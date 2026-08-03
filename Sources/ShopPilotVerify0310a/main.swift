import Foundation
import ShopPilotCore

/// SPK-0310a verify without XCTest (CLT-only):
/// the cancel API/path aborts an in-flight draft generation (wireframe pass +
/// heightfield sim) instead of letting it run to completion, and the manager
/// stays usable afterwards. No UI thread is involved — cancellation must be
/// prompt and non-blocking.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Pump the main run loop so `DispatchQueue.main` completions actually run in a
/// CLI process (plain Thread.sleep would starve them and hang the check).
func waitFor(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

/// Raster G-code: `rows` horizontal passes x `cols` points each, with plunges.
/// A raster is heavy for both the wireframe pass and the heightfield sim.
func makeRasterGcode(rows: Int, cols: Int, step: Double) -> [String] {
    var lines: [String] = ["G21", "G90", "G0 X0 Y0 Z5"]
    for r in 0..<rows {
        let y = Double(r) * step
        let xMax = Double(cols - 1) * step
        let left = r % 2 == 0
        lines.append("G0 X\(left ? "0" : String(format: "%.2f", xMax)) Y\(String(format: "%.2f", y))")
        lines.append("G1 Z-2 F800")
        if left {
            for c in 0..<cols { lines.append("G1 X\(String(format: "%.2f", Double(c) * step)) Y\(String(format: "%.2f", y))") }
        } else {
            for c in stride(from: cols - 1, through: 0, by: -1) { lines.append("G1 X\(String(format: "%.2f", Double(c) * step)) Y\(String(format: "%.2f", y))") }
        }
        lines.append("G1 Z2")
    }
    return lines
}

func draftConfig() -> PreviewConfiguration {
    PreviewConfiguration(
        qualityLevel: .draft,
        showWireframe: true,
        showHeightfield: true,
        showKeepOutZones: false,
        progressiveRefinement: true,
        timeoutSeconds: 30
    )
}

func main() throws {
    // --- 1. Simulator-level: shouldCancel aborts the loop mid-way (deterministic). ---
    let big = makeRasterGcode(rows: 200, cols: 200, step: 0.5) // ~40k lines
    let sim = ToolpathSimulator.createDefault(cellSizeMm: 2.0, stockWidthMm: 100, stockHeightMm: 100)

    var checks = 0
    let cancelAfterLines = 1000
    let aborted = sim.simulate(toolpathGcode: big, shouldCancel: {
        checks += 1
        return checks * 64 >= cancelAfterLines
    })
    try expect(aborted.isCancelled, "simulate with cancelling probe must report isCancelled")
    try expect(checks < big.count / 64, "sim loop must stop early (probe calls=\(checks), lines=\(big.count))")

    let full = sim.simulate(toolpathGcode: big)
    try expect(!full.isCancelled, "full sim must not be cancelled")
    try expect(full.success, "full sim success flag")

    // Chunked wireframe pass aborts mid-flight too.
    let wireAborted = WireframeRenderer.generateSegmentsCancellable(from: big, shouldCancel: { true })
    try expect(wireAborted.isCancelled, "wireframe pass must report cancellation")
    try expect(wireAborted.segments.isEmpty, "wireframe pass cancelled before first chunk must be empty")
    let wireFull = WireframeRenderer.generateSegmentsCancellable(from: big)
    try expect(!wireFull.isCancelled, "full wireframe pass must not be cancelled")
    try expect(wireFull.segments.count == WireframeRenderer.generateSegments(from: big).count,
               "chunked pass must equal single-pass output")

    // --- 2. Manager-level: cancel before the deferred work starts. ---
    let managerA = PreviewManager(simulator: sim, configuration: draftConfig())
    managerA.generatePreview(gcodeLines: big)
    managerA.cancelPreview() // lands before the 0.1s deferred start
    try expect(waitFor(timeout: 5.0) { managerA.currentState != .generating }, "manager must settle after cancel")
    try expect(managerA.currentState == .cancelled, "cancel-before-start must end .cancelled, got \(managerA.currentState)")
    try expect(managerA.currentResult == nil, "cancelled generation must not publish a result")

    // --- 3. Manager-level: cancel mid-flight while the draft sim is running. ---
    // Heavy enough that a full generation takes well over a second.
    let heavy = makeRasterGcode(rows: 400, cols: 400, step: 0.25) // ~160k lines
    let managerFull = PreviewManager(simulator: sim, configuration: draftConfig())
    let fullStart = Date()
    managerFull.generatePreview(gcodeLines: heavy)
    try expect(waitFor(timeout: 60.0) { managerFull.currentState == .ready },
               "full draft generation must complete")
    let fullElapsed = Date().timeIntervalSince(fullStart)
    try expect(fullElapsed > 0.2, "heavy input should take non-trivial time (got \(fullElapsed)s)")
    try expect(managerFull.currentResult?.isCancelled == false, "completed result must not be flagged cancelled")
    try expect((managerFull.currentResult?.pointCount ?? 0) > 0, "completed result must carry points")

    let managerC = PreviewManager(simulator: sim, configuration: draftConfig())
    let cancelStart = Date()
    managerC.generatePreview(gcodeLines: heavy)
    // Give the deferred work item time to start, then cancel while it is in flight.
    Thread.sleep(forTimeInterval: 0.15)
    managerC.cancelPreview()
    try expect(waitFor(timeout: 10.0) { managerC.currentState != .generating }, "manager must settle promptly after mid-flight cancel")
    let cancelElapsed = Date().timeIntervalSince(cancelStart)
    try expect(managerC.currentState == .cancelled, "mid-flight cancel must end .cancelled, got \(managerC.currentState)")
    try expect(managerC.currentResult == nil, "aborted generation must not publish a result")
    try expect(cancelElapsed < fullElapsed, "cancelled run (\(String(format: "%.2f", cancelElapsed))s) must beat full run (\(String(format: "%.2f", fullElapsed))s)")

    // --- 4. Manager stays usable after a cancel. ---
    managerC.generatePreview(gcodeLines: makeRasterGcode(rows: 40, cols: 40, step: 2.5))
    try expect(waitFor(timeout: 30.0) { managerC.currentState == .ready },
               "manager must generate again after cancel")
    try expect(managerC.currentState == .ready, "regeneration must end .ready")
    try expect(managerC.currentResult?.isCancelled == false, "regenerated result must not be cancelled")

    print(String(format: "ShopPilotVerify0310a PASS — full=%.2fs cancel=%.2fs, states: cancel-before-start/cancel-mid-flight/regenerate all correct",
                 fullElapsed, cancelElapsed))
}

do {
    try main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
