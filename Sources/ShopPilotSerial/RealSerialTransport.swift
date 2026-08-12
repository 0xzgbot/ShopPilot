import Foundation
import ShopPilotCore

#if canImport(Combine)
import Combine
#endif

// MARK: - Serial Port Info

/// Enriched serial port information.
public struct SerialPortInfo: Codable, Equatable {
    public let path: String
    public let description: String
    
    public init(path: String, description: String) {
        self.path = path
        self.description = description
    }
}

// MARK: - Real Serial Transport

/// Real serial port transport for CNC machines.
public final class RealSerialTransport: MachineTransport, @unchecked Sendable {
    
    // MARK: - Internal State
    
    private let serialQueue = DispatchQueue(label: "com.shoppilot.serial")
    /// SPK-1401h — one-writer-at-a-time gate for port writes AND termios
    /// configuration. Previously `write(_:)` hit the FileHandle with no
    /// queue while `read()` used `serialQueue.sync`, so a concurrent
    /// streamer + status `?` + realtime `!` could byte-race on the wire.
    private let writeGate = SerialWriteGate()
    private var fileHandle: FileHandle?
    /// Multi-consumer event hub (session poll + streamer ok-wait + UI console).
    private let fanOut = TransportEventFanOut()
    private var monitorTask: Task<Void, Error>?
    private var isConnected = false
    
    // MARK: - AsyncStream
    
    public var events: AsyncStream<TransportEvent> {
        fanOut.subscribe()
    }
    
    // MARK: - Public API
    
    public init() {}
    
    // MARK: - Port Enumeration
    
    /// Enumerate available serial ports on macOS.
    public static func enumeratePorts() -> [String] {
        let ioResult = IOServiceMatching("IOUSBSerialDevice") as CFDictionary
        let _ = IOServiceGetMatchingServices(kIOMasterPortDefault, ioResult, nil)
        
        var ports: [String] = []
        
        // Check /dev/cu.* and /dev/tty.* for serial devices
        do {
            let fileManager = FileManager.default
            let rootContents = try fileManager.contentsOfDirectory(atPath: "/dev")
            
            for entry in rootContents where entry.hasPrefix("cu.") || entry.hasPrefix("tty.") {
                // Skip pseudo-terminals and network devices
                guard !entry.hasPrefix("cu.Bluetooth") &&
                      !entry.hasPrefix("tty modem") &&
                      !entry.hasPrefix("tty.X") &&
                      !entry.hasPrefix("tty.iphone") else { continue }
                
                ports.append("/dev/\(entry)")
            }
        } catch {
            // Fallback: return empty list if enumeration fails
        }
        
        return ports.sorted()
    }
    
    /// Get enriched port descriptions.
    public static func portDescriptions() async -> [SerialPortInfo] {
        let ports = enumeratePorts()
        return ports.map { path in
            let description = describePort(path)
            return SerialPortInfo(path: path, description: description)
        }
    }
    
    private static func describePort(_ path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        
        if fileName.contains("FTDI") || fileName.contains("ftdi") {
            return "FTDI USB-to-Serial"
        } else if fileName.contains("CP210") || fileName.contains("cp210") {
            return "Silicon Labs CP210x USB-to-Serial"
        } else if fileName.contains("CH340") || fileName.contains("ch340") {
            return "WCH CH340 USB-to-Serial"
        } else if fileName.contains("PL2303") || fileName.contains("pl2303") {
            return "Prolific PL2303 USB-to-Serial"
        } else if fileName.hasPrefix("cu.Bluetooth") || fileName.hasPrefix("tty.Bluetooth") {
            return "Bluetooth Serial"
        } else if fileName.hasPrefix("cu.usbmodem") || fileName.hasPrefix("tty.usbmodem") {
            return "USB Modem (Arduino/ESP)"
        } else if fileName.hasPrefix("cu.usbserial") || fileName.hasPrefix("tty.usbserial") {
            return "USB Serial Adapter"
        } else {
            return "Serial Port: \(fileName)"
        }
    }
    
    // MARK: - Connection Management
    
    public func open(config: ShopPilotCore.SerialConfig) async throws {
        guard !isConnected else { return }
        
        let path = config.portName
        
        guard FileManager.default.fileExists(atPath: path) else {
            throw RealSerialTransportError.portNotFound(path)
        }
        
        // Open the serial port for reading AND writing.
        // A write-only handle cannot receive data, which silently killed the
        // RX monitor path. (SPK review pass 2026-07-31)
        let handle = FileHandle(forUpdatingAtPath: path)
        guard handle != nil else {
            throw RealSerialTransportError.cannotOpenPort(path)
        }
        
        self.fileHandle = handle
        
        // Apply Darwin termios 8N1 at the requested baud rate. The baud
        // from config must NOT be discarded (SPK-1401b) — a port left at the
        // OS-default rate (often 9600) would silently mis-clock a 115200
        // GRBL controller.
        try configureSerial(baudRate: config.baudRate)
        
        isConnected = true
        
        // Start monitoring for incoming data
        startDataMonitoring()
        
        // Emit connected event
        fanOut.yield(TransportEvent.connected)
    }
    
    public func close() async {
        guard isConnected else { return }
        
        monitorTask?.cancel()
        monitorTask = nil
        
        fileHandle?.closeFile()
        fileHandle = nil
        
        isConnected = false
        
        fanOut.yield(TransportEvent.disconnected)
        fanOut.finish()
    }
    
    public func write(_ data: Data) async throws {
        guard let handle = fileHandle, isConnected else {
            throw RealSerialTransportError.notConnected
        }

        // SPK-1401h — every write (streamer G-code, status `?`, realtime
        // `!`/`~`/0x18) serializes through the write gate, so two writers
        // can never interleave mid-frame on the port.
        do {
            try writeGate.synchronized {
                try handle.write(contentsOf: data)
            }
        } catch {
            throw RealSerialTransportError.ioError(error.localizedDescription)
        }
    }
    
    public func read() async throws -> Data {
        guard isConnected else {
            throw RealSerialTransportError.notConnected
        }
        
        return try serialQueue.sync {
            guard let handle = fileHandle else {
                return Data()
            }
            return handle.availableData
        }
    }
    
    // MARK: - Serial Configuration
    
    private func configureSerial(baudRate: Int) throws {
        guard let handle = fileHandle else {
            throw RealSerialTransportError.notConnected
        }

        // SPK-1401h — configuration shares the write gate: termios applies
        // under the same lock as port writes, so a write can never land
        // mid-tcsetattr (and vice versa).
        try writeGate.synchronized {
            // Real termios configuration via Darwin (same approach as
            // ORSSerialPort): raw mode + 8N1 frame + requested baud.
            let settings = SerialTermiosSettings.make(baud: baudRate)
            var t = termios()

            guard tcgetattr(handle.fileDescriptor, &t) == 0 else {
                throw RealSerialTransportError.termiosError("tcgetattr failed")
            }

            // Raw mode: no echo, no canonical buffering, no IXON/IXOFF software
            // flow control — byte-exact TX/RX for GRBL/FluidNC streaming.
            cfmakeraw(&t)

            // 8N1 (8 data bits, no parity, 1 stop bit) at the requested baud.
            // The transformation is a pure, port-free function so the verify CLT
            // asserts it without hardware.
            settings.apply8N1(to: &t)

            guard tcsetattr(handle.fileDescriptor, TCSANOW, &t) == 0 else {
                throw RealSerialTransportError.termiosError("tcsetattr failed")
            }

            // SPK-1401g — custom baud rates (e.g. 250000) have no termios speed
            // constant; apply them via the Darwin IOSSIOSPEED ioctl so the
            // transport actually runs at the requested rate instead of silently
            // falling back to B9600. No-op for standard rates.
            settings.applyCustomBaud(to: handle.fileDescriptor)
        }
    }
    
    // MARK: - Data Monitoring
    
    private func startDataMonitoring() {
        monitorTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled, let handle = self.fileHandle, self.isConnected {
                // Check for available data (non-blocking)
                if let availableData = try? handle.availableData, !availableData.isEmpty {
                    fanOut.yield(.dataReceived(availableData))
                }
                
                // Small delay to prevent busy-waiting
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
}

// MARK: - Serial Monitor

/// Monitors a serial port for incoming data.
public final class SerialMonitor: ObservableObject {
    
    @Published public var receivedData: [Data] = []
    @Published public var lastMessage: String?
    @Published public var isConnected = false
    
    private var transport: RealSerialTransport?
    private var monitorTask: Task<Void, Never>?
    
    /// Start monitoring the given transport.
    public func start(transport: RealSerialTransport) {
        self.transport = transport
        isConnected = true
        
        monitorTask = Task { [weak self] in
            guard let self else { return }
            
            for await event in transport.events {
                switch event {
                case .dataReceived(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await MainActor.run {
                            self.receivedData.append(data)
                            self.lastMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    
                case .connected:
                    await MainActor.run { [weak self] in
                        self?.isConnected = true
                    }
                    
                case .disconnected:
                    await MainActor.run { [weak self] in
                        self?.isConnected = false
                    }
                    
                case .error(let message):
                    await MainActor.run { [weak self] in
                        self?.lastMessage = "Error: \(message)"
                    }
                }
            }
        }
    }
    
    /// Stop monitoring.
    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        isConnected = false
    }
}

// MARK: - Errors

/// Errors specific to real serial transport operations.
public enum RealSerialTransportError: LocalizedError, Sendable {
    case portNotFound(String)
    case cannotOpenPort(String)
    case notConnected
    case ioError(String)
    case termiosError(String)
    
    public var errorDescription: String? {
        switch self {
        case .portNotFound(let path):
            return "Serial port not found: \(path)"
        case .cannotOpenPort(let path):
            return "Cannot open serial port: \(path)"
        case .notConnected:
            return "Not connected to a serial port"
        case .ioError(let message):
            return "I/O error: \(message)"
        case .termiosError(let message):
            return "Termios configuration error: \(message)"
        }
    }
}
