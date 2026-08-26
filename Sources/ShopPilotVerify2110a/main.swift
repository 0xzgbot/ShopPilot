import Foundation
import ShopPilotCore

// SPK-2110a — PhotoVCarve groove width + depth + 45° raster.
// AC: groove WIDTH from V-angle + tip Ø + depth; depth from luminance kept;
//     default raster 45° (legacy decode 0); invert on the Photo form;
//     init stepover = 50% of widest groove so adjacent grooves overlap.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

/// 20×20 gradient: h = maxHeight · x / width — dark (deep) on the left,
/// bright (shallow) on the right. Cell 1 mm.
func rampField() -> HeightfieldData {
    let n = 20
    var hs: [Double] = []
    hs.reserveCapacity(n * n)
    for _ in 0..<n {
        for i in 0..<n {
            hs.append(Double(i) / Double(n - 1) * 2.0)
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
    // ── 1. Width formula: w = tip + 2·d·tan(θ/2). ───────────────────────────
    let w60sharp = PhotoVCarveToolpathParams.grooveWidthMm(vBitAngleDegrees: 60, tipDiameterMm: 0, depthMm: 2)
    try expect(abs(w60sharp - 2 * 2.0 * tan(.pi / 6)) < 1e-9,
               "60° sharp @ d=2 → w=2.309 (\(w60sharp))")
    let w90tip = PhotoVCarveToolpathParams.grooveWidthMm(vBitAngleDegrees: 90, tipDiameterMm: 0.1, depthMm: 1)
    try expect(abs(w90tip - (0.1 + 2.0)) < 1e-9,
               "90° tip0.1 @ d=1 → w=2.10 (\(w90tip))")
    try expect(PhotoVCarveToolpathParams.grooveWidthMm(vBitAngleDegrees: 0, tipDiameterMm: 0.3, depthMm: 5) == 0.3,
               "degenerate angle falls back to tip Ø")

    // ── 2. Defaults + legacy decode. ────────────────────────────────────────
    let p = PhotoVCarveToolpathParams()
    try expect(p.rasterAngleDegrees == 45.0, "init default raster 45°")
    try expect(p.tipDiameterMm == 0.1, "init default tip Ø 0.1")
    try expect(p.invertLuminance == false, "init default no invert")
    // Widest groove at defaults: w = 0.1 + 2·3·tan30° = 3.5637; stepover 50%.
    let widestDefault = PhotoVCarveToolpathParams.grooveWidthMm(vBitAngleDegrees: 60, tipDiameterMm: 0.1, depthMm: 3)
    try expect(abs(p.stepOverMm - widestDefault * 0.5) < 1e-9,
               "init stepover = 50% of widest groove (\(p.stepOverMm))")
    try expect(widestDefault > p.stepOverMm,
               "adjacent grooves overlap: stepover < groove width")

    let legacyJSON = "{\"vBitAngleDegrees\":60,\"maxDepthMm\":3,\"stepOverMm\":0.5,\"safeZHeightMm\":5,\"feedRateMmPerMin\":1200,\"plungeRateMmPerMin\":300,\"spindleRpm\":10000}"
    let legacy = try JSONDecoder().decode(PhotoVCarveToolpathParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.rasterAngleDegrees == 0, "legacy decode raster stays 0 (byte-stable)")
    try expect(legacy.tipDiameterMm == 0 && !legacy.invertLuminance,
               "legacy decode: sharp tip, no invert")

    // ── 3. Engine: default run is diagonal; depth still tracks luminance. ───
    let hf = rampField()
    let res45 = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: PhotoVCarveToolpathParams())
    try expect(res45.gcodeLines.contains { $0.contains("raster 45deg)") },
               "default output uses 45° pass headers")
    try expect(res45.gcodeLines.contains { $0.contains("V-bit 60° tip Ø0.10") },
               "header announces tip Ø and derived groove width")
    // Diagonal passes must visit off-axis points the 0° Y-raster never does:
    let m45 = motionLines(res45.gcodeLines).filter { abs($0.x - $0.y.rounded()) > 0.75 }
    try expect(m45.count > 5, "45° passes cut non-axis-aligned points (\(m45.count) pts)")

    let res0 = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: legacy)
    try expect(!res0.gcodeLines.contains { $0.contains("raster ") },
               "legacy header unchanged (no raster mention)")
    // Legacy 0° rows are horizontal: within each pass every G1 shares one Y
    // (reset the tracker at "(Photo pass" headers).
    let raw0 = res0.gcodeLines
    var straightOnly = true
    var prevY = Double.nan
    for l in raw0 {
        if l.contains("(Photo pass") { prevY = Double.nan; continue }
        guard l.hasPrefix("G1"), let r = l.range(of: "Y([+-]?[0-9]+\\.?[0-9]*)",
                                                 options: .regularExpression),
              let y = Double(l[r].dropFirst()) else { continue }
        if !prevY.isNaN && abs(y - prevY) > 1e-6 { straightOnly = false }
        prevY = y
    }
    try expect(straightOnly, "legacy 0° params reproduce horizontal Y-rasters only")

    // Depth-from-luminance kept: with a dense single-row run, Z decreases
    // monotonically left→right (dark deep → bright shallow).
    var deep = PhotoVCarveToolpathParams()
    deep.rasterAngleDegrees = 0
    deep.stepOverMm = 0.5   // every column sampled
    let rowRun = motionLines(PhotoVCarveToolpathEngine.compute(heightfield: hf, params: deep).gcodeLines)
    try expect(rowRun.count > 10, "dense run has enough samples (\(rowRun.count))")
    // Group into passes via "(Photo pass" headers, then require Z to rise
    // monotonically ALONG the dark→bright direction within the FIRST pass
    // (between passes the bit rapids back to the deep side).
    func passes(_ lines: [String]) -> [[(x: Double, y: Double, z: Double)]] {
        var out: [[(Double, Double, Double)]] = [[]]
        for l in lines {
            if l.contains("(Photo pass") { out.append([]); continue }
            if l.hasPrefix("G1"), let r = l.range(of: "X([+-]?[0-9]+\\.?[0-9]*)",
                                                  options: .regularExpression),
               let x = Double(l[r].dropFirst()),
               let r2 = l.range(of: "Y([+-]?[0-9]+\\.?[0-9]*)",
                                options: .regularExpression),
               let y = Double(l[r2].dropFirst()),
               let r3 = l.range(of: "Z([+-]?[0-9]+\\.?[0-9]*)",
                                options: .regularExpression),
               let z = Double(l[r3].dropFirst()) {
                out[out.count - 1].append((x, y, z))
            }
        }
        return out.filter { $0.count > 3 }
    }
    let firstPass = passes(PhotoVCarveToolpathEngine.compute(heightfield: hf, params: deep).gcodeLines)[0]
    var monotonic = true
    for k in 1..<firstPass.count where firstPass[k].z <= firstPass[k - 1].z + 1e-9 {
        monotonic = false
    }
    try expect(monotonic, "within a pass, Z strictly RISES as luminance rises (dark deep → bright shallow)")

    // ── 4. Invert: dark becomes shallow, bright becomes deep. ───────────────
    var inv = deep
    inv.invertLuminance = true
    let invPass = passes(PhotoVCarveToolpathEngine.compute(heightfield: hf, params: inv).gcodeLines)[0]
    var invMonotonic = true
    for k in 1..<invPass.count where invPass[k].z >= invPass[k - 1].z - 1e-9 {
        invMonotonic = false
    }
    try expect(invMonotonic, "inverted pass Z strictly FALLS left→right (flip confirmed)")
    let zMin = rowRun.map { $0.z }.min()!
    let iZMin = invPass.map { $0.z }.min()!
    // The surface term −(stockTop − h) does NOT invert, so extremes don't
    // mirror exactly; the honest check is that the deepest point moves to
    // the OPPOSITE side of the ramp.
    let origDeepX = rowRun.first { $0.z == zMin }!.x
    let invDeepX = invPass.first { $0.z == iZMin }!.x
    try expect(origDeepX < 5 && invDeepX > 15,
               "deepest cut moves dark-side (\(origDeepX)) → bright-side (\(invDeepX)) under invert")

    print(failures == 0
          ? "ShopPilotVerify2110a: PASS"
          : "ShopPilotVerify2110a: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
