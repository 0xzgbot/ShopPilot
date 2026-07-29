import Foundation

// MARK: - TransportEvent

/// Events emitted by a MachineTransport over its AsyncStream.
public enum TransportEvent: Sendable {
    /// Transport successfully opened and ready for I/O.
    case connected
    /// Transport closed or lost connection.
    case disconnected
    /// Raw data received from the machine/controller.
    case dataReceived(Data)
    /// An error occurred on the transport layer.
    case error(String)
}

// MARK: - MachineTransport

/// Protocol abstracting serial / simulator transport for CNC machines.
public protocol MachineTransport: AnyObject, Sendable {
    /// Stream of TransportEvent values emitted by this transport.
    var events: AsyncStream<TransportEvent> { get }

    /// Open the transport with the given configuration.
    func open(config: SerialConfig) async throws

    /// Close the transport (graceful shutdown).
    func close() async

    /// Write raw data to the machine/controller.
    func write(_ data: Data) async throws
}

// MARK: - SerialConfig

/// Configuration for a serial / simulator connection.
public struct SerialConfig: Codable, Identifiable, Sendable {
    public let id = UUID()
    public let baudRate: Int
    public let portName: String
    public let isSimulator: Bool

    public init(baudRate: Int = 115200, portName: String = "/dev/ttyUSB0", isSimulator: Bool = false) {
        self.baudRate = baudRate
        self.portName = portName
        self.isSimulator = isSimulator
    }

    // Custom CodingKeys to exclude computed `id` from JSON encoding.
    enum CodingKeys: String, CodingKey {
        case baudRate
        case portName
        case isSimulator
    }
}

// MARK: - SimulatorTransport

/// A thread-safe simulator transport that mimics GRBL v1.x behaviour.
///
/// Simulated responses:
///   `?`  → `<Idle|MPos:0.000,0.000,0.000|WPos:0.000,0.000,0.000|FS:0,0>`
///   `G0 X… Y…` → simulated motion with updated position feedback.
public final class SimulatorTransport: MachineTransport {

    // MARK: - Internal state (protected by actor)

    private let actor = TransportActor()

    // MARK: - AsyncStream plumbing

    private let (stream, continuation) = AsyncStream<TransportEvent>.makeStream()

    public var events: AsyncStream<TransportEvent> {
        stream
    }

    // MARK: - Public API

    public init() {}

    // MARK: Open / Close / Write

    public func open(config: SerialConfig) async throws {
        try await actor.open()
        continuation.yield(.connected)
    }

    public func close() async {
        await actor.close()
        continuation.yield(.disconnected)
    }

    public func write(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        // Simulate processing delay.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        let response = try await actor.handleCommand(text)
        continuation.yield(.dataReceived(Data(response.utf8)))
    }
}

// MARK: - TransportActor (thread-safe state)

/// Actor that encapsulates all mutable state for SimulatorTransport.
private actor TransportActor {
    private var isConnected = false
    private var mPos: (x: Double, y: Double, z: Double) = (0.0, 0.0, 0.0)

    func open() throws {
        guard !isConnected else { return }
        isConnected = true
        // Simulate connection delay — caller handles Task.sleep.
    }

    func close() async {
        guard isConnected else { return }
        isConnected = false
        mPos = (0.0, 0.0, 0.0)
    }

    func handleCommand(_ text: String) throws -> String {
        guard isConnected else {
            throw MachineTransportError.disconnected
        }

        if text == "?" {
            return statusString()
        } else if text.hasPrefix("G0 ") || text.hasPrefix("G00 ") {
            mPos = try parseAndApplyMove(text)
            return statusString()
        } else if text.hasPrefix("G1 ") || text.hasPrefix("G01 ") {
            mPos = try parseAndApplyMove(text)
            return statusString()
        } else if text == "G28" {
            mPos = (0.0, 0.0, 0.0)
            return "<Idle|MPos:0.000,0.000,0.000|WPos:0.000,0.000,0.000|FS:0,0>"
        } else {
            return "ok"
        }
    }

    private func statusString() -> String {
        let x = formatted(mPos.x)
        let y = formatted(mPos.y)
        let z = formatted(mPos.z)
        return "<Idle|MPos:\(x),\(y),\(z)|WPos:\(x),\(y),\(z)|FS:0,0>"
    }

    private func formatted(_ value: Double) -> String {
        var output = ""
        output.append(String(format: "%.3f", value))
        return output
    }

    private func parseAndApplyMove(_ line: String) throws -> (x: Double, y: Double, z: Double) {
        var x = mPos.x
        var y = mPos.y
        var z = mPos.z

        let tokens = line.split(separator: " ")
        for token in tokens {
            if let value = parseCoordinate(token, prefix: "X") { x = value }
            else if let value = parseCoordinate(token, prefix: "Y") { y = value }
            else if let value = parseCoordinate(token, prefix: "Z") { z = value }
        }

        return (x, y, z)
    }

    private func parseCoordinate(_ token: Substring, prefix: String) -> Double? {
        guard token.hasPrefix(prefix) else { return nil }
        let valueString = String(token.dropFirst(prefix.count))
        return Double(valueString)
    }
}

// MARK: - Error

/// Errors that can occur on a MachineTransport.
public enum MachineTransportError: LocalizedError, Sendable {
    case disconnected
    case invalidConfig(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .disconnected:
            return "Transport is not connected"
        case .invalidConfig(let reason):
            return "Invalid configuration: \(reason)"
        case .ioError(let message):
            return "I/O error: \(message)"
        }
    }
}
