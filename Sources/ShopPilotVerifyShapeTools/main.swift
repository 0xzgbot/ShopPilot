import Foundation
import ShopPilotCore

/// SPK-0703 verify (CLT machines, no XCTest).
/// Proves the parametric shape-relief engine (`ShapeReliefGenerator`):
///   1. Flat: constant plane at flatHeight everywhere; clamped ≥ 0 / ≤ peak.
///   2. Angled: linear ramp 0 at the left edge → peak at the right edge
///      (monotone in x, constant in y).
///   3. Round: dome peaked at the center, falling to 0 at the corners
///      (monotone in distance-from-center).
///   4. Smooth: bell peaked at center; higher smoothness → broader shoulder
///      (a mid-ring cell rises as smoothness goes 0.2 → 0.9).
///   5. Grid shape: width/height/cellSize drive cols/rows; minX/minY = 0.
///   6. Custom falls back to a flat plane (never empty).
///   7. Codable round-trip of ShapeParameters.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    let peak = 10.0

    // ── 1. Flat ───────────────────────────────────────────────────────────
    let flat = ShapeReliefGenerator.generate(
        shapeType: .flat,
        params: ShapeParameters(flatHeight: 3.0),
        width: 20, height: 10, cellSizeMm: 2.0, maxHeight: peak
    )
    try expect(flat.width == 10 && flat.height == 5, "20×10mm @2mm → 10×5 grid (got \(flat.width)×\(flat.height))")
    try expect(flat.heights.allSatisfy { abs($0 - 3.0) < 1e-9 }, "flat plane = 3.0 everywhere")
    try expectClose(flat.maxHeight, 3.0, "flat maxHeight 3")

    // Negative flat height clamps to 0.
    let flatNeg = ShapeReliefGenerator.generate(
        shapeType: .flat,
        params: ShapeParameters(flatHeight: -2.0),
        width: 10, height: 10, cellSizeMm: 2.0, maxHeight: peak
    )
    try expect(flatNeg.heights.allSatisfy { $0 == 0 }, "negative flatHeight clamps to 0")

    // ── 2. Angled (ramp) ──────────────────────────────────────────────────
    let angled = ShapeReliefGenerator.generate(
        shapeType: .angled,
        params: ShapeParameters(angle: 45),
        width: 20, height: 10, cellSizeMm: 2.0, maxHeight: peak
    )
    // 10 cols; col 0 ≈ 0.05·peak, col 9 ≈ 0.95·peak — monotone increasing in x.
    let col0 = angled.heights[0 * angled.width + 0]
    let colLast = angled.heights[0 * angled.width + (angled.width - 1)]
    try expect(colLast > col0, "angled ramp rises left → right")
    try expectClose(col0, peak * 0.5 / Double(angled.width), "angled col0 ≈ peak/2n")
    // Monotone: every row increases across columns.
    for j in 0..<angled.height {
        for i in 1..<angled.width {
            try expect(angled.heights[j * angled.width + i] >= angled.heights[j * angled.width + i - 1] - 1e-9,
                       "angled monotone in x at row \(j), col \(i)")
        }
    }

    // ── 3. Round (dome) ───────────────────────────────────────────────────
    let round = ShapeReliefGenerator.generate(
        shapeType: .round,
        params: ShapeParameters(radius: 4.0),
        width: 20, height: 20, cellSizeMm: 2.0, maxHeight: peak
    )
    // 10×10 grid — even dims have no cell exactly at center, so the peak cell
    // sits at (4,4)/(5,5) and reaches ≈ peak·sqrt(1−0.01) = 9.95; the closest
    // cell to center must be within 5% of the peak.
    let centerIdx = (round.height / 2) * round.width + (round.width / 2)
    try expect(round.heights[centerIdx] > peak * 0.95, "round dome peaks near center (got \(round.heights[centerIdx]))")
    // The corner cell center is inset (r = 0.9 on a 10×10 grid), so the dome
    // reads peak·sqrt(1−0.81) = 4.36 there — the corner is the global
    // minimum and well under half the peak.
    let corner = round.heights[0]
    try expect(round.heights.min() == corner, "round dome corner is the global minimum")
    try expect(corner < peak * 0.5, "round dome corner well under half the peak (got \(corner))")
    // Monotone: every cell ≤ the center cell.
    let cx = round.width / 2
    let cy = round.height / 2
    for j in 0..<round.height {
        for i in 0..<round.width {
            try expect(round.heights[j * round.width + i] <= round.heights[centerIdx] + 1e-9,
                       "round dome never exceeds center at (\(i),\(j))")
        }
    }

    // ── 4. Smooth (bell) — smoothness broadens the shoulder ───────────────
    let smoothNarrow = ShapeReliefGenerator.generate(
        shapeType: .smooth,
        params: ShapeParameters(smoothness: 0.2),
        width: 20, height: 20, cellSizeMm: 2.0, maxHeight: peak
    )
    let smoothBroad = ShapeReliefGenerator.generate(
        shapeType: .smooth,
        params: ShapeParameters(smoothness: 0.9),
        width: 20, height: 20, cellSizeMm: 2.0, maxHeight: peak
    )
    let cx2 = smoothNarrow.width / 2
    let cy2 = smoothNarrow.height / 2
    // A cell ~60% of the way to the corner: broad bell has more height there.
    let probeI = min(smoothNarrow.width - 1, cx2 + Int(Double(cx2) * 0.6))
    let probeJ = min(smoothNarrow.height - 1, cy2 + Int(Double(cy2) * 0.6))
    let narrowProbe = smoothNarrow.heights[probeJ * smoothNarrow.width + probeI]
    let broadProbe = smoothBroad.heights[probeJ * smoothNarrow.width + probeI]
    try expect(broadProbe > narrowProbe, "smoothness 0.9 has a broader shoulder than 0.2 (narrow \(narrowProbe), broad \(broadProbe))")
    // Center cell (even grid, r = 0.1) reads peak·0.5·(1+cos(π·0.217)) ≈ 8.88
    // for narrow and ≈ 9.87 for broad — both within 15% of the peak.
    try expect(smoothNarrow.heights[cy2 * smoothNarrow.width + cx2] > peak * 0.85,
               "smooth center near peak (narrow got \(smoothNarrow.heights[cy2 * smoothNarrow.width + cx2]))")
    try expect(smoothBroad.heights[cy2 * smoothNarrow.width + cx2] > peak * 0.85,
               "smooth broad center near peak (got \(smoothBroad.heights[cy2 * smoothNarrow.width + cx2]))")

    // ── 5. Custom → flat fallback (never empty) ───────────────────────────
    let custom = ShapeReliefGenerator.generate(
        shapeType: .custom,
        params: ShapeParameters(flatHeight: 1.5),
        width: 10, height: 10, cellSizeMm: 2.0, maxHeight: peak
    )
    try expect(custom.heights.allSatisfy { abs($0 - 1.5) < 1e-9 }, "custom falls back to flat plane")

    // ── 6. Codable round-trip ─────────────────────────────────────────────
    let params = ShapeParameters(angle: 30, radius: 5, smoothness: 0.7, flatHeight: 2.5)
    let data = try JSONEncoder().encode(params)
    let decoded = try JSONDecoder().decode(ShapeParameters.self, from: data)
    try expectClose(decoded.angle, 30, "params round-trip angle")
    try expectClose(decoded.smoothness, 0.7, "params round-trip smoothness")

    // ── 7. ShapeType displayName ──────────────────────────────────────────
    try expect(ShapeType.angled.displayName == "Angled", "angled displayName")
    try expect(ShapeType.flat.displayName == "Flat", "flat displayName")

    print("ShopPilotVerifyShapeTools: PASS — flat plane, angled ramp monotone, round dome, smooth bell broadening, custom fallback, Codable round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyShapeTools: FAIL — \(error)")
    exit(1)
}
