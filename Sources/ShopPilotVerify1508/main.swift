import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1508 verify (CLT executable, no XCTest).
// Proves the status poller goes quiet while the streamer is mid-stream:
//   1. POLLS WHILE IDLE: with the gate false (streamer .idle), `?` bytes
//      appear on the wire.
//   2. QUIET WHILE STREAMING: with the gate true (streamer .streaming), a
//      poll window produces NO `?` writes.
//   3. RESUMES AFTER: back to .idle, `?` flows again (stream complete/cancel
//      → poll resumes).
//   4. SESSION WIRING: MachineSession's poller gate reads its attached
//      streamer's state (source-level check on MachineSession.swift).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1/2/3. Gate-controlled polling on a recording transport. ─────────
    let sim = SimulatorTransport()
    let streamer = GCodeStreamer()
    // Reference box (like MachineSession.StreamerStateBox): the poller task
    // and the test task share the flag through an explicit reference, so the
    // gate closure always reads the current value.
    final class StreamingFlag {
        var value = false
        init() {}
    }
    let streaming = StreamingFlag()
    let poller = StatusPoller(
        intervalNanoseconds: 20_000_000,   // 20ms — fast enough for the test
        isStreaming: { streaming.value }
    )

    let pollTask = Task { await poller.run(transport: sim) }
    defer { pollTask.cancel() }

    func pollBytes() async -> Data {
        await sim.writtenBytesSnapshot
    }

    try awaitBlocking {
        // Open the sim transport first — handleCommand throws `disconnected`
        // on an unopened port (same contract 1401f relies on), so the poller
        // would write once then exit.
        try await sim.open(config: SerialConfig(isSimulator: true, simulationDelayNanoseconds: 0))

        // 1. Idle → polls.
        let before = await pollBytes()
        try await Task.sleep(nanoseconds: 120_000_000)
        let idleDelta = (await pollBytes()).dropFirst(before.count)
        try expect(idleDelta.contains(StatusPoller.statusQueryByte),
                   "poller writes '?' while idle")

        // 2. Streaming → quiet (no new '?' in a full poll window).
        streaming.value = true
        let streamStart = await pollBytes()
        try await Task.sleep(nanoseconds: 120_000_000)
        let streamDelta = (await pollBytes()).dropFirst(streamStart.count)
        try expect(!streamDelta.contains(StatusPoller.statusQueryByte),
                   "poller writes NO '?' while streaming (got \(streamDelta.count) bytes)")

        // 3. Back to idle → resumes.
        streaming.value = false
        let resumeStart = await pollBytes()
        try await Task.sleep(nanoseconds: 120_000_000)
        let resumeDelta = (await pollBytes()).dropFirst(resumeStart.count)
        try expect(resumeDelta.contains(StatusPoller.statusQueryByte),
                   "poller resumes '?' after streaming ends (got \(resumeDelta.count) bytes)")
    }

    // ── 4. Session wiring: gate reads the attached streamer's state. ─────
    let sessionSource = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ShopPilotCore/MachineSession.swift"),
        encoding: .utf8
    )
    try expect(sessionSource.contains("box?.streamer?.state == .streaming"),
               "MachineSession wires poller gate to its attached streamer's state")
    try expect(sessionSource.contains("streamStateBox?.streamer = streamer"),
               "attachStreamer updates the poller's state box")

    print("1508: PASS — status poll pauses while streaming")
    print("  idle → '?' flows; streaming → quiet; resume → '?' flows again; session gate wired")
}

do {
    try main()
} catch {
    print("1508: FAIL — \(error)")
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
