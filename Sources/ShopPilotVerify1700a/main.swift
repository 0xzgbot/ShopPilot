import Foundation
import ShopPilotCore

// SPK-1700a verify (CLT executable, no XCTest).
// Proves the preview's material sim is a FULL dense heightmap, not the old
// `/40` dot scatter:
//   1. DENSE DEFAULT: `materialSimulation` with no stride argument samples
//      EVERY cell (width × height) — on a 200×100 sheet at 1mm that is
//      20,000 samples, not the old max(1, 200/40)=5-stride 800.
//   2. HEIGHTMAP: `simulateHeightmap` returns a Heightmap of exactly
//      width × height cells spanning the sheet.
//   3. CONTIGUOUS TRENCHES: two horizontal G1 passes carve two full, solid
//      rows — the removed cells form contiguous runs (a trench), not
//      isolated dots; rows between the passes stay at stock top.
//   4. COARSE DRAFT still available: an explicit large stride yields the
//      coarse draft sample set (and never crashes).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Two horizontal full-width cuts at y=10 and y=60, plunge to z=0 first
/// (stock top = 20). Every removed cell sits on one of those two rows.
func trenchFixture() -> [String] {
    [
        "G0 X0 Y10",
        "G0 Z5",
        "G1 Z0 F100",
        "G1 X200 Y10 F500",
        "G0 X0 Y60",
        "G1 X200 Y60 F500",
    ]
}

func main() throws {
    let fixture = trenchFixture()
    // A point-sized radius isolates THIS card's density/contiguity contract
    // from the SPK-1700c disk stamp (which widens the trench to the tool
    // diameter) — 1700a is about the filled raster, not the bit width.
    let pointRadius = 0.01

    // ── 1. Dense default stride (no arg) = every cell. ─────────────────────
    let dense = ToolpathSimulator.materialSimulation(
        from: fixture,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        toolRadiusMm: pointRadius
    )
    try expect(!dense.isCancelled, "dense run must not be cancelled")
    try expect(dense.samples.count == 20_000,
               "default stride samples EVERY cell — got \(dense.samples.count), want 200×100 = 20000")
    try expect(dense.samples.count >= 19_000,
               "sample count ≈ width×height (not the old ~40×40 scatter)")

    // ── 2. simulateHeightmap returns the full dense grid. ──────────────────
    let outcome = ToolpathSimulator.simulateHeightmap(
        from: fixture,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        toolRadiusMm: pointRadius
    )
    let hm = outcome.heightmap
    try expect(hm.width == 200 && hm.height == 100,
               "heightmap grid is width×height (got \(hm.width)×\(hm.height))")
    try expect(!outcome.isCancelled, "heightmap run must not be cancelled")

    // ── 3. Contiguous trenches, not isolated dots. ─────────────────────────
    // Every cell on the cut rows is removed…
    for x in 0..<200 {
        try expect(hm.getHeight(x, 10) < 0.001, "row 10 fully removed at x=\(x)")
        try expect(hm.getHeight(x, 60) < 0.001, "row 60 fully removed at x=\(x)")
    }
    // …and the rows BETWEEN the passes stay at stock top (a solid trench is
    // 1 cell wide here — no bit stamp yet, that's 1700c).
    for x in 0..<200 {
        try expect(abs(hm.getHeight(x, 35) - 20) < 0.001, "row 35 stays at stock top (x=\(x))")
    }
    // Removed cells are exactly the two full rows — one contiguous run each,
    // no scattered dots elsewhere in the grid.
    var removedCount = 0
    var removedInRow10 = 0
    var removedInRow60 = 0
    var minRow10X = Int.max, maxRow10X = -1
    var minRow60X = Int.max, maxRow60X = -1
    for y in 0..<100 {
        for x in 0..<200 {
            if hm.getHeight(x, y) < 0.001 {
                removedCount += 1
                if y == 10 { removedInRow10 += 1; minRow10X = min(minRow10X, x); maxRow10X = max(maxRow10X, x) }
                else if y == 60 { removedInRow60 += 1; minRow60X = min(minRow60X, x); maxRow60X = max(maxRow60X, x) }
            }
        }
    }
    try expect(removedCount == 400, "exactly the two trench rows removed (got \(removedCount))")
    try expect(removedInRow10 == 200 && minRow10X == 0 && maxRow10X == 199,
               "row 10 trench is one contiguous run 0…199 (got \(removedInRow10) cells, \(minRow10X)…\(maxRow10X))")
    try expect(removedInRow60 == 200 && minRow60X == 0 && maxRow60X == 199,
               "row 60 trench is one contiguous run 0…199 (got \(removedInRow60) cells, \(minRow60X)…\(maxRow60X))")

    // ── 4. Coarse draft stride still works when explicitly requested. ──────
    let draft = ToolpathSimulator.materialSimulation(
        from: fixture,
        sheetWidthMm: 200, sheetDepthMm: 100, stockTopMm: 20,
        cellSizeMm: 1.0,
        sampleStride: 40
    )
    try expect(draft.samples.count == 15,
               "explicit coarse stride 40 → 5×3 draft samples (got \(draft.samples.count))")

    print("PASS — dense heightfield raster: 20000 default-stride samples, 200×100 heightmap, contiguous trench rows 10+60 (400 cells, no scattered dots), stock rows intact, coarse draft 15")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}
