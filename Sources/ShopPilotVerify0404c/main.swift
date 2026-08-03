import Foundation
import ShopPilotCore

/// SPK-0404c verify (CLT machines, no XCTest).
/// AC: an ok-wait stream of a small fixture publishes progress from 0 to 1.
///
/// Exercises the real GCodeStreamer + SimulatorTransport against the
/// fixtures/gcode/*.nc files: streams every executable line with ok-wait
/// while a sampler task snapshots the @Published progress property, then
/// asserts the observed progress sequence starts at 0.0 and ends at 1.0,
/// with the streamer reporting completion (idle, currentLine == totalLines).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Resolve the repo root (directory containing Package.swift) from the CWD,
/// so the verify binary works when launched from the worktree root or
/// anywhere below it.
func repoRoot() -> URL {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
        url.deleteLastPathComponent()
        guard url.path != "/" else { break }
    }
    return url
}

func fixtureURL(_ name: String) throws -> URL {
    let url = repoRoot()
        .appendingPathComponent("fixtures/gcode")
        .appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw VerifyError.failed("Fixture not found: \(url.path)")
    }
    return url
}

func main() async throws {
    let fixtures = ["square_air_10mm.nc", "rapid_only.nc"]

    for name in fixtures {
        let url = try fixtureURL(name)
        print("=== \(name) ===")

        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)

        // Initial state: progress 0, idle.
        try expect(streamer.progress == 0.0, "initial progress is 0.0")
        try expect(streamer.state == .idle, "initial state is idle")

        // Sampler task: snapshot distinct @Published progress values while
        // the stream runs (poll at 20ms — the sim answers each line in 50ms,
        // so intermediate steps are observable for a short fixture).
        let sampler = Task { () -> [Double] in
            var samples: [Double] = [streamer.progress]
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000)
                let p = streamer.progress
                if p != samples.last {
                    samples.append(p)
                }
                if streamer.state == .idle
                    && streamer.currentLine >= streamer.totalLines
                    && streamer.totalLines > 0 {
                    break
                }
            }
            return samples
        }

        // Load + stream with ok-wait.
        let lines = try await streamer.load(from: url)
        try expect(lines.count > 0, "fixture has executable lines (\(lines.count))")
        print("  loaded \(lines.count) executable lines")

        try await streamer.stream(lines: lines, to: transport)
        sampler.cancel()
        let observed = await sampler.value
        let distinct = Array(Set(observed)).sorted()
        print("  published progress samples: \(distinct)")

        // Completion state.
        try expect(streamer.state == .idle, "state is idle after stream")
        try expect(streamer.progress == 1.0, "progress is 1.0 at completion")
        try expect(streamer.currentLine == streamer.totalLines,
                   "all lines sent (\(streamer.currentLine)/\(streamer.totalLines))")
        try expect(streamer.totalLines > 0, "total lines > 0")

        // Observed progress: starts at 0, ends at 1, and a short fixture
        // shows intermediate published values (throttle is 0.1s, sim is 50ms).
        try expect(distinct.first == 0.0, "progress starts at 0.0")
        try expect(distinct.last == 1.0, "progress reaches 1.0")
        try expect(distinct.count >= 2, "progress was published at least 0 and 1")
        if lines.count > 2 {
            try expect(distinct.count >= 3,
                       "short fixture shows intermediate progress (\(distinct))")
        }

        print("  PASS — \(streamer.currentLine)/\(streamer.totalLines) lines, progress \(distinct.first ?? -1) → \(distinct.last ?? -1)")
        print()

        await transport.close()
    }

    print("SPK-0404c verification: PASS — ok-wait stream of small fixture publishes progress 0 → 1")
}

do {
    try await main()
} catch {
    fputs("SPK-0404c verification: FAIL — \(error)\n", stderr)
    exit(1)
}
