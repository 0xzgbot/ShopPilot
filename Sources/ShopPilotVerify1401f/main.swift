import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1401f verify (CLT machine, no XCTest).
// Proves the status polling loop actually WRITES the GRBL status-query byte
// '?' to the transport on an interval while a session is connected:
//   1. A recording transport sees '?' bytes on the wire while the session is
//      live — >= 2 writes during a short run with a 20 ms poll interval.
//   2. The loop is cancellable and disconnected-safe: after disconnect() the
//      poll task is cancelled and no further bytes are written.
//
// The poller lives in ShopPilotCore (StatusPoller, owned by MachineSession);
// the app uses it automatically via MachineSession.connect/attach.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Records every byte written to it so the verify can prove '?' reached the
/// wire. Writes are instantaneous (no simulated delay), so the poll loop's
/// cadence is governed purely by its interval.
final class RecordingTransport: MachineTransport, @unchecked Sendable {
    private let fanOut = TransportEventFanOut()
    private let lock = NSLock()
    private var _writes: [Data] = []

    var events: AsyncStream<TransportEvent> { fanOut.subscribe() }

    var writes: [Data] {
        lock.lock(); defer { lock.unlock() }
        return _writes
    }

    func open(config: ShopPilotCore.SerialConfig) async throws {
        fanOut.yield(.connected)
    }

    func close() async {
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    func write(_ data: Data) async throws {
        recordWrite(data)
    }

    /// Synchronous, lock-protected append — NSLock calls must not sit directly
    /// in an async context (Swift 6 mode error).
    private func recordWrite(_ data: Data) {
        lock.lock()
        _writes.append(data)
        lock.unlock()
    }

    func read() async throws -> Data { Data() }
}

func verify() async throws {
    let transport = RecordingTransport()
    // 20 ms poll interval → ~10+ '?' writes in 250 ms of connected time.
    let session = MachineSession(statusPollInterval: .milliseconds(20))
    try await session.connect(transport: transport)
    try expect(session.isConnected, "session connected through the recording transport")

    // Let the poll loop run briefly while the session is live.
    try await Task.sleep(nanoseconds: 250_000_000)

    let liveWrites = transport.writes
    try expect(liveWrites.count >= 2,
               "status poll wrote '?' at least twice while connected (got \(liveWrites.count))")
    try expect(liveWrites.allSatisfy { $0 == Data("?".utf8) },
               "every poll write is exactly the GRBL status-query byte '?'")

    // Disconnect: the poll task is cancelled — no further writes may appear.
    await session.disconnect()
    let writesAfterDisconnect = transport.writes.count

    // Give any would-be straggler write a window to (incorrectly) appear.
    try await Task.sleep(nanoseconds: 150_000_000)
    try expect(transport.writes.count == writesAfterDisconnect,
               "no status writes after disconnect (got \(transport.writes.count - writesAfterDisconnect) more)")

    print("1401f: PASS — status poll sends ?")
}

// Top-level async entry (CLT — the repo's main.swift pattern, no @main).
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await verify()
        semaphore.signal()
    } catch {
        fputs("1401f: FAIL — \(error)\n", stderr)
        exit(1)
    }
}
semaphore.wait()
