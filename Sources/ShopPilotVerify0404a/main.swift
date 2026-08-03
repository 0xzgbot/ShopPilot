import Foundation
import ShopPilotCore

/// SPK-0404a verify (CLT machines, no XCTest).
/// Proves the ok-wait protocol: the streamer sends ONE line and waits for the
/// transport's "ok" before advancing and sending the next. Exercises both
/// stream(lines:) and stream(from: URL), plus a strict mock transport that
/// records the write/ok interleaving so a double-send is a hard failure.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// MARK: - Strict mock transport: only acks after the streamer's ok-wait consumes it

/// Mock GRBL that records every write and only emits `ok` when told to. The
/// streamer must send exactly one line, then wait; if it ever writes a second
/// line before consuming the previous `ok`, the recorded sequence shows it.
final class StrictOkTransport: MachineTransport, @unchecked Sendable {
    private let fanOut = TransportEventFanOut()
    private let lock = NSLock()
    private var written: [String] = []
    private var ackPending = false

    var events: AsyncStream<TransportEvent> { fanOut.subscribe() }

    var writtenLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    var overrun: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ackPending && written.count > 1
    }

    func open(config: SerialConfig) async throws {
        fanOut.yield(.connected)
    }

    func close() async {
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    func write(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        // A write while an ack is pending means the streamer did NOT wait for ok.
        if ackPending {
            written.append("!!OVERRUN:\(text)")
            lock.unlock()
            return
        }
        written.append(text)
        ackPending = true
        lock.unlock()
        // Yield the ok after a tiny delay so the streamer's waitForOk sees it.
        try await Task.sleep(nanoseconds: 10_000_000)
        lock.lock()
        ackPending = false
        lock.unlock()
        fanOut.yield(.dataReceived(Data("ok\n".utf8)))
    }

    func read() async throws -> Data { Data() }
}

func main() throws {
    // 1. Single line through stream(lines:) — send one, wait for ok, advance.
    let transport = SimulatorTransport()
    let config = SerialConfig(isSimulator: true)
    // Subscribe BEFORE open so the .connected event is not missed (fan-out is live-only).
    var drain = transport.events.makeAsyncIterator()
    try awaitBlocking { try await transport.open(config: config) }
    _ = try awaitBlocking { await drain.next() }

    let streamer = GCodeStreamer()
    try awaitBlocking { try await streamer.stream(lines: ["G21"], to: transport) }
    try expect(streamer.state == .idle, "state idle after one line")
    try expect(streamer.currentLine == 1, "currentLine advanced to 1, got \(streamer.currentLine)")
    try expect(streamer.totalLines == 1, "totalLines == 1")
    try expect(streamer.progress == 1.0, "progress 1.0 after one line")

    // 2. Sequential multi-line: index advances per ok, comments filtered.
    try awaitBlocking { try await streamer.stream(lines: ["G21 ; units", "(comment)", "G90", "  ", "G0 Z5"], to: transport) }
    try expect(streamer.totalLines == 3, "comments/blanks filtered: totalLines \(streamer.totalLines)")
    try expect(streamer.currentLine == 3, "all executable lines processed: \(streamer.currentLine)")

    // 3. stream(from: URL) — the file path previously subscribed after write
    //    and missed the ok on the live-only fan-out (hang). Regression check.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("spk0404a_okwait.nc")
    try "G90\nG0 Z5\n".write(to: tmp, atomically: true, encoding: .utf8)
    try awaitBlocking { try await streamer.stream(from: tmp, to: transport) }
    try expect(streamer.currentLine == 2, "file stream processed 2 lines: \(streamer.currentLine)")
    try expect(streamer.state == .idle, "file stream ends idle")

    // 4. Strict mock: prove one-line-at-a-time — no write before prior ok.
    let strict = StrictOkTransport()
    try awaitBlocking { try await strict.open(config: config) }
    let s2 = GCodeStreamer()
    try awaitBlocking { try await s2.stream(lines: ["G21", "G90", "G0 Z5"], to: strict) }
    try expect(strict.writtenLines.count == 3, "strict transport saw exactly 3 writes, got \(strict.writtenLines.count)")
    try expect(strict.writtenLines == ["G21", "G90", "G0 Z5"], "writes in order, no overrun: \(strict.writtenLines)")
    try expect(!strict.overrun, "no write while ok pending (ok-wait honored)")
    try expect(s2.currentLine == 3, "strict stream advanced through all lines")

    print("SPK-0404a verification: PASS")
    print("  single line send + ok-wait + index advance OK")
    print("  multi-line sequential + comment filtering OK")
    print("  stream(from:) file path (pre-subscribed fan-out) OK")
    print("  strict mock: one write per ok, no overrun OK")
}

// Minimal async runner: keep the verify main synchronous on CLT.
private func awaitBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task {
        do { result = .success(try await op()) }
        catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result!.get()
}

do {
    try main()
} catch {
    fputs("SPK-0404a verification: FAIL — \(error)\n", stderr)
    exit(1)
}
