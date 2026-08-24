import Foundation
import ShopPilotCore

// SPK-1920h verify — streamer line index drives live progress; Hold stops both.
//
// AC1: while streaming, currentLine advances monotonically toward totalLines
//      (the same values the Preview LIVE playhead renders).
// AC2: pause() freezes the stream AND currentLine together — no further
//      advance while paused; resume() continues.
// AC3: StreamState.isPaused distinguishes held from streaming (what the UI keys on).

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD1920h: FAIL — \(msg)")
        exit(1)
    }
}

@MainActor
func run() async {
    let sim = SimulatorTransport()
    let streamer = GCodeStreamer()

    do {
        try await sim.open(config: ShopPilotCore.SerialConfig(baudRate: 115200, isSimulator: true))
    } catch {
        expect(false, "sim open failed: \(error)")
    }

    // Small program; the sim's per-line delay makes mid-stream observation reachable.
    var program: [String] = ["G21", "G90"]
    for i in 0..<12 {
        program.append("G0 X\(10 + i * 5) Y\(10 + i * 3)")
        program.append("G1 X\(14 + i * 5) F800")
    }
    streamer.totalLines = program.count

    // Stream in a detached task so we can observe progress live.
    let streamTask = Task {
        try? await streamer.stream(lines: program, to: sim)
    }

    // Wait until streaming is underway.
    for _ in 0..<50 where streamer.currentLine == 0 {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    expect(streamer.currentLine > 0, "streaming underway (currentLine \(streamer.currentLine))")

    // --- AC1: currentLine advances during streaming -------------------------
    let early = streamer.currentLine
    expect(early < streamer.totalLines, "mid-stream (\(early) of \(streamer.totalLines))")
    try? await Task.sleep(nanoseconds: 120_000_000)
    let later = streamer.currentLine
    expect(later > early, "currentLine advanced (\(early) → \(later)) — drives the LIVE playhead")

    // --- AC2: pause freezes stream + playhead together ----------------------
    await streamer.pause()
    expect(streamer.state.isPaused, "state paused after pause()")
    expect(!streamer.isStreaming, "isStreaming false while held")
    let frozen = streamer.currentLine
    try? await Task.sleep(nanoseconds: 250_000_000)
    expect(streamer.currentLine == frozen,
           "currentLine FROZEN during hold (\(frozen) == \(streamer.currentLine))")

    // --- Resume completes ---------------------------------------------------
    await streamer.resume()
    _ = streamTask // stream loop finishes on its own after resume
    for _ in 0..<150 where streamer.currentLine < streamer.totalLines {
        try? await Task.sleep(nanoseconds: 40_000_000)
    }
    expect(streamer.currentLine >= streamer.totalLines - 1,
           "stream reached the end (\(streamer.currentLine)/\(streamer.totalLines))")
}

Task { @MainActor in
    await run()
    print("ShopPilotVerifyDOGFOOD1920h: PASS — currentLine advances live, Hold freezes stream+playhead together, resume completes.")
    exit(0)
}
RunLoop.main.run()
