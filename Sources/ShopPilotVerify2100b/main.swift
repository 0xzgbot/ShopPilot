import Foundation
import ShopPilotCore

/// SPK-2100b verify (CLT machine, no XCTest).
///
/// Finish 3D form parameters — % stepover + scallop readout + raster angle
/// 0/45/90 honored by `HeightfieldFinishEngine`:
///
///   1. PARAMS: `HeightfieldFinishParams()` defaults `rasterAngleDegrees` to 0
///      (today's Y-lace); a legacy paramsJSON without the key decodes to 0;
///      round-trip preserves 45. `snapRasterAngle` maps any input onto the
///      shipped set {0, 45, 90}. Scallop h = s²/(8R) matches hand math.
///   2. ANGLE-HONORING: angle 0 emits rows of constant Y (unchanged lace);
///      angle 90 emits passes of constant X (transposed); angle 45 emits
///      diagonal passes where X and Y move TOGETHER on the same G1.
///   3. DIAGONAL RIDGE: a knife-edge ridge along the line x − y = 3.0 on a
///      41×41 grid is NEVER visited by the 0° lattice (nearest sampled point
///      sits 0.71 mm off the crest) but the 45° run rides it — dozens of
///      emitted points land within 0.5 mm of the crest line.
///   4. GOLDEN STABILITY: at angle 0 the header comment stays byte-identical
///      to the pre-2100b engine ("(Finish: …mm ball nose, drop-cutter
///      compensated)") and pass comments keep the "(Pass N, Y=…)" form.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance {
        throw VerifyError.failed("\(msg) — expected \(b), got \(a)")
    }
}

/// One emitted XY move (from G0 X.. Y.. or G1 X.. Y.. Z.. F.. lines).
struct MovePoint {
    var x: Double
    var y: Double
    var isCut: Bool // true for G1 feed moves, false for the G0 lead-in
}

/// Split g-code into passes (delimited by "(Pass " comments) and parse the
/// XY of every move line inside each pass.
func passesOf(_ lines: [String]) -> [[MovePoint]] {
    var passes: [[MovePoint]] = []
    var current: [MovePoint] = []
    for line in lines {
        if line.hasPrefix("(Pass") {
            if !current.isEmpty { passes.append(current) }
            current = []
            continue
        }
        let isG0 = line.hasPrefix("G0 X")
        let isG1 = line.hasPrefix("G1 X")
        guard isG0 || isG1 else { continue }
        func axis(_ letter: String) -> Double? {
            guard let r = line.range(of: letter + "([+-]?[0-9]+\\.?[0-9]*)",
                                     options: .regularExpression) else { return nil }
            return Double(line[r].dropFirst())
        }
        guard let x = axis("X"), let y = axis("Y") else { continue }
        current.append(MovePoint(x: x, y: y, isCut: isG1))
    }
    if !current.isEmpty { passes.append(current) }
    return passes
}

/// Flat relief helper.
func flatRelief(n: Int, cell: Double) -> HeightfieldData {
    HeightfieldData(
        width: n, height: n, cellSizeMm: cell, minX: 0, minY: 0,
        heights: [Double](repeating: 2.0, count: n * n)
    )
}

/// Knife-edge ridge along x − y = 3.0: base 1 mm, peak 10 mm, Gaussian
/// falloff sigma 0.8 mm across the crest. Heights are decoration here — the
/// coverage assertions below are purely geometric (XY of emitted moves):
/// the 0° lattice's closest approach to the crest is |4 − 3|/√2 ≈ 0.707 mm,
/// while a 45° pass lands only |−2.284 − (−2.121)| ≈ 0.16 mm off it.
func ridgedRelief() -> HeightfieldData {
    let n = 41
    let cell = 1.0
    var hs: [Double] = []
    hs.reserveCapacity(n * n)
    for j in 0..<n {
        for i in 0..<n {
            let x = (Double(i) + 0.5) * cell
            let y = (Double(j) + 0.5) * cell
            let d = x - y - 3.0
            hs.append(1.0 + 9.0 * exp(-(d * d) / (2.0 * 0.8 * 0.8)))
        }
    }
    return HeightfieldData(
        width: n, height: n, cellSizeMm: cell, minX: 0, minY: 0, heights: hs
    )
}

func main() throws {
    // ── 1. PARAMS: default 0°, legacy decode 0°, round-trip, snap, scallop ──
    let defaults = HeightfieldFinishParams()
    try expectClose(defaults.rasterAngleDegrees, 0, "default rasterAngleDegrees = 0 (today's Y-lace)")

    // Legacy-safe decode: pre-2100b stored paramsJSON has no raster key.
    let legacyJSON = #"{"toolDiameterMm":3.175,"stepOverMm":0.3175,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"safeZHeightMm":5.0,"spindleRpm":18000}"#
    let legacy = try JSONDecoder().decode(HeightfieldFinishParams.self,
                                          from: Data(legacyJSON.utf8))
    try expectClose(legacy.rasterAngleDegrees, 0,
                    "decode missing rasterAngleDegrees key yields legacy default 0")

    // Round-trip preserves an explicit 45° choice.
    var angled = HeightfieldFinishParams()
    angled.rasterAngleDegrees = 45
    let decoded = try JSONDecoder().decode(
        HeightfieldFinishParams.self, from: try JSONEncoder().encode(angled))
    try expectClose(decoded.rasterAngleDegrees, 45, "encode/decode round-trips raster 45")

    // Snap onto the shipped set {0, 45, 90}.
    try expectClose(HeightfieldFinishParams.snapRasterAngle(0), 0, "snap(0) = 0")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(45), 45, "snap(45) = 45")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(90), 90, "snap(90) = 90")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(30), 45, "snap(30) = 45 (nearest)")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(60), 45, "snap(60) = 45 (nearest)")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(100), 90, "snap(100) = 90 (nearest)")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(-45), 0, "snap(-45) wraps to 135 → 0")
    try expectClose(HeightfieldFinishParams.snapRasterAngle(180), 0, "snap(180) = 0")

    // Scallop cusp height h ≈ s² / (8R): s = 10% of D = 0.3175, R = D/2.
    try expectClose(defaults.scallopHeightMm,
                    0.3175 * 0.3175 / (8.0 * (3.175 / 2.0)),
                    "scallop h = s²/(8R) hand-math match")
    // Halving the stepover quarters the scallop (the readout's whole point).
    var halfStep = defaults
    halfStep.stepOverMm = defaults.stepOverMm / 2
    try expectClose(halfStep.scallopHeightMm, defaults.scallopHeightMm / 4,
                    "scallop scales with s² (half stepover → quarter scallop)")
    try expectClose(defaults.snappedRasterAngleDegrees, 0, "snapped default stays 0")

    // ── 2. ANGLE HONORING on a flat relief ────────────────────────────────
    let flat = flatRelief(n: 21, cell: 1.0)

    // 0°: today's lace — every cut row runs along X at constant Y.
    var p0 = HeightfieldFinishParams(stepOverMm: 4.0)
    p0.rasterAngleDegrees = 0
    let run0 = HeightfieldFinishEngine.compute(heightfield: flat, params: p0)
    let passes0 = passesOf(run0.gcodeLines)
    try expect(passes0.count >= 5, "0° run emits multiple passes (got \(passes0.count))")
    for (idx, pass) in passes0.enumerated() {
        let ys = pass.map(\.y)
        let ySpread = (ys.max() ?? 0) - (ys.min() ?? 0)
        try expect(ySpread < 1e-6, "0° pass \(idx) holds constant Y (spread \(ySpread))")
        let xs = pass.map(\.x)
        try expect((xs.max() ?? 0) - (xs.min() ?? 0) > 5,
                   "0° pass \(idx) travels along X")
    }

    // 90°: transposed — every pass runs along Y at constant X.
    var p90 = HeightfieldFinishParams(stepOverMm: 4.0)
    p90.rasterAngleDegrees = 90
    let run90 = HeightfieldFinishEngine.compute(heightfield: flat, params: p90)
    let passes90 = passesOf(run90.gcodeLines)
    try expect(passes90.count >= 5, "90° run emits multiple passes (got \(passes90.count))")
    for (idx, pass) in passes90.enumerated() {
        let xs = pass.map(\.x)
        let xSpread = (xs.max() ?? 0) - (xs.min() ?? 0)
        try expect(xSpread < 1e-6, "90° pass \(idx) holds constant X (spread \(xSpread))")
        let ys = pass.map(\.y)
        try expect((ys.max() ?? 0) - (ys.min() ?? 0) > 5,
                   "90° pass \(idx) travels along Y")
    }

    // 45°: diagonal — at least one pass moves X and Y together per G1.
    var p45 = HeightfieldFinishParams(stepOverMm: 4.0)
    p45.rasterAngleDegrees = 45
    let run45flat = HeightfieldFinishEngine.compute(heightfield: flat, params: p45)
    let passes45 = passesOf(run45flat.gcodeLines)
    var diagonalPassCount = 0
    for pass in passes45 {
        var bothMoving = false
        for i in 1..<pass.count {
            let dx = abs(pass[i].x - pass[i - 1].x)
            let dy = abs(pass[i].y - pass[i - 1].y)
            if dx > 0.05 && dy > 0.05 { bothMoving = true }
        }
        if bothMoving { diagonalPassCount += 1 }
    }
    try expect(diagonalPassCount >= 3,
               "45° run has diagonal passes moving X and Y together (got \(diagonalPassCount))")
    try expect(run45flat.gcodeLines.contains { $0.contains("raster 45deg)") },
               "45° pass comments label the raster angle")
    try expect(run90.gcodeLines.contains { $0.contains("raster 90deg)") },
               "90° pass comments label the raster angle")

    // ── 3. DIAGONAL RIDGE: 45° visits what 0° misses ──────────────────────
    // Crest line x − y = 3.0; perpendicular distance from (x,y) is
    // |x − y − 3| / √2. The 0° sampling lattice (0.5 + 4k) has x − y ∈
    // multiples of 4, so its closest approach is |4 − 3|/√2 ≈ 0.707 mm —
    // the 0° path never gets within 0.5 mm of the crest. The 45° passes run
    // PARALLEL to the crest, and one lands only ~0.16 mm off it.
    let ridge = ridgedRelief()
    let ridgeRun0 = HeightfieldFinishEngine.compute(heightfield: ridge, params: p0)
    let ridgeRun45 = HeightfieldFinishEngine.compute(heightfield: ridge, params: p45)

    func pointsNearCrest(_ lines: [String], within tol: Double) -> Int {
        let sqrt2 = 2.0.squareRoot()
        var count = 0
        for pass in passesOf(lines) where pass.contains(where: \.isCut) {
            for pt in pass {
                let dist = abs(pt.x - pt.y - 3.0) / sqrt2
                if dist < tol { count += 1 }
            }
        }
        return count
    }

    let near0 = pointsNearCrest(ridgeRun0.gcodeLines, within: 0.5)
    let near45 = pointsNearCrest(ridgeRun45.gcodeLines, within: 0.5)
    try expect(near0 == 0,
               "0° lace never visits the diagonal ridge crest (got \(near0) points within 0.5mm)")
    try expect(near45 >= 20,
               "45° lace rides the diagonal ridge (\(near45) points within 0.5mm, need ≥20)")

    // ── 4. GOLDEN STABILITY: 0° output keeps the pre-2100b byte contract ──
    try expect(run0.gcodeLines.contains(
        "(Finish: 3.2mm ball nose, drop-cutter compensated)"),
        "0° header comment is byte-identical to the pre-2100b engine")
    try expect(!run0.gcodeLines.contains(where: { $0.contains(", raster") }),
               "0° output carries no raster suffix (goldens stable)")
    try expect(run0.gcodeLines.contains { $0.hasPrefix("(Pass 1, Y=") },
               "0° pass comments keep the (Pass N, Y=…) form")
    try expect(run0.gcodeLines.first == "%", "0° output still opens with %")
    try expect(run0.gcodeLines.contains("O=FINISH_3D"), "marker O=FINISH_3D intact")
    try expect(run0.passCount == passes0.count,
               "result passCount matches emitted passes")

    print("ShopPilotVerify2100b: PASS — finish form params (% stepover, scallop s²/8R, raster 0/45/90) verified")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2100b: FAIL — \(error)")
    exit(1)
}
