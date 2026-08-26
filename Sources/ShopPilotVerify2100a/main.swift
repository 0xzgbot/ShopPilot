import Foundation
import ShopPilotCore

/// SPK-2100a verify (CLT machine, no XCTest).
///
/// Drop-cutter / ball-nose compensation on `HeightfieldFinishEngine` plus the
/// 10%-of-D default finish stepover:
///
///   1. PARAMS: `HeightfieldFinishParams()` init defaults stepOverMm to
///      0.10 * toolDiameterMm (10% of D, industry finish band); an explicit
///      stepOverMm still wins; DECODE of a legacy paramsJSON missing the key
///      still yields 0.8 (legacy-safe).
///   2. FLAT: on a flat relief the emitted cut Z is the tool CENTER at
///      +R above the surface — compensated Z is NOT the surface Z
///      (naive surface trace would emit 0).
///   3. DOME: at the apex the compensated center rides ~R above the surface
///      contact point; every traced Z sits at or above its surface contact
///      requirement (no gouging anywhere on a convex form).
///   4. VALLEY: over a concave groove narrower than the ball, the center lifts
///      by ~R versus the naive surface trace — the valley is NOT overcut by
///      the ball radius (the old engine drove the center to the floor).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func g1CutZValues(_ lines: [String]) -> [Double] {
    var out: [Double] = []
    for line in lines where line.hasPrefix("G1") && line.contains("Z") {
        if let range = line.range(of: "Z([+-]?[0-9]+\\.?[0-9]*)",
                                  options: .regularExpression),
           let z = Double(line[range].dropFirst()) {
            out.append(z)
        }
    }
    return out
}

/// Flat 6×6 relief at 2 mm, 1 mm cells.
func flatRelief() -> HeightfieldData {
    HeightfieldData(
        width: 6, height: 6, cellSizeMm: 1.0, minX: 0, minY: 0,
        heights: [Double](repeating: 2.0, count: 36)
    )
}

/// Dome: hemisphere radius 8 mm centered on the middle cell of a 41×41 grid
/// at 0.5 mm cells (odd count ⇒ an exact center cell at (10.25, 10.25)).
func domeRelief() -> HeightfieldData {
    let n = 41
    let cell = 0.5
    let centerIdx = 20
    let domeR = 8.0
    var hs: [Double] = []
    hs.reserveCapacity(n * n)
    for j in 0..<n {
        for i in 0..<n {
            let dx = (Double(i) - Double(centerIdx)) * cell
            let dy = (Double(j) - Double(centerIdx)) * cell
            let r2 = dx * dx + dy * dy
            hs.append(r2 >= domeR * domeR ? 0 : (domeR * domeR - r2).squareRoot())
        }
    }
    return HeightfieldData(
        width: n, height: n, cellSizeMm: cell, minX: 0, minY: 0, heights: hs
    )
}

/// Concave groove: base plateau 2 mm with a 3-cell-wide (3 mm) groove carved
/// to 0 down the middle column band of a 21×21 grid at 1 mm cells. The ball
/// (D 3.175) cannot seat to the floor of a 3 mm groove — drop-cutter must
/// hold the center up instead of driving it to the groove floor.
func groovedPlateau() -> HeightfieldData {
    let n = 21
    var hs: [Double] = []
    hs.reserveCapacity(n * n)
    for _ in 0..<n {
        for i in 0..<n {
            hs.append((9...11).contains(i) ? 0.0 : 2.0)
        }
    }
    return HeightfieldData(
        width: n, height: n, cellSizeMm: 1.0, minX: 0, minY: 0, heights: hs
    )
}

func main() throws {
    // ── 1. PARAMS: init default 10% of D; explicit wins; decode stays 0.8. ──
    let defaults = HeightfieldFinishParams()
    try expect(abs(defaults.toolDiameterMm - 3.175) < 1e-9, "default toolDiameterMm = 3.175")
    try expect(abs(defaults.stepOverMm - 0.3175) < 1e-9,
               "HeightfieldFinishParams() gets 10% of D (0.3175, got \(defaults.stepOverMm))")
    let bigTool = HeightfieldFinishParams(toolDiameterMm: 6.0)
    try expect(abs(bigTool.stepOverMm - 0.6) < 1e-9,
               "10% scales with D (6 mm bit → 0.6, got \(bigTool.stepOverMm))")
    let explicit = HeightfieldFinishParams(toolDiameterMm: 3.175, stepOverMm: 0.5)
    try expect(abs(explicit.stepOverMm - 0.5) < 1e-9, "explicit stepOverMm still wins")

    // Legacy decode: pre-2100a stored paramsJSON without a stepOverMm key
    // must still decode to the historical 0.8 default.
    let legacyJSON = #"{"toolDiameterMm":3.175,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"safeZHeightMm":5.0,"spindleRpm":18000}"#
    let legacy = try JSONDecoder().decode(HeightfieldFinishParams.self,
                                          from: Data(legacyJSON.utf8))
    try expect(abs(legacy.stepOverMm - 0.8) < 1e-9,
               "decode missing stepOverMm key still yields legacy 0.8 (got \(legacy.stepOverMm))")

    // Round-trip preserves the NEW init default.
    let roundTrip = try JSONDecoder().decode(
        HeightfieldFinishParams.self, from: try JSONEncoder().encode(defaults))
    try expect(abs(roundTrip.stepOverMm - 0.3175) < 1e-9,
               "encode/decode round-trip preserves the 10%-of-D default")

    // ── 2. FLAT: compensated center Z = +R, NOT the surface Z (= 0 here). ──
    let ballR = 3.175 / 2.0
    let flat = flatRelief()
    let flatRun = HeightfieldFinishEngine.compute(
        heightfield: flat,
        params: HeightfieldFinishParams(stepOverMm: 1.0))
    try expect(flatRun.gcodeLines.contains("O=FINISH_3D"), "finish emits O=FINISH_3D marker")
    try expect(flatRun.gcodeLines.contains { $0.contains("drop-cutter compensated") },
               "finish header documents drop-cutter compensation")
    let flatZ = g1CutZValues(flatRun.gcodeLines)
    try expect(!flatZ.isEmpty, "flat run has cut moves")
    try expect(flatZ.allSatisfy { abs($0 - ballR) < 0.005 },
               "flat: every cut Z is the ball center at +R (\(ballR)), not surface Z 0")
    try expect(abs(flatZ[0] - 0.0) > 0.1,
               "compensated Z is NOT the surface Z on a flat")

    // ── 3. DOME: apex center rides ~R above the surface; no gouge anywhere. ─
    let dome = domeRelief()
    let apexXY = 10.25
    let apexH = dome.heightInterpolated(atX: apexXY, y: apexXY)
    try expect(abs(apexH - 8.0) < 1e-6, "dome fixture peaks at 8 mm at the center cell")
    let domeRun = HeightfieldFinishEngine.compute(
        heightfield: dome,
        params: HeightfieldFinishParams(stepOverMm: 0.5))
    let domeZ = g1CutZValues(domeRun.gcodeLines)
    try expect(!domeZ.isEmpty, "dome run has cut moves")
    let apexSurfaceZ = -(dome.maxHeight - apexH) // naive trace: 0.000
    try expect(domeZ.contains { abs($0 - (apexSurfaceZ + ballR)) < 0.01 },
               "dome apex: compensated Z ≈ surface + R (not the surface Z)")
    // No-gouge invariant: for EVERY traced cut move, the center Z must sit at
    // or above the surface contact point directly beneath it — the ball never
    // drives through its own local contact surface.
    func moveXYZ(_ line: String) -> (x: Double, y: Double, z: Double)? {
        func num(_ key: String) -> Double? {
            guard let r = line.range(of: key + "([+-]?[0-9]+\\.?[0-9]*)",
                                     options: .regularExpression) else { return nil }
            return Double(line[r].dropFirst())
        }
        guard line.hasPrefix("G1"), let x = num("X"), let y = num("Y"),
              let z = num("Z") else { return nil }
        return (x, y, z)
    }
    var checked = 0
    var worstSlack = Double.infinity
    for line in domeRun.gcodeLines {
        guard let m = moveXYZ(line) else { continue }
        let h = dome.heightInterpolated(atX: m.x, y: m.y)
        worstSlack = min(worstSlack, m.z - (-(dome.maxHeight - h)))
        checked += 1
    }
    try expect(checked > 0, "parsed 3-axis dome moves for the no-gouge sweep")
    try expect(worstSlack > -0.02,
               "every dome cut holds the center at/above its local contact (worst slack \(worstSlack))")

    // ── 4. VALLEY: center lifts ~R off the groove floor (no ~R overcut). ────
    let groove = groovedPlateau()
    let grooveRun = HeightfieldFinishEngine.compute(
        heightfield: groove,
        params: HeightfieldFinishParams(stepOverMm: 1.0))
    let grooveMoves = grooveRun.gcodeLines.filter { $0.hasPrefix("G1") && $0.contains("X10.500 Y") }
    try expect(!grooveMoves.isEmpty, "groove run traces the groove centerline")
    let centerlineZ = g1CutZValues(grooveMoves)
    try expect(!centerlineZ.isEmpty, "groove centerline has cut Z values")
    let stockTop = groove.maxHeight // 2.0
    let naiveFloorZ = -(stockTop - 0.0) // naive surface trace at the floor: −2.000
    for z in centerlineZ {
        try expect(abs(z - naiveFloorZ) > 0.1,
                   "centerline Z \(z) is NOT the naive surface trace (\(naiveFloorZ))")
        let liftVsNaive = z - naiveFloorZ
        try expect(liftVsNaive > ballR * 0.9,
                   "valley lift vs naive trace ≈ R (got \(liftVsNaive), R = \(ballR)) — not overcut")
        try expect(liftVsNaive < ballR * 1.1 + 0.05,
                   "valley lift stays honest (~R, got \(liftVsNaive))")
    }

    print("ShopPilotVerify2100a: PASS — drop-cutter ball compensation (flat +R ≠ surface, dome no-gouge, groove lift ≈ R) + stepOver init default 10% of D with legacy 0.8 decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2100a: FAIL — \(error)")
    exit(1)
}
