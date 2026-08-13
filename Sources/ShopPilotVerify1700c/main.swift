import Foundation
import ShopPilotCore

// SPK-1700c verify (CLT executable, no XCTest).
// Proves the circular bit-radius stamp: each interpolated cut point clears a
// DISK of the tool radius (flat endmill v0), not a 1-cell needle:
//   1. A G1 along X at z below stock with radius R=3 clears a band ≈ 2R wide
//      in Y (rows 7…13 around y=10 — NOT a 1-cell line).
//   2. Raster stepover ridges match the tool: two passes spaced 8mm apart
//      (diameter 6mm) leave a stock ridge between them; two passes spaced
//      6mm (== diameter) clear a continuous pocket with NO ridge.
//   3. Documented fallback: nil radius stamps the documented 1.5mm default
//      (a ~3mm-wide band, not a needle).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func removedRows(inColumn x: Int, _ hm: Heightmap, stockTop: Double) -> [Int] {
    (0..<hm.height).filter { hm.getHeight(x, $0) < stockTop - 0.001 }
}

func main() throws {
    let stockTop = 10.0

    // ── 1. Single pass, radius 3 → band ≈ 2R wide, not a 1-cell line. ─────
    let single = ToolpathSimulator.simulateHeightmap(
        from: ["G0 X2 Y10", "G0 Z5", "G1 Z0 F100", "G1 X18 Y10 F500"],
        sheetWidthMm: 20, sheetDepthMm: 20, stockTopMm: stockTop,
        cellSizeMm: 1.0,
        toolRadiusMm: 3.0
    ).heightmap
    try expect(single.getHeight(10, 10) < 0.001, "cell on the pass line is removed")
    try expect(single.getHeight(10, 7) < 0.001, "cell 3mm below the line is removed (|7−10| == R)")
    try expect(single.getHeight(10, 13) < 0.001, "cell 3mm above the line is removed (|13−10| == R)")
    try expect(abs(single.getHeight(10, 5) - stockTop) < 0.001, "cell 5mm off the line stays at stock")
    let band = removedRows(inColumn: 10, single, stockTop: stockTop)
    try expect(band.count >= 5 && band.count <= 9,
               "band is ≈ 2R = 6mm wide, not a 1-cell line (got \(band.count) rows: \(band))")

    // ── 2a. Stepover 8mm > diameter 6mm → a stock ridge stays between. ────
    let ridgeSim = ToolpathSimulator.simulateHeightmap(
        from: ["G0 X2 Y5", "G0 Z5", "G1 Z0 F100", "G1 X18 Y5 F500",
               "G0 X2 Y13", "G1 X18 Y13 F500"],
        sheetWidthMm: 20, sheetDepthMm: 20, stockTopMm: stockTop,
        cellSizeMm: 1.0,
        toolRadiusMm: 3.0
    ).heightmap
    let ridgeBand = removedRows(inColumn: 10, ridgeSim, stockTop: stockTop)
    try expect(ridgeBand.contains(5) && ridgeBand.contains(13),
               "both passes carved their bands (got rows \(ridgeBand))")
    try expect(abs(ridgeSim.getHeight(10, 9) - stockTop) < 0.001,
               "the 8mm-stepover ridge stays at stock (row 9 is 4mm from both passes)")

    // ── 2b. Stepover 6mm == diameter → no ridge; a continuous pocket. ──────
    let pocketSim = ToolpathSimulator.simulateHeightmap(
        from: ["G0 X2 Y4", "G0 Z5", "G1 Z0 F100", "G1 X18 Y4 F500",
               "G0 X2 Y10", "G1 X18 Y10 F500"],
        sheetWidthMm: 20, sheetDepthMm: 20, stockTopMm: stockTop,
        cellSizeMm: 1.0,
        toolRadiusMm: 3.0
    ).heightmap
    var ridgeFound = false
    for y in 5...9 where abs(pocketSim.getHeight(10, y) - stockTop) < 0.001 {
        ridgeFound = true   // any stock cell between the passes = a ridge
    }
    try expect(!ridgeFound, "6mm stepover == diameter clears a continuous pocket (no ridge)")

    // ── 3. Documented fallback (nil radius) = 1.5mm → ~3mm band. ───────────
    let fallback = ToolpathSimulator.simulateHeightmap(
        from: ["G0 X2 Y10", "G0 Z5", "G1 Z0 F100", "G1 X18 Y10 F500"],
        sheetWidthMm: 20, sheetDepthMm: 20, stockTopMm: stockTop,
        cellSizeMm: 1.0
    ).heightmap
    let fallbackBand = removedRows(inColumn: 10, fallback, stockTop: stockTop)
    try expect(fallbackBand.count >= 2 && fallbackBand.count <= 4,
               "nil radius falls back to the documented 1.5mm (band ≈ 3 rows, got \(fallbackBand))")

    print("PASS — bit stamp: R=3 clears a ~6mm band (not 1 cell), 8mm stepover leaves a ridge, 6mm stepover is a continuous pocket, nil falls back to 1.5mm")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}
