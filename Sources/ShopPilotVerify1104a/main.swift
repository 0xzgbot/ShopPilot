import Foundation
import ShopPilotCore

/// SPK-1104a verify (CLT machines, no XCTest).
///
/// Covers: Machine stage receiving session.gcodeLines into the
/// MachineSession buffer (`loadGCode`) WITHOUT auto-run:
///   1. loadGCode buffers the exact lines (buffer == session gcodeLines).
///   2. Loading alone never streams: runJob() throws .notConnected when no
///      transport is attached (no hidden auto-run on load).
///   3. Loading while connected sends ZERO bytes to the transport — the
///      buffer is passive until the user explicitly calls runJob().
///   4. runJob() streams exactly the buffered lines (nothing more, nothing
///      less), proving the buffer is what the explicit run consumes.
///   5. Re-loading replaces the buffer (send-to-machine twice = replace,
///      not append).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Minimal spy transport: counts writes, replies "ok" to every command so
/// the GRBL ok-wait streamer can complete. `events` returns a fresh
/// fan-out subscription per consumer (same contract as SimulatorTransport).
final class SpyTransport: MachineTransport, @unchecked Sendable {
    private let fanOut = TransportEventFanOut()
    private let lock = NSLock()
    private var _writes: [String] = []

    var events: AsyncStream<TransportEvent> { fanOut.subscribe() }

    var writes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _writes
    }

    func open(config: SerialConfig) async throws {
        fanOut.yield(.connected)
    }

    func close() async {
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    func write(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self)
        recordWrite(text)
        fanOut.yield(.dataReceived(Data("ok\n".utf8)))
    }

    func read() async throws -> Data { Data() }

    /// Synchronous mutation helper so NSLock is never touched from an async
    /// context (Swift 6 forbids it).
    private func recordWrite(_ text: String) {
        lock.lock()
        _writes.append(text)
        lock.unlock()
    }
}

func verify() async throws {
    // The Machine stage receives session.gcodeLines — a typical post-processed job.
    let sessionLines = [
        "G21 ; set units to mm",
        "G90 ; absolute positioning",
        "G0 Z5",
        "G0 X0 Y0",
        "G1 Z-1 F100",
        "G1 X50 F500",
        "G1 X50 Y50",
        "G1 X0 Y50",
        "G1 X0 Y0",
        "G0 Z5",
        "M2",
    ]

    // 1. Buffer load: MachineSession.loadGCode captures the lines verbatim.
    let session = MachineSession()
    session.loadGCode(sessionLines)
    try expect(session.gcodeBuffer == sessionLines, "gcodeBuffer equals session gcodeLines")
    try expect(session.gcodeBuffer.count == sessionLines.count, "buffer count matches (\(session.gcodeBuffer.count))")

    // 2. No auto-run when disconnected: loading must not start streaming.
    try expect(!session.isConnected, "session is not connected after load")
    do {
        try await session.runJob()
        throw VerifyError.failed("runJob without transport should throw notConnected (no auto-run)")
    } catch let error as MachineSessionError {
        if case .notConnected = error {
            // Expected: nothing ran; buffer is passive.
        } else {
            throw VerifyError.failed("unexpected error: \(error)")
        }
    }

    // 3. No auto-run when connected: connecting + loading sends zero bytes.
    let spy = SpyTransport()
    try await session.connect(transport: spy)
    try expect(session.isConnected, "session connected to spy transport")
    try expect(spy.writes.isEmpty, "connect alone writes nothing")

    session.loadGCode(sessionLines)
    try expect(spy.writes.isEmpty, "loadGCode while connected sends ZERO bytes (no auto-run)")
    try expect(session.gcodeBuffer == sessionLines, "buffer unchanged by connect")

    // 4. Explicit runJob() streams exactly the buffered lines.
    try await session.runJob()
    try expect(spy.writes.count == sessionLines.count, "runJob streamed all \(sessionLines.count) lines (got \(spy.writes.count))")

    let trimmedWrites = spy.writes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    try expect(trimmedWrites == sessionLines, "streamed lines match buffered gcodeLines exactly")

    // 5. Re-loading replaces the buffer (send-to-machine twice = replace).
    let secondSend = ["G0 X1 Y1", "M2"]
    session.loadGCode(secondSend)
    try expect(session.gcodeBuffer == secondSend, "re-load replaces buffer (not append)")

    print("SPK-1104a verification: PASS")
    print("  session.gcodeLines -> MachineSession.gcodeBuffer verbatim (\(sessionLines.count) lines)")
    print("  no auto-run on load (0 bytes written until explicit runJob)")
    print("  runJob streams exactly the buffered lines; re-load replaces buffer")
}

// Top-level async entry (CLT — no @main to keep the repo's main.swift pattern).
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await verify()
        semaphore.signal()
    } catch {
        fputs("SPK-1104a verification: FAIL — \(error)\n", stderr)
        exit(1)
    }
}
semaphore.wait()
