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

    /// Read available data from the transport (non-blocking).
    /// Returns an empty `Data` when no data is available.
    func read() async throws -> Data
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

// MARK: - Event Fan-Out

/// Fan-out hub allowing multiple consumers to iterate the same transport event
/// stream. `AsyncStream` is single-consumer: with a single stored stream, the
/// session poll loop, `GCodeStreamer.waitForOk` and the UI console would steal
/// events from each other and streaming would hang or go blind. Each consumer
/// calls `subscribe()` and receives every event. (SPK review pass 2026-07-31)
public final class TransportEventFanOut: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<TransportEvent>.Continuation] = [:]

    public init() {}

    /// Subscribe a new consumer. The returned stream is finite: it terminates
    /// when the consumer's iterator is dropped or the hub is finished.
    public func subscribe() -> AsyncStream<TransportEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// Deliver an event to every live subscriber.
    public func yield(_ event: TransportEvent) {
        lock.lock()
        let live = Array(continuations.values)
        lock.unlock()
        for continuation in live {
            continuation.yield(event)
        }
    }

    /// Terminate all subscriptions (transport closed).
    public func finish() {
        lock.lock()
        let live = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in live {
            continuation.finish()
        }
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

    /// Multi-consumer event hub (session poll + streamer ok-wait + UI console).
    private let fanOut = TransportEventFanOut()

    public var events: AsyncStream<TransportEvent> {
        fanOut.subscribe()
    }

    // MARK: - Public API

    public init() {}

    // MARK: Open / Close / Write

    public func open(config: SerialConfig) async throws {
        try await actor.open()
        fanOut.yield(.connected)
    }

    public func close() async {
        await actor.close()
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    public func write(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        // Simulate processing delay.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        let response = try await actor.handleCommand(text)
        fanOut.yield(.dataReceived(Data(response.utf8)))
        try await actor.pushToReadBuffer(Data(response.utf8))
    }

    // MARK: - Read

    public func read() async throws -> Data {
        try await actor.drainReadBuffer()
    }
}

// MARK: - TransportActor (thread-safe state)

/// Actor that encapsulates all mutable state for SimulatorTransport.
private actor TransportActor {
    private var isConnected = false
    private var mPos: (x: Double, y: Double, z: Double) = (0.0, 0.0, 0.0)
    private var readBuffer = Data()

    func open() throws {
        guard !isConnected else { return }
        isConnected = true
    }

    func close() async {
        guard isConnected else { return }
        isConnected = false
        mPos = (0.0, 0.0, 0.0)
        readBuffer.removeAll()
    }

    func pushToReadBuffer(_ data: Data) {
        readBuffer.append(data)
    }

    func drainReadBuffer() async throws -> Data {
        guard isConnected else { throw MachineTransportError.disconnected }
        let data = readBuffer
        readBuffer.removeAll()
        return data
    }

    func handleCommand(_ text: String) async throws -> String {
        guard isConnected else {
            throw MachineTransportError.disconnected
        }

        if text == "?" {
            return statusString()
        } else if text.hasPrefix("G0 ") || text.hasPrefix("G00 ")
                    || text.hasPrefix("G0X") || text.hasPrefix("G0Y") || text.hasPrefix("G0Z")
                    || text.hasPrefix("G1 ") || text.hasPrefix("G01 ")
                    || text.hasPrefix("G1X") || text.hasPrefix("G1Y") || text.hasPrefix("G1Z") {
            // Motion commands update simulated position; GRBL replies with ok (not status).
            mPos = try parseAndApplyMove(text)
            return "ok"
        } else if text == "G28" {
            mPos = (0.0, 0.0, 0.0)
            return "ok"
        } else if text == "!" || text == "~" {
            return "ok"
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
