import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// ShopPilotVerifyFitCurves — CLT verify for FitCurvesEngine (no XCTest).
///
/// Parity row D13 (fit curves) goldens, derived BY HAND from the engine
/// semantics, deterministic (no randomness):
///   1. 3-point collinear freehand → cornerCount 0, output points unchanged.
///   2. 90° corner freehand → corner detected, corner point preserved exactly
///      even under maximal smoothing.
///   3. Wavy freehand: smoothing 0 keeps the point count; smoothing 1 never
///      increases it and actually moves at least one point.
///   4. Codable round-trip of FitCurvesParams and FitCurvesResult.
///   5. Circle case samples to 64 points and stays closed (first == last).
///   6. Line passes through as exactly 2 points.
///   7. Resampling: a 10 mm segment at maxSegmentLengthMm 3 → 5 points.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance {
        throw VerifyError.failed("\(msg): expected \(a) ≈ \(b) within \(tolerance)")
    }
}

func main() throws {
    // ── 1. Collinear 3-point freehand passes through unchanged. ────────────
    let collinear = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 5, y: 0), VectorPoint(x: 10, y: 0),
    ])
    let r1 = FitCurvesEngine.fit(shape: collinear, params: FitCurvesParams())
    try expect(r1.cornerCount == 0, "collinear input has no corners (got \(r1.cornerCount))")
    try expect(r1.fitted.count == 1 && r1.fitted[0].count == 3,
               "collinear output keeps 3 points (got \(r1.fitted[0].count))")
    try expect(r1.fitted[0][0] == VectorPoint(x: 0, y: 0)
               && r1.fitted[0][1] == VectorPoint(x: 5, y: 0)
               && r1.fitted[0][2] == VectorPoint(x: 10, y: 0),
               "collinear output points unchanged")

    // ── 2. 90° corner is detected and preserved exactly (max smoothing). ───
    let corner = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0), VectorPoint(x: 10, y: 10),
    ])
    let r2 = FitCurvesEngine.fit(shape: corner, params: FitCurvesParams(smoothing: 1))
    try expect(r2.cornerCount >= 1, "90° corner detected (got \(r2.cornerCount))")
    try expect(r2.fitted.count == 1 && r2.fitted[0].count == 3,
               "90° corner keeps 3 points (got \(r2.fitted[0].count))")
    try expect(r2.fitted[0][1] == VectorPoint(x: 10, y: 0),
               "corner point (10,0) preserved exactly")

    // ── 3. Wavy freehand: smoothing 0 same count, smoothing 1 never grows. ─
    let wavyPoints: [VectorPoint] = [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 1, y: 0.5), VectorPoint(x: 2, y: 0),
        VectorPoint(x: 3, y: -0.5), VectorPoint(x: 4, y: 0), VectorPoint(x: 5, y: 0.5),
        VectorPoint(x: 6, y: 0), VectorPoint(x: 7, y: -0.5), VectorPoint(x: 8, y: 0),
        VectorPoint(x: 9, y: 0.5), VectorPoint(x: 10, y: 0),
    ]
    let wavy = VectorShape.freehand(points: wavyPoints)
    let r3a = FitCurvesEngine.fit(shape: wavy, params: FitCurvesParams(smoothing: 0))
    try expect(r3a.inputPointCount == wavyPoints.count
               && r3a.outputPointCount == wavyPoints.count,
               "smoothing 0 keeps the point count (\(r3a.inputPointCount) -> \(r3a.outputPointCount))")

    let r3b = FitCurvesEngine.fit(shape: wavy, params: FitCurvesParams(smoothing: 1))
    try expect(r3b.outputPointCount <= r3b.inputPointCount,
               "smoothing 1 never increases the point count (\(r3b.inputPointCount) -> \(r3b.outputPointCount))")
    var moved = false
    for (a, b) in zip(r3b.fitted[0], wavyPoints) {
        if abs(a.x - b.x) > 1e-9 || abs(a.y - b.y) > 1e-9 {
            moved = true
            break
        }
    }
    try expect(moved, "smoothing 1 actually smooths (at least one point moved)")

    // ── 4. Codable round-trip. ─────────────────────────────────────────────
    let params = FitCurvesParams(smoothing: 0.75, cornerAngleDegrees: 45, maxSegmentLengthMm: 2.5)
    let paramsData = try JSONEncoder().encode(params)
    let paramsBack = try JSONDecoder().decode(FitCurvesParams.self, from: paramsData)
    try expect(paramsBack.smoothing == 0.75
               && paramsBack.cornerAngleDegrees == 45
               && paramsBack.maxSegmentLengthMm == 2.5,
               "FitCurvesParams round-trips through Codable")

    let resultData = try JSONEncoder().encode(r2)
    let resultBack = try JSONDecoder().decode(FitCurvesResult.self, from: resultData)
    try expect(resultBack.inputPointCount == r2.inputPointCount
               && resultBack.outputPointCount == r2.outputPointCount
               && resultBack.cornerCount == r2.cornerCount
               && resultBack.fitted == r2.fitted,
               "FitCurvesResult round-trips through Codable")

    // ── 5. Circle samples to 64 points and stays closed. ───────────────────
    let circle = VectorShape.circle(center: VectorPoint(x: 10, y: 10), radius: 5)
    let r5 = FitCurvesEngine.fit(shape: circle, params: FitCurvesParams())
    try expect(r5.inputPointCount == 64 && r5.fitted[0].count == 64,
               "circle samples to 64 points (got \(r5.fitted[0].count))")
    let first = r5.fitted[0].first!
    let last = r5.fitted[0].last!
    try expectClose(first.x, last.x, "circle closing x")
    try expectClose(first.y, last.y, "circle closing y")
    try expect(r5.cornerCount == 0, "circle has no hard corners (got \(r5.cornerCount))")

    // ── 6. Line passes through as exactly 2 points. ────────────────────────
    let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 10))
    let r6 = FitCurvesEngine.fit(shape: line, params: FitCurvesParams())
    try expect(r6.inputPointCount == 2 && r6.outputPointCount == 2 && r6.cornerCount == 0,
               "line passes through as 2 points (got \(r6.outputPointCount))")

    // ── 7. Resampling: 10 mm segment at 3 mm max → 4 parts, 5 points. ──────
    let longSeg = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0),
    ])
    let r7 = FitCurvesEngine.fit(shape: longSeg, params: FitCurvesParams(maxSegmentLengthMm: 3))
    try expect(r7.fitted[0].count == 5,
               "10 mm segment resampled at 3 mm max yields 5 points (got \(r7.fitted[0].count))")

    print("ShopPilotVerifyFitCurves: PASS — collinear passthrough, 90° corner preservation, smoothing 0/1 counts, Codable round-trip, circle 64-point closed sampling, line passthrough, 3 mm resampling")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyFitCurves: FAIL — \(error)")
    exit(1)
}
