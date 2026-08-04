import Foundation
import Combine
import ShopPilotCore

/// SPK-0418 verify (CLT machine, no XCTest).
/// Proves the LARGE-FILE STREAM STRESS contract on the simulator:
///   1. A 10,000-line job streams through the REAL `SimulatorTransport`
///      (fast config — the new `SerialConfig.simulationDelayNanoseconds`
///      knob) with ZERO lost oks: every command line reaches the transport
///      exactly once, in order (written-bytes audit), and the streamer
///      settles on currentLine == totalLines == 10_000.
///   2. Progress updates are THROTTLED (0.1s window): the @Published sink
///      observes far fewer samples than lines (bounded < 250 for a 10k
///      stream) — the UI cannot be flooded, i.e. no freeze path on large
///      files; progress still reaches 1.0.
///   3. HOLD / RESUME work MID-STREAM: pause() while streaming flips
///      state to .paused and the line counter freezes (<= 1 in-flight line
///      over a 250ms window); the GRBL `!` byte is on the wire; resume()
///      sends `~` and the job completes.
///   4. The file entry `stream(from:to:)` also carries a 10k-line file end
///      to end with all oks accounted.
/// The UI glue (RUN button → MachineSession.runJob → streamer, Hold/Resume
/// chrome → MachineSession.hold/resume → streamer.pause/resume) is covered
/// by the app build; the streamer IS the machine path.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// A 10,000-line zigzag job: alternating rapids/cuts, coordinates inside
/// 0..49 — comfortably inside the sim's 500mm travel envelope, so every
/// line earns a plain `ok` and no soft-limit alarm can fire.
func makeStressJob(lineCount: Int = 10_000) -> [String] {
    (0..<lineCount).map { i in
        let x = Double(i % 50)
        let y = Double((i / 50) % 50)
        return i % 2 == 0 ? "G0 X\(x) Y\(y)" : "G1 X\(x) Y\(y)"
    }
}

/// Audit the transport's written-bytes log: strip the hold/resume realtime
/// bytes, then every command line must appear exactly once, in order.
func writtenCommandLines(_ transport: SimulatorTransport) async -> [String] {
    let data = await transport.writtenBytesSnapshot
    var cleaned = Data()
    for byte in data {
        if byte == 0x21 || byte == 0x7E { continue } // '!' and '~'
        cleaned.append(byte)
    }
    return String(decoding: cleaned, as: UTF8.self)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func main() async throws {
    let job = makeStressJob()
    try expect(job.count == 10_000, "stress job has 10,000 lines")
    try expect(job.allSatisfy { $0.hasPrefix("G0 ") || $0.hasPrefix("G1 ") }, "stress job is all executable moves")

    let transport = SimulatorTransport()
    // Tiny per-line delay (0.2ms): the 10k run takes ~2s — fast enough for a
    // regression CLT, slow enough that the mid-stream hold is deterministic.
    try await transport.open(config: SerialConfig(isSimulator: true, simulationDelayNanoseconds: 200_000))
    defer { Task { await transport.close() } }

    let streamer = GCodeStreamer()
    var progressSamples: [Double] = []
    let cancellable = streamer.$progress.sink { progressSamples.append($0) }

    let run = Task { try await streamer.stream(lines: job, to: transport) }

    // ── 3. Hold mid-stream: let the stream begin, then catch it mid-flight. ─
    // The stream Task cannot run until main() suspends, so wait for .streaming.
    var startAttempts = 0
    while streamer.state == .idle && startAttempts < 2000 {
        try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        startAttempts += 1
    }
    try expect(streamer.state == .streaming, "stream started (state \(streamer.state))")

    var pausedLine = 0
    while streamer.state == .streaming {
        if streamer.currentLine >= 50 {
            await streamer.pause()
            try expect(streamer.state == .paused, "pause() flips state to .paused mid-stream")
            pausedLine = streamer.currentLine
            break
        }
        try await Task.sleep(nanoseconds: 2_000_000) // 2ms
    }
    try expect(streamer.state == .paused, "stream was caught mid-flight and paused (state \(streamer.state), line \(streamer.currentLine))")

    // Hold really holds: no more than one in-flight line in 250ms.
    try await Task.sleep(nanoseconds: 250_000_000)
    let frozenLine = streamer.currentLine
    try expect(frozenLine <= pausedLine + 1,
               "hold freezes the stream (paused at \(pausedLine), advanced to \(frozenLine))")
    let wire = await transport.writtenBytesSnapshot
    try expect(wire.contains(0x21), "GRBL hold byte '!' is on the wire")

    // ── Resume: `~` on the wire, stream runs to completion. ────────────────
    await streamer.resume()
    try expect(streamer.state == .streaming, "resume() flips state back to .streaming")
    let resumedWire = await transport.writtenBytesSnapshot
    try expect(resumedWire.contains(0x7E), "GRBL resume byte '~' is on the wire")

    try await run.value
    try expect(streamer.currentLine == 10_000, "stream completed all 10,000 lines (got \(streamer.currentLine))")
    try expect(streamer.totalLines == 10_000, "totalLines counted 10,000")
    try expect(streamer.state == .idle, "streamer settles to .idle on completion")
    try expect(abs(streamer.progress - 1.0) < 0.0001, "progress reaches 1.0")
    try expect(streamer.lastError == nil, "no stream error surfaced")

    // ── 1. No lost oks: written-bytes audit (hold/resume bytes stripped). ───
    let written = await writtenCommandLines(transport)
    try expect(written.count == 10_000, "every command line hit the wire exactly once (got \(written.count))")
    try expect(written == job, "wire commands match the job order exactly — zero lost oks")

    // ── 2. Throttled progress: far fewer publishes than lines. ──────────────
    try expect(progressSamples.count >= 2, "progress published at least start+end (\(progressSamples.count))")
    try expect(progressSamples.count < 250,
               "progress is throttled — \(progressSamples.count) publishes for 10,000 lines (no UI flood)")
    try expect(abs((progressSamples.last ?? -1) - 1.0) < 0.0001, "last progress sample is 1.0")
    try expect(abs((progressSamples.first ?? -1) - 0.0) < 0.0001, "first progress sample is 0.0")

    // ── 4. File entry: 10k-line file streams end to end. ────────────────────
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("shopPilot0418_stress_\(UUID().uuidString).nc")
    try job.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let fileTransport = SimulatorTransport()
    try await fileTransport.open(config: SerialConfig(isSimulator: true, simulationDelayNanoseconds: 0))
    defer { Task { await fileTransport.close() } }
    let fileStreamer = GCodeStreamer()
    try await fileStreamer.stream(from: url, to: fileTransport)
    try expect(fileStreamer.currentLine == 10_000, "file stream completed all 10,000 lines")
    try expect(abs(fileStreamer.progress - 1.0) < 0.0001, "file stream progress reaches 1.0")
    let fileWritten = await writtenCommandLines(fileTransport)
    try expect(fileWritten.count == 10_000 && fileWritten == job,
               "file stream wrote every line once, in order — no lost oks")

    _ = cancellable
    print("ShopPilotVerify0418: PASS — 10k-line stream on SimulatorTransport: zero lost oks (wire audit), throttled progress (\(progressSamples.count) publishes), hold freezes mid-stream, resume completes, file entry end-to-end")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify0418: FAIL — \(error)")
    exit(1)
}
