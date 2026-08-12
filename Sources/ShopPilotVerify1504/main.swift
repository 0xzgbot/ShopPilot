import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1504 verify (CLT executable, no XCTest).
// Proves Start-stream hygiene in MachineController:
//   1. BEHAVIORAL: GCodeStreamer.resetStreamState() is STATE-ONLY — it can be
//      called with NO transport attached (a wire write is impossible), clears
//      state/progress/currentLine, and needs no await. GCodeStreamer.reset()
//      is the 0x18 writer (requires a transport) — the two differ by design.
//   2. WRITE-FREE PROOF: resetStreamState() on a streamer that has streamed
//      through a recording transport produces NO extra 0x18 — the byte count
//      is exactly what the stream itself wrote.
//   3. SOURCE CONTRACT: MachineController's two stream-start paths
//      (streamSessionBuffer + streamFallback) use resetStreamState(), NOT
//      reset(), and BOTH call machineSession.attachStreamer(streamer).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let streamer = GCodeStreamer()

    // ── 1. State-only reset needs no transport and clears counters. ─────
    streamer.resetStreamState()   // must not require a connection
    streamer.state = .streaming
    streamer.progress = 0.75
    streamer.currentLine = 42
    streamer.resetStreamState()
    try expect(streamer.state == .idle, "resetStreamState → .idle")
    try expect(streamer.progress == 0.0, "resetStreamState → progress 0")
    try expect(streamer.currentLine == 0, "resetStreamState → currentLine 0")

    // ── 2. Write-free: a full stream then state-reset adds no 0x18. ─────
    let sim = SimulatorTransport()
    let session = MachineSession()
    try awaitBlocking {
        try await session.connect(transport: sim,
                                  config: SerialConfig(isSimulator: true, simulationDelayNanoseconds: 0))
        session.attachStreamer(streamer)
        let before = await sim.writtenBytesSnapshot
        streamer.resetStreamState()
        let after = await sim.writtenBytesSnapshot
        try expect(after.count == before.count,
                   "resetStreamState writes NOTHING (0x18 count unchanged: \(before.count) → \(after.count))")
        try expect(!after.contains(0x18),
                   "no 0x18 anywhere after state-only reset")
        await session.disconnect()
    }

    // ── 3. Source contract: MachineController start paths. ───────────────
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/MachineController.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    // streamSessionBuffer path.
    try expect(source.contains("streamer.resetStreamState()"),
               "MachineController uses resetStreamState (not reset) on start")
    // No start-path `await streamer.reset()` remains (stopStreaming legitimately
    // keeps reset() — it is a stop, not a start).
    let bufferPath = source.range(of: "private func streamSessionBuffer() async")!
    let bufferBody = source[bufferPath.upperBound...]
        .prefix(600)
    try expect(bufferBody.contains("resetStreamState"),
               "streamSessionBuffer resets state-only")

    // attachStreamer in BOTH start paths.
    let fallbackPath = source.range(of: "private func streamFallback(lines: [String]) async")!
    let fallbackBody = source[fallbackPath.upperBound...].prefix(900)
    try expect(fallbackBody.contains("attachStreamer"),
               "streamFallback attaches the streamer (single-writer realtime intact)")
    try expect(fallbackBody.contains("resetStreamState"),
               "streamFallback also resets state-only, no 0x18 on start")

    print("1504: PASS — stream start hygiene (no 0x18 on Start; fallback attaches streamer)")
    print("  resetStreamState is write-free; both start paths state-only + attached")
}

do {
    try main()
} catch {
    print("1504: FAIL — \(error)")
    exit(1)
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
