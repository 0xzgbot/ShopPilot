import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-0417a verify (CLT machines, no XCTest).
///
/// AC: Simulator path connect → stream fixture → hold → resume → complete.
/// Out of scope: live router (serial transport is never touched here).
///
/// Exercises the real `SimulatorTransport` + `GCodeStreamer` stack:
///   Leg 1 — connect → stream `square_air_10mm.nc` → complete (progress 0 → 1.0)
///   Leg 2 — connect → stream `rapid_only.nc` → hold mid-stream → assert paused
///           and progress frozen → resume → complete (progress 0 → 1.0)

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Walk up from the executable's working directory until Package.swift is found.
func projectRoot() -> URL {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
        url.deleteLastPathComponent()
        if url.path == "/" { break }
    }
    return url
}

func connect(_ transport: SimulatorTransport) async throws {
    let config = SerialConfig(isSimulator: true)
    try await transport.open(config: config)
}

// MARK: - Leg 1: connect → stream fixture → complete

func runLeg1() async throws {
    print("=== Leg 1: connect → stream square_air_10mm.nc → complete ===")
    let root = projectRoot()
    let fixtureURL = root.appendingPathComponent("fixtures/gcode/square_air_10mm.nc")
    try expect(FileManager.default.fileExists(atPath: fixtureURL.path),
               "fixture exists: \(fixtureURL.path)")

    let transport = SimulatorTransport()
    let streamer = GCodeStreamer()
    defer { Task { await transport.close() } }

    // Connect
    try await connect(transport)

    // Initial state
    try expect(streamer.state == .idle, "initial state is idle")
    try expect(streamer.progress == 0.0, "initial progress is 0.0")

    // Load + stream
    let lines = try await streamer.load(from: fixtureURL)
    try expect(!lines.isEmpty, "fixture has executable lines (\(lines.count))")
    try await streamer.stream(lines: lines, to: transport)

    // Complete
    try expect(streamer.state == .idle, "state is idle after stream (got \(streamer.state))")
    try expect(streamer.progress == 1.0, "progress is 1.0 at completion (got \(streamer.progress))")
    try expect(streamer.currentLine == streamer.totalLines, "all lines sent (\(streamer.currentLine)/\(streamer.totalLines))")
    try expect(streamer.totalLines > 0, "totalLines > 0")
    print("  PASS: \(streamer.currentLine)/\(streamer.totalLines) lines, progress 0 → \(streamer.progress)")
    print()
}

// MARK: - Leg 2: connect → stream fixture → hold → resume → complete

func runLeg2() async throws {
    print("=== Leg 2: connect → stream rapid_only.nc → hold → resume → complete ===")
    let root = projectRoot()
    let fixtureURL = root.appendingPathComponent("fixtures/gcode/rapid_only.nc")
    try expect(FileManager.default.fileExists(atPath: fixtureURL.path),
               "fixture exists: \(fixtureURL.path)")

    let transport = SimulatorTransport()
    let streamer = GCodeStreamer()
    defer { Task { await transport.close() } }

    // Connect
    try await connect(transport)
    try expect(streamer.state == .idle, "initial state is idle")

    // Load
    let lines = try await streamer.load(from: fixtureURL)
    try expect(!lines.isEmpty, "fixture has executable lines (\(lines.count))")
    let total = lines.count

    // Stream in a background task so hold/resume can be injected mid-stream.
    let streamTask = Task {
        try await streamer.stream(lines: lines, to: transport)
    }

    // Let the first few lines flow (50ms sim delay per write).
    try await Task.sleep(nanoseconds: 150_000_000)
    try expect(streamer.state == .streaming, "stream is streaming before hold (got \(streamer.state))")

    // Hold — GRBL feed hold (bang). Simulator ack is also ok, which the
    // ok-wait loop consumes; the important invariant is the state + freeze.
    await streamer.pause()
    try expect(streamer.state == .paused, "state is paused after hold (got \(streamer.state))")

    // GRBL lets the in-flight line finish before the hold engages, so let any
    // in-flight ok settle, then assert the stream is truly frozen.
    try await Task.sleep(nanoseconds: 200_000_000)
    let lineAtHold = streamer.currentLine
    try expect(streamer.progress < 1.0, "progress < 1.0 during hold (got \(streamer.progress))")

    // Give the loop a few sleep cycles: progress/currentLine must NOT advance.
    try await Task.sleep(nanoseconds: 400_000_000)
    try expect(streamer.currentLine == lineAtHold,
               "currentLine frozen during hold (\(lineAtHold) → \(streamer.currentLine))")
    print("  HOLD OK: paused at line \(lineAtHold)/\(total), progress \(streamer.progress)")

    // Resume — GRBL resume (tilde).
    await streamer.resume()
    try expect(streamer.state == .streaming, "state is streaming after resume (got \(streamer.state))")

    // Let it finish.
    try await streamTask.value

    // Complete
    try expect(streamer.state == .idle, "state is idle after resume→complete (got \(streamer.state))")
    try expect(streamer.progress == 1.0, "progress is 1.0 after resume→complete (got \(streamer.progress))")
    try expect(streamer.currentLine == streamer.totalLines, "all lines sent after resume (\(streamer.currentLine)/\(streamer.totalLines))")
    print("  RESUME OK: completed \(streamer.currentLine)/\(streamer.totalLines) lines, progress 0 → \(streamer.progress)")
    print()
}

// MARK: - Main

@main
struct ShopPilotVerify0417aMain {
    static func main() async {
        do {
            try await runLeg1()
            try await runLeg2()
            print("SPK-0417a verification: PASS")
            print("  simulator path connect → stream fixture → hold → resume → complete OK")
            exit(0)
        } catch {
            fputs("SPK-0417a verification: FAIL — \(error)\n", stderr)
            exit(1)
        }
    }
}
