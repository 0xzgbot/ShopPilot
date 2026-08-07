import Foundation
import ShopPilotCore

/// SPK-DrillBank verify (CLT machines, no XCTest).
/// Proves the Drill Bank toolpath engine (parity matrix F34):
///   1. Grid generation: 3×2 at spacing 20/25 from origin (0,0) → 6 points
///      at exact expected coordinates, row-major (col fastest).
///   2. Marker + header: O=DRILL_BANK_TOOLPATH, grid-size comment.
///   3. Through style plunges to full -cutDepth.
///   4. Brad-point style stops at 0.8×cutDepth with the brad-point comment.
///   5. Feed/plunge rates appear in the G-code.
///   6. Explicit points override the grid.
///   7. Codable round-trip.
///   8. spindleRpm > 0 emits M3 S.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    let params = DrillBankToolpathParams(
        gridCols: 3, gridRows: 2,
        spacingX: 20.0, spacingY: 25.0,
        originX: 0.0, originY: 0.0,
        toolDiameterMm: 6.0,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        safetyHeightMm: 10.0,
        cutDepthMm: 10.0,
        style: .through
    )

    // ── 1. Grid generation ────────────────────────────────────────────────
    let grid = params.gridPoints()
    try expect(grid.count == 6, "3×2 grid → 6 points (got \(grid.count))")
    let expected: [(Double, Double)] = [
        (0, 0), (20, 0), (40, 0),
        (0, 25), (20, 25), (40, 25),
    ]
    for (i, pair) in expected.enumerated() {
        try expectClose(grid[i].x, pair.0, "grid point \(i) x")
        try expectClose(grid[i].y, pair.1, "grid point \(i) y")
    }
    try expectClose(grid[0].zDepthMm, -10.0, "grid point depth = -cutDepth")

    // ── 2. Marker + header ────────────────────────────────────────────────
    let result = DrillBankToolpathEngine.compute(params: params)
    try expect(result.gcodeLines.contains("O=DRILL_BANK_TOOLPATH"), "drill-bank marker present")
    try expect(result.gcodeLines.contains("(Drill Bank: 3x2 grid — 6 holes)"), "grid header comment")
    try expect(result.pointCount == 6, "result pointCount 6")

    // ── 3. Through style reaches full depth ───────────────────────────────
    let throughZ = result.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(throughZ.count == 6, "6 plunge moves (through)")
    try expect(throughZ.allSatisfy { $0.contains("-10.000") }, "through plunges to -10.000")
    let throughFeeds = result.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(throughFeeds.allSatisfy { $0.contains("F300") }, "plunge feed F300 in G1 Z lines")

    // ── 4. Brad-point style ───────────────────────────────────────────────
    var bradParams = params
    bradParams.style = .bradPoint
    let brad = DrillBankToolpathEngine.compute(params: bradParams)
    let bradZ = brad.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(bradZ.allSatisfy { $0.contains("-8.000") }, "brad-point plunges to 0.8×10 = -8.000")
    try expect(brad.gcodeLines.contains(where: { $0.contains("Brad-point") }), "brad-point comment present")

    // ── 5. Feed/plunge rates ──────────────────────────────────────────────
    try expect(result.gcodeLines.contains(where: { $0.contains("F300") }), "plunge feed appears")
    try expect(result.gcodeLines.contains(where: { $0.contains("G0 Z10.0") }), "safety height rapids")

    // ── 6. Explicit points override the grid ──────────────────────────────
    let customPoints = [
        DrillPoint(x: 5, y: 5, zDepthMm: -3),
        DrillPoint(x: 55, y: 55, zDepthMm: -3),
    ]
    let custom = DrillBankToolpathEngine.compute(points: customPoints, params: params)
    try expect(custom.pointCount == 2, "explicit points override grid (2 holes)")
    try expect(custom.gcodeLines.contains("(Hole 1/2: X5.000 Y5.000)"), "custom point 1 positioned")
    try expect(custom.gcodeLines.contains("(Hole 2/2: X55.000 Y55.000)"), "custom point 2 positioned")

    // ── 7. Codable round-trip ─────────────────────────────────────────────
    let encoder = JSONEncoder()
    let data = try encoder.encode(params)
    let decoded = try JSONDecoder().decode(DrillBankToolpathParams.self, from: data)
    try expect(decoded.gridCols == 3 && decoded.gridRows == 2, "round-trip grid dims")
    try expect(decoded.style == .through, "round-trip style")
    try expectClose(decoded.spacingX, 20.0, "round-trip spacingX")

    // ── 8. Spindle RPM ────────────────────────────────────────────────────
    var rpmParams = params
    rpmParams.spindleRpm = 12000
    let rpm = DrillBankToolpathEngine.compute(params: rpmParams)
    try expect(rpm.gcodeLines.contains("M3 S12000"), "spindleRpm emits M3 S12000")

    // fromMaterial factory
    let fromMat = DrillBankToolpathParams.fromMaterial(Material.pine, toolDiameter: 6.0)
    try expectClose(fromMat.feedRateMmPerMin, Material.pine.maxFeedRateMmPerMin * 0.5, "fromMaterial feed = 0.5×max")
    try expectClose(fromMat.plungeFeedRateMmPerMin, Material.pine.maxFeedRateMmPerMin * 0.2, "fromMaterial plunge = 0.2×max")

    print("ShopPilotVerifyDrillBank: PASS — 3×2 grid coords, marker+header, through depth, brad-point 0.8×, feeds, point override, Codable round-trip, M3 S, fromMaterial")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyDrillBank: FAIL — \(error)")
    exit(1)
}
