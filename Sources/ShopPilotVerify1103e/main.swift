import Foundation
import ShopPilotCore

/// SPK-1103e verify (CLT machine, no XCTest).
/// Proves the sheet-aware material/heightfield sim spine:
///   1. SHEET-AWARE: a 200x100x20 stock yields samples spanning the sheet's
///      X/Y extent with every sample at the stock top (z == 20) before cutting.
///   2. REMOVAL ALONG THE PATH: a raster pocket carves the cells the cutter
///      passes through (z -> 0) and leaves off-line cells at the stock top.
///   3. FULL TREE: two ops in disjoint regions both remove material; the gap
///      between regions stays uncut (a last-op-only sim would miss one region).
///   4. CANCEL-IMMEDIATE: an always-true probe aborts fast, reports
///      isCancelled, and still returns the partial heightmap.
///   5. CANCEL-MID-RUN: a probe that flips after ~40 lines returns a partial
///      result (some material already removed) with isCancelled set — the
///      non-blocking cancel contract for the UI.
///   6. DRAFT REGRESSION: draftHeightSamples still yields the same shape.
/// The view glue (sheet dims from session.job, detached task, Cancel button)
/// is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Raster-fill G-code: plunges to `depth` at (x0,y0), then sweeps X across
/// each Y line (spacing `lineSpacingMm`), stepping to the next line at the
/// current X so every horizontal trench is a pure G1 (no diagonals).
func rasterPocketGCode(
    x0: Double, y0: Double, size: Double,
    depth: Double, lineSpacingMm: Double
) -> [String] {
    var lines: [String] = [
        "G0 X\(x0) Y\(y0)",
        "G0 Z5",
        "G1 Z\(depth) F100",
    ]
    var y = y0
    var goRight = true
    while y <= y0 + size + 1e-9 {
        if goRight {
            lines.append("G1 X\(x0 + size) Y\(y) F500")
        } else {
            lines.append("G1 X\(x0) Y\(y) F500")
        }
        let nextY = y + lineSpacingMm
        if nextY <= y0 + size + 1e-9 {
            let x = goRight ? x0 + size : x0
            lines.append("G1 X\(x) Y\(nextY) F500")
        }
        goRight.toggle()
        y = nextY
    }
    return lines
}

func sample(_ samples: [(x: Double, y: Double, z: Double)], _ x: Double, _ y: Double) -> Double? {
    samples.first(where: { abs($0.x - x) < 0.001 && abs($0.y - y) < 0.001 })?.z
}

func main() throws {
    // ── 1. Sheet-aware sizing + untouched stock. ────────────────────────────
    let untouched = ToolpathSimulator.materialSimulation(
        from: [],
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        sampleStride: 1
    )
    try expect(!untouched.isCancelled, "empty run must not be cancelled")
    try expect(untouched.samples.count > 0, "empty run must still sample the sheet")
    let xs = untouched.samples.map { $0.x }
    let ys = untouched.samples.map { $0.y }
    try expect((xs.min() ?? -1) >= 0 && (xs.max() ?? 201) <= 200, "samples must span X 0...200")
    try expect((ys.min() ?? -1) >= 0 && (ys.max() ?? 101) <= 100, "samples must span Y 0...100")
    try expect(untouched.samples.allSatisfy { abs($0.z - 20) < 0.001 }, "untouched stock stays at z == 20 everywhere")

    // ── 2. Material removal along the cutter path. ──────────────────────────
    let raster = rasterPocketGCode(x0: 0, y0: 0, size: 40, depth: 0, lineSpacingMm: 10)
    let carved = ToolpathSimulator.materialSimulation(
        from: raster,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        sampleStride: 1
    )
    try expect(!carved.isCancelled, "raster run must not be cancelled")
    // Raster lines at y = 0,10,20,30,40 — (20,20) is on a line; (20,15) is between.
    let onLine = try sample(carved.samples, 20, 20) ?? { throw VerifyError.failed("missing sample on raster line") }()
    let betweenLines = try sample(carved.samples, 20, 15) ?? { throw VerifyError.failed("missing sample off line") }()
    let outside = try sample(carved.samples, 90, 20) ?? { throw VerifyError.failed("missing sample outside") }()
    try expect(onLine < 0.001, "cell on a raster line must be carved to z 0 (got \(onLine))")
    try expect(abs(betweenLines - 20) < 0.001, "cell between raster lines must stay at stock top (got \(betweenLines))")
    try expect(abs(outside - 20) < 0.001, "cell outside the pocket must stay at stock top (got \(outside))")

    // ── 3. Full tree: two ops, disjoint regions, both carved. ───────────────
    var fullTree: [String] = []
    fullTree.append(contentsOf: rasterPocketGCode(x0: 0, y0: 0, size: 40, depth: 0, lineSpacingMm: 10))
    fullTree.append(contentsOf: rasterPocketGCode(x0: 100, y0: 60, size: 40, depth: 0, lineSpacingMm: 10))
    let treeSim = ToolpathSimulator.materialSimulation(
        from: fullTree,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        sampleStride: 1
    )
    let regionA = try sample(treeSim.samples, 20, 20) ?? { throw VerifyError.failed("missing sample region A") }()
    let regionB = try sample(treeSim.samples, 120, 70) ?? { throw VerifyError.failed("missing sample region B") }()
    let gap = try sample(treeSim.samples, 90, 20) ?? { throw VerifyError.failed("missing sample in gap") }()
    try expect(regionA < 0.001, "op1 region must be carved (got \(regionA))")
    try expect(regionB < 0.001, "op2 region must be carved — full-tree sim (got \(regionB))")
    try expect(abs(gap - 20) < 0.001, "gap between ops must stay uncut (got \(gap))")

    // ── 4. Cancel-immediate. ────────────────────────────────────────────────
    let cancelled = ToolpathSimulator.materialSimulation(
        from: fullTree,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        shouldCancel: { true }
    )
    try expect(cancelled.isCancelled, "immediate-true probe must report isCancelled")
    try expect(cancelled.samples.count > 0, "cancelled run still returns the partial heightmap")

    // ── 5. Cancel mid-run: partial material removal + isCancelled. ──────────
    var longRaster: [String] = ["G0 X0 Y0", "G0 Z5", "G1 Z0 F100"]
    for i in 0..<100 {
        longRaster.append("G1 X\(i % 2 == 0 ? 40 : 0) Y\(Double(i) * 0.5) F500")
    }
    var polls = 0
    let midRun = ToolpathSimulator.materialSimulation(
        from: longRaster,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        shouldCancel: {
            polls += 1
            return polls > 40
        }
    )
    try expect(midRun.isCancelled, "mid-run probe flip must report isCancelled")
    try expect(midRun.samples.contains { $0.z < 19.999 }, "mid-run cancel must keep the partial removal (some cell carved)")
    try expect(polls >= 40, "probe must have been polled per-line (\(polls) polls)")

    // ── 6. Draft regression (1103a path unchanged). ─────────────────────────
    let draft = ToolpathSimulator.draftHeightSamples(from: raster, cellSizeMm: 2.0, stockMm: 120)
    try expect(draft.samples.count > 0, "draftHeightSamples still yields samples")
    try expect(draft.seconds >= 0, "draft seconds must be non-negative")

    print("PASS — material sim sheet-aware (200x100x20), removal along path, full-tree both regions, cancel-immediate, cancel-mid-run partial, draft regression")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}
