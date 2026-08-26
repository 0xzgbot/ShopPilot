import Foundation
import ShopPilotCore

// SPK-2100d — Rest finish from previous tool on HeightfieldFinishEngine.
// AC: previousToolDiameterMm > 0 finish-machines only leftover cusps;
//     0 = compensated finish without rest (byte-stable vs SPK-2100a).

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

/// Flat plateau (2 mm) with a narrow V-groove carved to 0 down the middle
/// column band — same shape family as the SPK-2100a groovedPlateau fixture.
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

func motionLines(_ lines: [String]) -> [(x: Double, y: Double, z: Double)] {
    var out: [(Double, Double, Double)] = []
    for line in lines where line.hasPrefix("G1") {
        func num(_ key: String) -> Double? {
            guard let r = line.range(of: key + "([+-]?[0-9]+\\.?[0-9]*)",
                                     options: .regularExpression) else { return nil }
            return Double(line[r].dropFirst())
        }
        guard let x = num("X"), let y = num("Y"), let z = num("Z") else { continue }
        out.append((x, y, z))
    }
    return out
}

func main() throws {
    let hf = groovedPlateau()

    // ── 1. Params contract: default 0; round-trip; legacy missing key → 0. ──
    let defaults = HeightfieldFinishParams()
    try expect(defaults.previousToolDiameterMm == 0,
               "init default previousToolDiameterMm == 0")
    let decoded = try JSONDecoder().decode(
        HeightfieldFinishParams.self, from: try JSONEncoder().encode(defaults))
    try expect(decoded.previousToolDiameterMm == 0, "round-trip keeps 0")
    let legacyJSON = "{\"toolDiameterMm\":3.175,\"stepOverMm\":0.8,\"feedRateMmPerMin\":1000,\"plungeFeedRateMmPerMin\":300,\"safeZHeightMm\":5,\"spindleRpm\":10000}"
    let legacy = try JSONDecoder().decode(
        HeightfieldFinishParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.previousToolDiameterMm == 0, "legacy decode missing key -> 0")
    try expect(abs(legacy.stepOverMm - 0.8) < 1e-9, "legacy stepover still 0.8")

    // ── 2. Byte stability: previousTool=0 output identical to plain finish. ─
    let plainParams = HeightfieldFinishParams()
    let plain = HeightfieldFinishEngine.compute(heightfield: hf, params: plainParams)
    var zeroParams = HeightfieldFinishParams()
    zeroParams.previousToolDiameterMm = 0
    let zeroRes = HeightfieldFinishEngine.compute(heightfield: hf, params: zeroParams)
    try expect(plain.gcodeLines.count > 10, "plain finish has motion")
    try expect(plain.gcodeLines == zeroRes.gcodeLines,
               "previousTool=0 byte-identical to plain finish")
    try expect(!plain.gcodeLines.contains { $0.contains("Rest finish") },
               "no rest header when previousTool=0")

    // ── 3. Rest run: header + strictly fewer cuts + cusps still machined. ───
    var restParams = HeightfieldFinishParams()
    restParams.previousToolDiameterMm = 6.35   // big ball rides over the groove
    let rest = HeightfieldFinishEngine.compute(heightfield: hf, params: restParams)
    try expect(rest.gcodeLines.contains { $0.contains("Rest finish") },
               "rest header present when previousTool>0")

    let pm = motionLines(plain.gcodeLines)
    let rm = motionLines(rest.gcodeLines)
    try expect(!pm.isEmpty && !rm.isEmpty, "both runs have G1 moves")
    try expect(rm.count < pm.count,
               "rest emits fewer cuts than plain (\(rm.count) < \(pm.count))")
    // The retained region is the groove the big ball bridged: every retained
    // cut must sit near the groove columns (x within [8.5, 11.5]).
    let offGroove = rm.filter { $0.x < 8.5 || $0.x > 11.5 }
    try expect(offGroove.isEmpty,
               "all retained cuts inside the leftover cusp region (\(offGroove.count) stray)")
    try expect(rm.contains { $0.z < -1e-3 },
               "retained cuts machine below the 2mm surface (groove floor)")

    print(failures == 0
          ? "ShopPilotVerify2100d: PASS"
          : "ShopPilotVerify2100d: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
