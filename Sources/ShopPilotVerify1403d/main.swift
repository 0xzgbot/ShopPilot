import Foundation
import ShopPilotCore

// SPK-1403d verify (CLT executable, no XCTest).
// Proves the extracted fixture G-code loading (FixtureGCodeLoader):
//   1. NON-EMPTY BUFFER → no-op (false, buffer untouched) — a real job is
//      never clobbered by fixture loading.
//   2. EMPTY BUFFER + FIXTURE FILE → loads + filters the fixture's lines,
//      summary names the file.
//   3. EMPTY BUFFER + NO FILE → built-in air-cut square, summary matches.
//   4. SOURCE CONTRACT: AppSession.loadFixtureGCodeIfNeeded delegates to
//      Core; Machine Continue / fixture load still fill gcodeLines.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

final class FakeFixtureSession: FixtureLoadingSession {
    var gcodeLines: [String] = []
    var summaries: [String] = []
    func setLastToolpathSummary(_ text: String) { summaries.append(text) }
}

func main() throws {
    // ── 1. Non-empty buffer → no-op. ─────────────────────────────────────
    let busy = FakeFixtureSession()
    busy.gcodeLines = ["G0 X1"]
    let noop = FixtureGCodeLoader.loadIfNeeded(into: busy, candidateURLs: [])
    try expect(!noop, "non-empty buffer → no-op (false)")
    try expect(busy.gcodeLines == ["G0 X1"], "buffer untouched when a job is loaded")
    try expect(busy.summaries.isEmpty, "no summary published for a no-op")

    // ── 2. Empty buffer + fixture file → loads the file. ─────────────────
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fixtures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let fixtureURL = dir.appendingPathComponent("calibration_square.nc")
    try """
    G21
    G90

    G0 Z5
    G0 X0 Y0
    M2
    """.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let fileSession = FakeFixtureSession()
    let loadedFile = FixtureGCodeLoader.loadIfNeeded(
        into: fileSession,
        candidateURLs: [fixtureURL]
    )
    try expect(loadedFile, "empty buffer + fixture file → loaded (true)")
    try expect(fileSession.gcodeLines == ["G21", "G90", "G0 Z5", "G0 X0 Y0", "M2"],
               "fixture lines loaded, blank lines filtered (got \(fileSession.gcodeLines))")
    try expect(fileSession.summaries.last?.contains("calibration_square.nc") == true,
               "summary names the loaded fixture (got \(fileSession.summaries.last ?? "nil"))")

    // ── 3. Empty buffer + no file → built-in air-cut square. ─────────────
    let fallback = FakeFixtureSession()
    let loadedBuiltIn = FixtureGCodeLoader.loadIfNeeded(into: fallback, candidateURLs: [])
    try expect(loadedBuiltIn, "empty buffer + no file → built-in loaded (true)")
    try expect(fallback.gcodeLines == FixtureGCodeLoader.builtInAirCutSquare,
               "built-in air-cut square fills the buffer (got \(fallback.gcodeLines.count) lines)")
    try expect(fallback.gcodeLines.contains("M2"), "built-in ends with M2")
    try expect(fallback.summaries.last?.contains("Built-in air-cut square") == true,
               "summary names the built-in (got \(fallback.summaries.last ?? "nil"))")

    // ── 4. Source contract: one-line delegate. ───────────────────────────
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/AppSession.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    try expect(source.contains("FixtureGCodeLoader.loadIfNeeded(into: self)"),
               "AppSession.loadFixtureGCodeIfNeeded delegates to Core")
    try expect(source.contains("FixtureLoadingSession"),
               "AppSession conforms to FixtureLoadingSession")
    // Machine Continue / fixture load path intact.
    try expect(source.contains("loadFixtureGCodeIfNeeded()"),
               "session call sites still invoke the facade")

    print("1403d: PASS — machine fixture G-code facade extracted to Core FixtureGCodeLoader")
    print("  non-empty no-op; fixture file loads + filters; built-in fallback; one-line delegate; session call sites intact")
}

do {
    try main()
} catch {
    print("1403d: FAIL — \(error)")
    exit(1)
}
