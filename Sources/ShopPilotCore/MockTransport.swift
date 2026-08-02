import Foundation

// MARK: - MockTransport

/// A test-only transport that captures every byte written and replays events.

public final class MockTransport: MachineTransport {

    /// All data written via `write(_)` in chronological order.
    public private(set) var writtenBytes: [Data] = []

    /// Convenience: concatenated bytes as a single string.
    public var writtenText: String {
        writtenBytes.map { String(decoding: $0, as: UTF8.self) }.joined()
    }

    /// Convenience: concatenated bytes as a single Data.
    public var writtenData: Data {
        writtenBytes.reduce(Data()) { $0 + $1 }
    }

    /// Clear all captured bytes.
    public func clearCaptured() {
        writtenBytes.removeAll()
    }

    // MARK: - MachineTransport

    private let fanOut = TransportEventFanOut()

    public var events: AsyncStream<TransportEvent> {
        fanOut.subscribe()
    }

    public init() {}

    public func open(config: SerialConfig) async throws {
        fanOut.yield(.connected)
    }

    public func close() async {
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    public func write(_ data: Data) async throws {
        writtenBytes.append(data)
    }

    public func read() async throws -> Data {
        Data()
    }
}
