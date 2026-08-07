import Foundation
import ShopPilotCore

/// SPK-0714 verify (CLT machines, no XCTest).
/// Proves the two-rail sweep relief engine (`SweepReliefEngine`):
///   1. Two parallel straight rails → a strip grid whose cells inside the
///      swept region carry the profile height (rectangle = flat top).
///   2. Circle profile → centerline cells peak at `height`, rail-edge cells
///      fall toward 0.
///   3. Resampling: rails of unequal point counts produce aligned samples.
///   4. Degenerate rails (single point / empty) → nil, no crash.
///   5. Grid geometry: cells are cellSizeMm, minX/minY = strip bbox min.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // ── 1. Parallel rails → flat-top strip ────────────────────────────────
    // Rail 1: y=0 from x=0..20; rail 2: y=10 from x=0..20. The strip is a
    // 20×10 rectangle.
    let rail1 = (0...10).map { pt(Double($0) * 2.0, 0) }
    let rail2 = (0...10).map { pt(Double($0) * 2.0, 10) }
    guard let hf = SweepReliefEngine.sweep(
        rail1: rail1, rail2: rail2,
        profile: .rectangle, height: 5.0, cellSizeMm: 1.0
    ) else {
        throw VerifyError.failed("parallel rails sweep produced nil")
    }
    // Bbox: x 0..20, y 0..10 → 20×10 grid @1mm.
    try expect(hf.width >= 19 && hf.width <= 21, "strip width ≈ 20 cells (got \(hf.width))")
    try expect(hf.height >= 9 && hf.height <= 11, "strip height ≈ 10 cells (got \(hf.height))")
    // Interior cells at the strip center carry the full height.
    let cx = hf.width / 2
    let cy = hf.height / 2
    try expectClose(hf.heights[cy * hf.width + cx], 5.0, "strip interior = flat-top height")
    // The strip fills its own bbox (parallel rails → full rectangle), so the
    // corner cell IS inside — verify with diagonal rails instead (below).

    // ── 1b. Diagonal rails → bbox corners are genuinely empty ─────────────
    let diag1 = [pt(0, 0), pt(20, 20)]
    let diag2 = [pt(0, 10), pt(20, 30)]
    guard let diag = SweepReliefEngine.sweep(
        rail1: diag1, rail2: diag2,
        profile: .rectangle, height: 5.0, cellSizeMm: 1.0
    ) else {
        throw VerifyError.failed("diagonal rails sweep produced nil")
    }
    // bbox x 0..20, y 0..30; the top-left corner (0,30) is outside the strip.
    try expectClose(diag.heights[(diag.height - 1) * diag.width + 0], 0.0,
                    "diagonal strip top-left corner outside → 0 (got \(diag.heights[(diag.height - 1) * diag.width + 0]))")
    // Center of the diagonal strip carries the height.
    let dCenter = diag.heights[(diag.height / 2) * diag.width + (diag.width / 2)]
    try expect(dCenter > 4.9, "diagonal strip interior = flat-top height (got \(dCenter))")

    // ── 2. Circle profile → domed top ─────────────────────────────────────
    guard let dome = SweepReliefEngine.sweep(
        rail1: rail1, rail2: rail2,
        profile: .circle, height: 5.0, cellSizeMm: 1.0
    ) else {
        throw VerifyError.failed("circle sweep produced nil")
    }
    let domeCenter = dome.heights[(dome.height / 2) * dome.width + (dome.width / 2)]
    // Center cell is 0.5mm off the true centerline → t ≈ 0.1 → 5·0.9 = 4.5.
    try expect(domeCenter > 4.0, "circle profile peaks near full height on the centerline (got \(domeCenter))")
    // A cell near the rail edge (y ≈ 0 or 10) is much lower.
    let edgeY = min(2, dome.height - 1)
    let edgeCell = dome.heights[edgeY * dome.width + (dome.width / 2)]
    try expect(edgeCell < domeCenter, "circle profile falls toward the rails (edge \(edgeCell) < center \(domeCenter))")

    // ── 3. Unequal point counts → resampled alignment ─────────────────────
    let shortRail1 = [pt(0, 0), pt(20, 0)]              // 2 points
    let longRail2 = (0...20).map { pt(Double($0), 10) } // 21 points
    guard let resampled = SweepReliefEngine.sweep(
        rail1: shortRail1, rail2: longRail2,
        profile: .rectangle, height: 3.0, cellSizeMm: 1.0
    ) else {
        throw VerifyError.failed("unequal rails sweep produced nil")
    }
    try expect(resampled.heights[(resampled.height / 2) * resampled.width + (resampled.width / 2)] > 2.9,
               "unequal rails still produce a filled strip")

    // ── 4. Degenerate rails → nil, no crash ───────────────────────────────
    let empty = SweepReliefEngine.sweep(
        rail1: [], rail2: rail2, profile: .rectangle, height: 5.0
    )
    try expect(empty == nil, "empty rail → nil")
    let single = SweepReliefEngine.sweep(
        rail1: [pt(0, 0)], rail2: rail2, profile: .rectangle, height: 5.0
    )
    try expect(single == nil, "single-point rail → nil")

    // ── 5. Grid geometry ──────────────────────────────────────────────────
    try expectClose(hf.cellSizeMm, 1.0, "cell size 1mm")
    try expectClose(hf.minX, 0.0, "minX = strip bbox min")
    try expectClose(hf.minY, 0.0, "minY = strip bbox min")
    try expect(hf.maxHeight > 0, "strip has positive peak")

    print("ShopPilotVerifySweep: PASS — flat-top strip, domed circle profile, resampled rails, degenerate rails nil, grid geometry")
}

do {
    try main()
} catch {
    print("ShopPilotVerifySweep: FAIL — \(error)")
    exit(1)
}
