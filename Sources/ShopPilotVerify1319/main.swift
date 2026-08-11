import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1319 verify (CLT, no XCTest).
/// Proves the 3D-text relief engine:
///   1. SQUARE glyph raster: point-in-polygon — center cell inside, corner
///      cells outside, true-cell count ≈ area (±20%).
///   2. CONCAVE L-shape: even-odd fill puts the notch cell outside.
///   3. SELF-INTERSECTING bow-tie: valid result, grid dims match bounds,
///      no crash.
///   4. buildHeightfield: two flat 25-cell (5×5) rasters composite into one
///      grid with the raised-letter convention (inside = stock, outside =
///      stock − carve); mismatched raster sizes → empty heights, no crash.
///   5. lettersAndSpacing: letters vs. total glyphs; spaces don't raster.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Square glyph raster. ───────────────────────────────────────────
    // 8×8mm square inset in a 10×10mm bounds at 1mm resolution → 10×10 grid.
    let square: [VectorPoint] = [
        VectorPoint(x: 1, y: 1),
        VectorPoint(x: 9, y: 1),
        VectorPoint(x: 9, y: 9),
        VectorPoint(x: 1, y: 9),
    ]
    let raster = ReliefText3D.rasterizeGlyph(
        outlinePoints: square,
        resolutionMm: 1.0,
        bounds: (minX: 0, minY: 0, maxX: 10, maxY: 10)
    )
    try expect(raster.count == 10 && raster.allSatisfy({ $0.count == 10 }),
               "square raster is 10×10 (got \(raster.count) rows)")
    try expect(raster[5][5] == true, "center cell inside = true")
    try expect(raster[0][0] == false && raster[9][9] == false,
               "corner cells outside = false")
    let trueCount = raster.reduce(0) { $0 + $1.filter { $0 }.count }
    let squareArea = 8.0 * 8.0
    try expect(abs(Double(trueCount) - squareArea) <= squareArea * 0.20,
               "true-cell count \(trueCount) ≈ area \(squareArea) (±20%)")

    // ── 2. Concave L-shape (6 points): even-odd handles concavity. ────────
    let lShape: [VectorPoint] = [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 6, y: 0),
        VectorPoint(x: 6, y: 2),
        VectorPoint(x: 2, y: 2),
        VectorPoint(x: 2, y: 6),
        VectorPoint(x: 0, y: 6),
    ]
    let lRaster = ReliefText3D.rasterizeGlyph(
        outlinePoints: lShape,
        resolutionMm: 1.0,
        bounds: (minX: 0, minY: 0, maxX: 6, maxY: 6)
    )
    try expect(lRaster.count == 6, "L-shape raster is 6×6")
    try expect(lRaster[1][1] == true, "L body cell inside = true")
    try expect(lRaster[4][4] == false, "L notch cell outside = false (even-odd)")

    // ── 3. Self-intersecting bow-tie: never crashes, dims match bounds. ───
    let bowTie: [VectorPoint] = [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 6, y: 6),
        VectorPoint(x: 0, y: 6),
        VectorPoint(x: 6, y: 0),
    ]
    let bowRaster = ReliefText3D.rasterizeGlyph(
        outlinePoints: bowTie,
        resolutionMm: 1.0,
        bounds: (minX: 0, minY: 0, maxX: 6, maxY: 6)
    )
    try expect(bowRaster.count == 6 && bowRaster.allSatisfy({ $0.count == 6 }),
               "bow-tie raster dims match 6×6 bounds (no crash)")

    // ── 4. buildHeightfield composite + convention + mismatch guard. ──────
    // Two glyph rasters, each a flat row-major 25-cell grid (5×5):
    //   a5 = center dot at (row 2, col 2) → flat index 2*5+2 = 12
    //   b5 = corner dot at (row 0, col 0) → flat index 0
    let a5 = (0..<25).map { $0 == 12 }          // center cell raised
    let b5 = (0..<25).map { $0 == 0 }           // corner cell raised
    let hf = ReliefText3D.buildHeightfield(
        glyphRasters: [a5, b5],
        cellSizeMm: 1.0,
        stockThicknessMm: 10.0,
        carveDepthMm: 3.0,
        originX: 0, originY: 0
    )
    try expect(hf.width == 5 && hf.height == 5,
               "heightfield is 5×5 from 25-cell rasters (got \(hf.width)×\(hf.height))")
    try expect(hf.heights.count == 25, "heights row-major, 25 entries (got \(hf.heights.count))")
    try expect(hf.cellSizeMm == 1.0 && hf.minX == 0 && hf.minY == 0,
               "grid origin / cell size propagated")
    try expect(hf.heights[12] == 10.0, "inside glyph = stock 10mm (raised)")
    try expect(hf.heights[0] == 10.0, "second glyph cell also raised")
    try expect(hf.heights[6] == 7.0, "background = stock − carve = 7mm")
    try expect(hf.heights[24] == 7.0, "background corner cell = 7mm")

    // Mismatched raster sizes → empty heights, never a crash.
    let small = [Bool](repeating: true, count: 4) // 2×2 = 4 cells
    let empty = ReliefText3D.buildHeightfield(
        glyphRasters: [a5, small],
        cellSizeMm: 1.0,
        stockThicknessMm: 10.0,
        carveDepthMm: 3.0,
        originX: 0, originY: 0
    )
    try expect(empty.heights.isEmpty, "mismatched rasters → empty heights (no crash)")

    // ── 5. lettersAndSpacing. ─────────────────────────────────────────────
    let hi = ReliefText3D.lettersAndSpacing("Hi there")
    try expect(hi.letterCount == 7 && hi.totalGlyphs == 7,
               "Hi there → 7 letters / 7 glyphs (space doesn't raster) (got \(hi.letterCount)/\(hi.totalGlyphs))")
    let blank = ReliefText3D.lettersAndSpacing("")
    try expect(blank.letterCount == 0 && blank.totalGlyphs == 0, "empty string → 0/0")

    print("ShopPilotVerify1319: PASS — glyph raster (square, concave L, self-intersecting bow-tie), heightfield composite + raised-letter convention, mismatch guard, lettersAndSpacing")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1319: FAIL — \(error)")
    exit(1)
}
