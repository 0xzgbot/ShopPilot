import Foundation

// MARK: - MockTransport

/// A test-only transport that captures every byte written and replays events.
///
/// Unlike the live-only `TransportEventFanOut` (whose `AsyncStream` registers
/// its continuation eagerly at stream creation), `MockTransport` records every
/// emitted event and replays the history to each new subscriber. Tests may
/// therefore subscribe *after* `open()`/`write()`/`close()` and still observe
/// the events those calls produced — no timing coupling.

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

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<TransportEvent>.Continuation] = [:]
    private var history: [TransportEvent] = []
    private var isFinished = false

    public var events: AsyncStream<TransportEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.lock.lock()
            self.continuations[id] = continuation
            let replay = self.history
            let finished = self.isFinished
            self.lock.unlock()

            // Replay everything emitted before this subscriber registered.
            for event in replay {
                continuation.yield(event)
            }
            if finished {
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    public init() {}

    public func open(config: SerialConfig) async throws {
        emit(.connected)
    }

    public func close() async {
        emit(.disconnected)
        lock.lock()
        isFinished = true
        let live = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in live {
            continuation.finish()
        }
    }

    public func write(_ data: Data) async throws {
        writtenBytes.append(data)
        // Simulate GRBL processing latency before acknowledging, mirroring
        // SimulatorTransport.
        try await Task.sleep(nanoseconds: 20_000_000) // 20 ms
        // Real GRBL controllers acknowledge each command with "ok"; emit the
        // same so the streamer's ok-wait loop can progress in tests.
        emit(.dataReceived(Data("ok\n".utf8)))
    }

    public func read() async throws -> Data {
        Data()
    }

    // MARK: - Private

    private func emit(_ event: TransportEvent) {
        lock.lock()
        history.append(event)
        let live = Array(continuations.values)
        lock.unlock()
        for continuation in live {
            continuation.yield(event)
        }
    }
}
