import Foundation
import ShopPilotCore

/// SPK-1305 verify (CLT machine, no XCTest).
/// Proves the REST MACHINING PLANNER contract:
///   1. CLEAN GRID → NO PASSES: all-zero remaining depth yields no passes.
///   2. LAYERED CLEARING: a cell with material `m` appears in exactly
///      ceil(m / stepDown) passes, shallow→deep.
///   3. TOLERANCE: cells at or below minRemaining are treated as clean.
///   4. DEPTH ORDER: pass depths are -step, -2·step, … (shallow first).
///   5. SHAPE VALIDATION: ragged grid (count not a multiple of width) and
///      empty grids return [] without crashing.
///   6. SUMMARIES: passCount + totalRemaining match hand-computed values.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) < tol }

func main() throws {
    // ── 1. Clean grid → no passes. ────────────────────────────────────────
    let clean = planRestPasses(grid: [0, 0, 0, 0], width: 2)
    try expect(clean.isEmpty, "all-clean grid yields no rest passes")

    // ── 2. Layered clearing. ──────────────────────────────────────────────
    // One cell with 5mm material, stepDown 2 → ceil(5/2) = 3 passes.
    let single = planRestPasses(grid: [5], width: 1, stepDown: 2, minRemaining: 0)
    try expect(single.count == 3, "5mm at 2mm step → 3 passes (got \(single.count))")
    try expect(single[0].cellIndices == [0], "pass 1 clears the cell")
    try expect(single[1].cellIndices == [0], "pass 2 still clears it")
    try expect(single[2].cellIndices == [0], "pass 3 still clears it")

    // ── 3. Tolerance. ─────────────────────────────────────────────────────
    // 0.2mm remaining with minRemaining 0.3 → clean (finish pass handles it).
    let thin = planRestPasses(grid: [0.2], width: 1, minRemaining: 0.3)
    try expect(thin.isEmpty, "0.2mm material under 0.3mm tolerance → no passes")
    // 0.5mm with the same tolerance → 0.2mm above tolerance, 1 pass at 2mm.
    let thin2 = planRestPasses(grid: [0.5], width: 1, minRemaining: 0.3)
    try expect(thin2.count == 1, "0.5mm − 0.3 tolerance → 1 pass (got \(thin2.count))")

    // ── 4. Depth order + per-pass membership. ─────────────────────────────
    // 4x1 grid: cells at 0, 2, 4, 6 mm. stepDown 2 → depths -2, -4, -6.
    let varied = planRestPasses(grid: [0, 2, 4, 6], width: 4, stepDown: 2, minRemaining: 0)
    try expect(varied.count == 3, "6mm max → 3 passes (got \(varied.count))")
    try expect(close(varied[0].depth, -2) && close(varied[1].depth, -4)
               && close(varied[2].depth, -6), "depths shallow→deep (-2, -4, -6)")
    try expect(varied[0].cellIndices == [1, 2, 3], "pass 1 clears cells with ≥2mm")
    try expect(varied[1].cellIndices == [2, 3], "pass 2 clears cells with ≥4mm")
    try expect(varied[2].cellIndices == [3], "pass 3 clears only the 6mm cell")

    // ── 5. Shape validation. ──────────────────────────────────────────────
    let ragged = planRestPasses(grid: [1, 2, 3], width: 2, minRemaining: 0)
    try expect(ragged.isEmpty, "ragged grid (3 cells, width 2) → []")
    let empty = planRestPasses(grid: [], width: 1)
    try expect(empty.isEmpty, "empty grid → []")

    // ── 6. Summaries. ─────────────────────────────────────────────────────
    try expect(RestRoughing.passCount(material: 5, stepDown: 2) == 3, "passCount 5mm/2mm = 3")
    try expect(RestRoughing.passCount(material: 4, stepDown: 2) == 2, "passCount 4mm/2mm = 2")
    try expect(RestRoughing.passCount(material: 0, stepDown: 2) == 0, "passCount 0mm = 0")
    try expect(close(RestRoughing.totalRemaining([0, 1, 2, 3], minRemaining: 0.5), 4.5),
               "totalRemaining = (1−.5)+(2−.5)+(3−.5) = 4.5")

    print("ShopPilotVerify1305: PASS — clean-grid → none, layered clearing (ceil math), tolerance, depth order + per-pass membership, ragged/empty guards, passCount + totalRemaining")
}

/// Local alias so the verify reads naturally.
private func planRestPasses(grid: [Double], width: Int, stepDown: Double = 2.0,
                            minRemaining: Double = 0.3) -> [RestPass] {
    RestRoughing.planRestPasses(remainingDepthGrid: grid, gridWidth: width,
                                stepDown: stepDown, minRemaining: minRemaining)
}

do {
    try main()
} catch {
    print("ShopPilotVerify1305: FAIL — \(error)")
    exit(1)
}
