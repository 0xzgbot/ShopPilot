import Foundation
import ShopPilotCore

// SPK-2120a — V-bit tip Ø on VCarveGeometry / VCarveParams.
// AC: tipDiameterMm (new-job default 0.1); missing JSON key = 0 so 2010
//     goldens stay byte-stable; wide valley depth changes when tip > 0.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

func main() throws {
    // ── 1. Geometry: tip reduces effective half-width. ─────────────────────
    // 90° bit, half-width 10, maxDepth 50, tip 0 → −10 (golden unchanged).
    let z90sharp = VCarveGeometry.depthForHalfWidth(10, angle: 90, maxDepth: 50)
    try expect(abs(z90sharp - (-10.0)) < 1e-9,
               "90° sharp @ half-width 10 → −10 (\(z90sharp))")
    // Same with tip 2: effective half = 10 − 1 = 9 → −9.
    let z90tip = VCarveGeometry.depthForHalfWidth(10, angle: 90, maxDepth: 50, tipDiameterMm: 2)
    try expect(abs(z90tip - (-9.0)) < 1e-9,
               "90° tip Ø2 @ half-width 10 → −9 (\(z90tip))")
    // Tip larger than half-width → effective half clamped to 0 → depth 0.
    let zTipBig = VCarveGeometry.depthForHalfWidth(1, angle: 90, maxDepth: 50, tipDiameterMm: 3)
    try expect(zTipBig == 0, "tip wider than channel → 0 (\(zTipBig))")
    // 30° bit, half-width 10, tip 0 → −10/tan(15°) ≈ −37.3.
    let z30sharp = VCarveGeometry.depthForHalfWidth(10, angle: 30, maxDepth: 50)
    try expect(abs(z30sharp - (-10.0 / tan(.pi / 12))) < 1e-6,
               "30° sharp @ half-width 10 → −37.3 (\(z30sharp))")
    // 30° bit, half-width 10, tip 2 → effective half = 10 − 1 = 9 → −9/tan(15°) ≈ −33.6.
    let z30tip = VCarveGeometry.depthForHalfWidth(10, angle: 30, maxDepth: 50, tipDiameterMm: 2)
    try expect(abs(z30tip - (-9.0 / tan(.pi / 12))) < 1e-6,
               "30° tip Ø2 @ half-width 10 → −33.6 (\(z30tip))")

    // ── 2. Params: default 0.1, legacy decode 0. ──────────────────────────
    let p = VCarveParams()
    try expect(p.tipDiameterMm == 0.1, "init default tip Ø 0.1")
    let legacyJSON = "{\"vBitAngleDegrees\":90,\"feedRateMmPerMin\":1000,\"plungeFeedRateMmPerMin\":300,\"maxDepthOfCutMm\":2,\"leadInDistanceMm\":5,\"leadOutDistanceMm\":5,\"stepOverMm\":1,\"flatBottomMode\":false,\"startDepthMm\":0,\"flatDepthMm\":1,\"cornerSharpen\":false,\"useVectorStartPoints\":true,\"useVectorSelectionOrder\":false,\"safeZHeightMm\":3.2,\"rampPlungeMoves\":false,\"clearancePassEnabled\":false,\"clearanceToolDiameterMm\":6,\"clearanceDepthMm\":1,\"clearanceStepOverMm\":0.4,\"spindleRpm\":0,\"medialAxisPass\":true,\"medialAxisCellMm\":1,\"flatAreaClearing\":false,\"flatAreaThresholdFactor\":1.5,\"flatAreaStepOverMm\":1}"
    let legacy = try JSONDecoder().decode(VCarveParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.tipDiameterMm == 0, "legacy decode missing key → 0 (byte-stable)")
    let roundtrip = try JSONDecoder().decode(VCarveParams.self, from: try JSONEncoder().encode(p))
    try expect(roundtrip.tipDiameterMm == 0.1, "round-trip keeps 0.1")

    // ── 3. Engine: tip=0 matches today's golden; tip>0 changes wide valley. ─
    func makeRect(w: Double, h: Double) -> VectorPath {
        VectorPath(points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: w, y: 0),
            VectorPoint(x: w, y: h), VectorPoint(x: 0, y: h),
        ], isClosed: true)
    }
    let rect = makeRect(w: 20, h: 10)

    var sharpP = VCarveParams()
    sharpP.tipDiameterMm = 0
    sharpP.maxDepthOfCutMm = 50
    let sharpRes = VCarveEngine.compute(vectors: [rect], params: sharpP)
    var tipP = VCarveParams()
    tipP.tipDiameterMm = 1.0
    tipP.maxDepthOfCutMm = 50
    let tipRes = VCarveEngine.compute(vectors: [rect], params: tipP)

    // tip=0 golden: Z at the long edge (half-width 10) for 90° = −10.
    let sharpZs = sharpRes.gcodeLines.compactMap { l -> Double? in
        guard l.hasPrefix("G1"), let r = l.range(of: "Z([+-]?[0-9]+\\.?[0-9]*)",
                                                  options: .regularExpression) else { return nil }
        return Double(l[r].dropFirst())
    }
    try expect(sharpZs.contains { abs($0 - (-10.0)) < 1e-6 },
               "tip=0 golden reaches −10 at half-width 10")
    // tip=1: effective half at long edge = 10 − 0.5 = 9.5 → −9.5.
    let tipZs = tipRes.gcodeLines.compactMap { l -> Double? in
        guard l.hasPrefix("G1"), let r = l.range(of: "Z([+-]?[0-9]+\\.?[0-9]*)",
                                                  options: .regularExpression) else { return nil }
        return Double(l[r].dropFirst())
    }
    try expect(tipZs.contains { abs($0 - (-9.5)) < 1e-6 },
               "tip=1 reaches −9.5 at half-width 10 (wide valley shallower)")
    // tip=0 is byte-identical to a params struct that never mentions tip.
    var noTipRef = VCarveParams()
    noTipRef.tipDiameterMm = 0
    noTipRef.maxDepthOfCutMm = 50
    let noTipRes = VCarveEngine.compute(vectors: [rect], params: noTipRef)
    try expect(sharpRes.gcodeLines == noTipRes.gcodeLines,
               "tip=0 byte-identical to reference sharp params")

    print(failures == 0
          ? "ShopPilotVerify2120a: PASS"
          : "ShopPilotVerify2120a: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
