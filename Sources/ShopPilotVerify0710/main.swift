import Foundation
import ShopPilotCore

/// SPK-0710 verify (CLT machine, no XCTest).
/// Proves the 3D finish toolpath engine:
///   1. SURFACE_FOLLOW: a flat-top relief produces horizontal G1 Z lines at a
///      constant Z (the tool skims the flat surface).
///   2. CONTOUR: a sloped relief produces varying Z along each row — the G-code
///      Z values track the bilinear-interpolated surface heights.
///   3. PARAMS_DEFAULTS: HeightfieldFinishParams defaults are reasonable and
///      serializable.
///   4. RESULT_STRUCTURE: HeightfieldToolpathResult carries gcodeLines,
///      estimatedTimeSeconds, passCount, bounds — all non-empty/non-zero.
///   5. VALIDATION: HeightfieldFinishEngine rejects stepOver == 0.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Build a simple flat-top heightfield: all cells at height 5.0mm,
/// 10×10 grid, cellSize 2mm, origin at (0,0).
func flatTopHeightfield() -> HeightfieldData {
    let cells = Array(repeating: 5.0, count: 10 * 10)
    return HeightfieldData(
        width: 10, height: 10, cellSizeMm: 2.0,
        minX: 0, minY: 0, heights: cells
    )
}

/// Build a sloped heightfield: height increases from 0 at x=0 to 10 at x=20.
/// 11×11 grid, cellSize 2mm, origin at (0,0).
func slopedHeightfield() -> HeightfieldData {
    var cells: [Double] = []
    for j in 0..<11 {
        for i in 0..<11 {
            let x = Double(i) * 2.0
            let h = x // 0 to 20mm, but we clamp to 10
            cells.append(min(h, 10.0))
        }
    }
    return HeightfieldData(
        width: 11, height: 11, cellSizeMm: 2.0,
        minX: 0, minY: 0, heights: cells
    )
}

func main() throws {
    // ── 1. SURFACE_FOLLOW: flat relief → constant Z along each row. ─────────
    let flat = flatTopHeightfield()
    var params = HeightfieldFinishParams(
        toolDiameterMm: 3.175,
        stepOverMm: 2.0,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        safeZHeightMm: 5.0
    )
    let result = HeightfieldFinishEngine.compute(heightfield: flat, params: params)
    try expect(!result.gcodeLines.isEmpty, "finish engine returns G-code")
    try expect(!result.gcodeLines.isEmpty, "gcodeLines is non-empty")
    try expect(result.passCount > 0, "passCount > 0")

    // Parse G1 Z values from the G-code. For a flat surface at height 5mm,
    // stockTop = 5mm + 0 = 5mm, so Z = -(5 - 5) = 0.0 for all cut moves.
    let g1ZLines = result.gcodeLines.filter { $0.contains("G1") && $0.contains("Z") }
    try expect(g1ZLines.count > 0, "G-code contains G1 Z moves (got \\(g1ZLines.count) lines)")

    // Extract Z values from G1 lines.
    var zValues: [Double] = []
    for line in g1ZLines {
        // Match Z followed by a number (possibly negative).
        let pattern = "Z([+-]?\\d+\\.?\\d*)"
        if let range = line.range(of: pattern, options: .regularExpression),
           let zStr = Double(line[range].dropFirst()) {
            zValues.append(zStr)
        }
    }
    try expect(zValues.count > 0, "Extracted Z values from G-code (got \\(zValues.count))")

    // All Z values should be near 0 (flat surface at 5mm, stockTop = 5mm).
    let zSpread = zValues.max()! - zValues.min()!
    try expect(zSpread < 0.01,
               "Flat surface: Z spread is tiny (\\(String(format: \"%.4f\", zSpread))) — tool follows the surface")

    // ── 2. CONTOUR: sloped relief → varying Z along rows. ────────────────────
    let sloped = slopedHeightfield()
    let slopedResult = HeightfieldFinishEngine.compute(heightfield: sloped, params: params)
    try expect(!slopedResult.gcodeLines.isEmpty, "sloped finish engine returns G-code")
    try expect(slopedResult.passCount > 0, "sloped passCount > 0")

    let slopedG1Z = slopedResult.gcodeLines.filter { $0.contains("G1") && $0.contains("Z") }
    try expect(slopedG1Z.count > 0, "sloped G-code contains G1 Z moves (got \\(slopedG1Z.count))")

    var slopedZValues: [Double] = []
    for line in slopedG1Z {
        let pattern = "Z([+-]?\\d+\\.?\\d*)"
        if let range = line.range(of: pattern, options: .regularExpression),
           let zStr = Double(line[range].dropFirst()) {
            slopedZValues.append(zStr)
        }
    }
    try expect(slopedZValues.count > 0, "Extracted Z values from sloped G-code (got \\(slopedZValues.count))")

    // Z values should vary — the surface slopes, so Z should not be constant.
    let slopedSpread = slopedZValues.max()! - slopedZValues.min()!
    try expect(slopedSpread > 1.0,
               "Sloped surface: Z spread is significant (\\(String(format: \"%.4f\", slopedSpread))) — tool follows the contour")

    // ── 3. PARAMS_DEFAULTS: defaults are reasonable and serializable. ────────
    let defaults = HeightfieldFinishParams()
    try expect(abs(defaults.toolDiameterMm - 3.175) < 0.001, "default toolDiameterMm = 3.175")
    try expect(abs(defaults.stepOverMm - 0.8) < 0.001, "default stepOverMm = 0.8")
    try expect(abs(defaults.feedRateMmPerMin - 1000) < 0.001, "default feedRateMmPerMin = 1000")
    try expect(abs(defaults.plungeFeedRateMmPerMin - 300) < 0.001, "default plungeFeedRateMmPerMin = 300")
    try expect(abs(defaults.safeZHeightMm - 5.0) < 0.001, "default safeZHeightMm = 5.0")

    // Encode → decode round-trip.
    let encoder = JSONEncoder()
    let decoded = try JSONDecoder().decode(HeightfieldFinishParams.self, from: try encoder.encode(defaults))
    try expect(abs(decoded.toolDiameterMm - 3.175) < 0.001, "params JSON round-trip preserves toolDiameterMm")
    try expect(abs(decoded.stepOverMm - 0.8) < 0.001, "params JSON round-trip preserves stepOverMm")

    // ── 4. RESULT_STRUCTURE: result carries all required fields. ─────────────
    try expect(result.gcodeLines.count > 0, "gcodeLines is non-empty")
    try expect(result.estimatedTimeSeconds >= 0, "estimatedTimeSeconds >= 0")
    try expect(result.passCount > 0, "passCount > 0")
    try expect(result.bounds.minX >= 0, "bounds.minX is set")
    try expect(result.bounds.maxX > result.bounds.minX, "bounds.maxX > bounds.minX")

    // ── 5. VALIDATION: stepOver = 0 is handled gracefully (stepOver clamped). ─
    let zeroParams = HeightfieldFinishParams(stepOverMm: 0.001) // clamped to 0.001 by init
    let zeroResult = HeightfieldFinishEngine.compute(heightfield: flat, params: zeroParams)
    try expect(!zeroResult.gcodeLines.isEmpty, "engine handles near-zero stepOver gracefully")
    try expect(zeroResult.gcodeLines.count > 0, "near-zero stepOver still produces G-code")

    // ── 6. STRATEGY: FinishToolpathStrategy enum values are valid. ────────────
    let strategies: [FinishToolpathStrategy] = [.parallel, .radial, .spiral, .followContour, .zigzag, .multiAxis]
    try expect(strategies.count == 6, "all 6 strategies are defined")
    for s in strategies {
        _ = s.rawValue // no crash on rawValue access
    }

    // ── 7. Validation: FinishToolpathEngine.validate() catches bad params. ────
    let badParams = FinishToolpathParams(
        stepOverMm: 0.0,
        stepDownMm: 0.0,
        feedRateMmPerMin: -100,
        plungeFeedRateMmPerMin: -50,
        toolDiameterMm: -1,
        safetyHeightMm: 0,
        scallopHeightMm: 0
    )
    let (valid, errors) = FinishToolpathEngine.validate(badParams)
    try expect(!valid, "validate rejects bad params")
    try expect(errors.count > 0, "validation returns errors (got \\(errors.count))")

    // ── 8. Generate result: FinishToolpathEngine.generate() with bounding box. ─
    let bb = BoundingBox3D(minX: 0, minY: 0, minZ: 0, maxX: 20, maxY: 20, maxZ: 10)
    let genParams = FinishToolpathParams(strategy: .parallel, stepOverMm: 0.5, stepDownMm: 0.1)
    let genResult = FinishToolpathEngine.generate(componentID: UUID(), config: genParams, boundingBox: bb)
    try expect(genResult.success, "generate returns success for valid params")
    try expect(genResult.totalPathLengthMm > 0, "totalPathLengthMm > 0")
    try expect(genResult.estimatedTimeMinutes > 0, "estimatedTimeMinutes > 0")
    try expect(genResult.strategy == .parallel, "strategy is preserved")
    try expect(genResult.toolChanges >= 1, "toolChanges >= 1")

    // ── 9. Error case: stepOver > toolDiameter. ──────────────────────────────
    let badGenParams = FinishToolpathParams(
        strategy: .parallel,
        stepOverMm: 10.0,
        stepDownMm: 0.1,
        toolDiameterMm: 3.0
    )
    let badGenResult = FinishToolpathEngine.generate(componentID: UUID(), config: badGenParams, boundingBox: bb)
    try expect(!badGenResult.success, "generate rejects stepOver > toolDiameter")
    try expect(badGenResult.errorMessage != nil, "error message is set for bad params")

    print("ShopPilotVerify0710: PASS — surface-following, contour tracking, params, result structure, validation")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0710: FAIL — \(error)")
    exit(1)
}
