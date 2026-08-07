import Foundation
import ShopPilotCore

/// SPK-0712 verify (CLT machines, no XCTest).
/// Proves the component operations engine (`ComponentOperationEngine`):
///   1. Smooth: Laplacian relaxation reduces local variance (a spiky grid
///      flattens toward its neighbours); preserveVolume keeps the mean.
///   2. Emboss: raised adds a dome (peak = depth at center), recessed
///      subtracts clamped ≥ 0; grid geometry preserved.
///   3. Bake: the visible component stack composites into one relief.
///   4. Split: cells above the plane are kept and re-based to 0; below-plane
///      cells read 0.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    // A 7×7 grid with a tall center spike over a flat 2.0 base.
    var base = [Double](repeating: 2.0, count: 49)
    base[3 * 7 + 3] = 10.0
    let spike = HeightfieldData(width: 7, height: 7, cellSizeMm: 1.0, minX: 0, minY: 0, heights: base)

    // ── 1. Smooth ─────────────────────────────────────────────────────────
    let smoothed = ComponentOperationEngine.smooth(
        spike,
        params: SmoothParams(iterations: 10, smoothingFactor: 0.5, algorithm: .laplacian)
    )
    try expect(smoothed.heights[3 * 7 + 3] < 10.0, "smooth lowers the spike (got \(smoothed.heights[3 * 7 + 3]))")
    try expect(smoothed.heights[3 * 7 + 3] > 2.0, "smooth keeps the spike above the base (got \(smoothed.heights[3 * 7 + 3]))")
    try expect(smoothed.width == 7 && smoothed.height == 7, "smooth keeps grid dims")

    // Smoothing reduces variance: neighbours of the spike rise.
    try expect(smoothed.heights[3 * 7 + 4] > 2.0, "smooth raises the spike's neighbours (got \(smoothed.heights[3 * 7 + 4]))")

    // PreserveVolume keeps the mean close to the original.
    let preserved = ComponentOperationEngine.smooth(
        spike,
        params: SmoothParams(iterations: 10, smoothingFactor: 0.5, preserveVolume: true)
    )
    let originalMean = spike.heights.reduce(0, +) / 49.0
    let preservedMean = preserved.heights.reduce(0, +) / 49.0
    try expectClose(preservedMean, originalMean, "preserveVolume keeps the mean", tolerance: 1e-6)

    // ── 2. Emboss ─────────────────────────────────────────────────────────
    // Raised: center gains the full depth; corners gain ~0.
    let flat = HeightfieldData(width: 7, height: 7, cellSizeMm: 1.0, minX: 0, minY: 0, heights: [Double](repeating: 0, count: 49))
    let raised = ComponentOperationEngine.emboss(
        flat,
        params: EmbossParams(embossType: .raised, depth: 4.0)
    )
    try expectClose(raised.heights[3 * 7 + 3], 4.0, "raised emboss peaks at depth in the center")
    try expect(raised.heights[0] < 1.0, "raised emboss ~0 at the corner (got \(raised.heights[0]))")

    // Recessed: subtracts from a base, clamped ≥ 0.
    let recessed = ComponentOperationEngine.emboss(
        spike,
        params: EmbossParams(embossType: .recessed, depth: 5.0)
    )
    try expectClose(recessed.heights[3 * 7 + 3], 5.0, "recessed emboss subtracts from the spike (10−5)")
    try expect(recessed.heights.allSatisfy { $0 >= 0 }, "recessed emboss clamps ≥ 0")
    try expect(recessed.width == 7, "emboss keeps grid width")

    // ── 3. Bake ───────────────────────────────────────────────────────────
    var componentA = ReliefComponent(name: "A", heightfield: HeightfieldData(width: 7, height: 7, cellSizeMm: 1.0, minX: 0, minY: 0, heights: [Double](repeating: 2.0, count: 49)))
    var componentB = ReliefComponent(name: "B", heightfield: HeightfieldData(width: 7, height: 7, cellSizeMm: 1.0, minX: 0, minY: 0, heights: [Double](repeating: 3.0, count: 49)))
    let baked = ComponentOperationEngine.bake([componentA, componentB])
    try expect(baked != nil, "bake composites the stack")
    // Add caps at max(a.maxHeight, b.maxHeight) = 3: min(3, 2+3) = 3.
    try expectClose(baked!.heights[0], 3.0, "bake Add caps at the tallest input (min(3, 5) = 3)")

    // Invisible components are skipped by the compositor.
    componentB.visible = false
    let bakedHidden = ComponentOperationEngine.bake([componentA, componentB])
    try expectClose(bakedHidden!.heights[0], 2.0, "bake skips hidden components")

    // ── 4. Split ──────────────────────────────────────────────────────────
    let split = ComponentOperationEngine.split(spike, planeHeight: 3.0)
    // Base cells (2.0) are below the plane → 0; the spike (10) → 7 (10−3),
    // then re-based so the minimum is 0 (spike stays 7).
    try expectClose(split.heights[3 * 7 + 3], 7.0, "split keeps the part above the plane (10−3)")
    try expectClose(split.heights[0], 0.0, "split zeroes cells below the plane (2−3 → 0)")
    try expect(split.heights.allSatisfy { $0 >= 0 }, "split never emits negative heights")

    // Re-basing: split at 0 keeps everything, minimum becomes 0.
    let splitZero = ComponentOperationEngine.split(spike, planeHeight: 0.0)
    try expect(splitZero.heights.allSatisfy { $0 >= 0 }, "split at 0 keeps all non-negative")

    print("ShopPilotVerifyComponentOps: PASS — smooth variance reduction + volume preserve, emboss raised/recessed, bake composite + hidden skip, split plane + re-base")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyComponentOps: FAIL — \(error)")
    exit(1)
}
