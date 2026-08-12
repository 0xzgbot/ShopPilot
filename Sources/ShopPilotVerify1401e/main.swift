import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-1401e verify (CLT machines, no XCTest).
/// Single realtime writer: one user Hold → EXACTLY ONE `!` (0x21) on the
/// wire; one user Reset → EXACTLY ONE 0x18 (Ctrl-X) on the wire.
///
/// The user-facing path is `MachineController.hold()/reset()` (app target —
/// not importable from this CLT). Those are now thin delegates that call
/// `MachineSession.hold()/reset()` ONLY; they no longer also call
/// `streamer.pause()/reset()`, which used to put a second byte on the wire.
/// This verify drives the Core seam those delegates call — the session —
/// in the exact app state that used to double-write: a streamer armed with
/// the SAME transport (post-job state) attached to the session. Bytes are
/// counted (not just present) on the shared transport's write log.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func countByte(_ data: Data, _ byte: UInt8) -> Int {
    data.reduce(0) { $0 + ($1 == byte ? 1 : 0) }
}

func main() async throws {
    // Shared recording transport: every raw byte written lands in
    // writtenBytesSnapshot — the race-free observable for realtime-byte
    // assertions (SPK-1104d).
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }

    // Long poll interval so the 1401f `?` poller cannot fire inside the
    // byte-count windows (it writes once on attach, then stays silent).
    let session = MachineSession(statusPollInterval: .seconds(600))
    session.attach(transport: transport)
    try expect(session.isConnected, "session attached and connected")

    // Worst case that used to double-write: the streamer holds the SAME
    // transport (post-job state) and is attached to the session — a bare
    // session.hold() used to write `!` twice (streamer.pause() + session).
    let streamer = GCodeStreamer()
    try await streamer.stream(lines: ["G0 X1"], to: transport) // arms transport
    session.attachStreamer(streamer)

    let baselineBang = countByte(await transport.writtenBytesSnapshot, 0x21)
    let baselineReset = countByte(await transport.writtenBytesSnapshot, 0x18)
    try expect(baselineBang == 0 && baselineReset == 0,
               "setup wrote no realtime bytes (bang=\(baselineBang), reset=\(baselineReset))")

    // ── User Hold → EXACTLY ONE `!` ─────────────────────────────────────
    await session.hold()
    let afterHold = await transport.writtenBytesSnapshot
    try expect(countByte(afterHold, 0x21) == baselineBang + 1,
               "HOLD wrote exactly one `!` (0x21), got \(countByte(afterHold, 0x21) - baselineBang)")
    try expect(countByte(afterHold, 0x18) == baselineReset,
               "HOLD wrote no 0x18")
    try expect(streamer.state == .paused,
               "session hold still pauses the stream loop (state \(streamer.state))")

    // ── User Reset → EXACTLY ONE 0x18 ───────────────────────────────────
    await session.reset()
    let afterReset = await transport.writtenBytesSnapshot
    try expect(countByte(afterReset, 0x18) == baselineReset + 1,
               "RESET wrote exactly one 0x18, got \(countByte(afterReset, 0x18) - baselineReset)")
    try expect(countByte(afterReset, 0x21) == baselineBang + 1,
               "RESET wrote no `!`")
    try expect(streamer.state == .idle,
               "session reset still clears the stream loop state (state \(streamer.state))")
    try expect(session.connectionState == .connected,
               "session reset keeps connection state connected")

    // ── Direct Core APIs unchanged ──────────────────────────────────────
    // GCodeStreamer.reset() (buffer reset) must still write its 0x18.
    await streamer.reset()
    let afterDirectReset = await transport.writtenBytesSnapshot
    try expect(countByte(afterDirectReset, 0x18) == baselineReset + 2,
               "GCodeStreamer.reset() still writes 0x18 for buffer reset")

    print("1401e: PASS — single realtime writer")
}

do {
    try await main()
} catch {
    print("1401e: FAIL — \(error)")
    exit(1)
}
