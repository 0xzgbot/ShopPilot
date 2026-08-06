import Foundation
import ShopPilotCore

/// SPK-0907 remainder — Drag knife toolpath (blade-offset center path with
/// corner pivots). Verifies the real geometry: the spindle center travels
/// offset by the blade offset AHEAD of the tip along travel; at a corner the
/// center arcs around the corner point at the blade-offset radius (the pivot).
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

/// Parse "G0 X1.000 Y2.000" style moves into (x, y).
func parseXY(_ line: String) -> (Double, Double)? {
    guard let xRange = line.range(of: "X") else { return nil }
    var xStr = String(line[xRange.upperBound...])
    var yStr = ""
    if let yRange = xStr.range(of: "Y") {
        yStr = String(xStr[yRange.upperBound...])
        xStr = String(xStr[..<yRange.lowerBound])
    }
    return (Double(xStr) ?? 0, Double(yStr) ?? 0)
}

func main() throws {
    let params = DragKnifeToolpathParams(bladeOffsetMm: 4.0, cutDepthMm: 2.0)

    // 1. Straight line: center offset ahead of tip by bladeOffset along travel.
    //    Path (0,0)→(10,0) travelling +X: start center (4,0), end center (14,0).
    let line = VectorPath(points: [pt(0, 0), pt(10, 0)], isClosed: false)
    let r1 = DragKnifeToolpathEngine.compute(paths: [line], params: params)
    try expect(r1.gcodeLines.contains("O=DRAG_KNIFE_TOOLPATH"), "drag knife marker")
    let starts = r1.gcodeLines.filter { $0.hasPrefix("G0 X4.000 Y0.000") }
    try expect(!starts.isEmpty, "start center at (4,0) — tip lands on (0,0): \(r1.gcodeLines.filter { $0.hasPrefix("G0 X") }.prefix(3))")
    let ends = r1.gcodeLines.filter { $0.hasPrefix("G1 X14.000 Y0.000") }
    try expect(!ends.isEmpty, "end center at (14,0) — tip on (10,0)")
    try expect(!r1.gcodeLines.contains { $0.hasPrefix("G2") || $0.hasPrefix("G3") },
               "straight line has no pivots")

    // 2. L-corner: (0,0)→(10,0)→(10,10). Turn at (10,0) is +90° (CCW → G3).
    //    Enter center (14,0) [= corner + b·û_in], exit (10,4) [= corner + b·û_out].
    //    Arc I/J = corner − start = (10−14, 0−0) = (−4, 0).
    let lShape = VectorPath(points: [pt(0, 0), pt(10, 0), pt(10, 10)], isClosed: false)
    let r2 = DragKnifeToolpathEngine.compute(paths: [lShape], params: params)
    let arcs = r2.gcodeLines.filter { $0.hasPrefix("G2") || $0.hasPrefix("G3") }
    try expect(arcs.count == 1, "one pivot arc at the corner (got \(arcs.count))")
    try expect(arcs[0].hasPrefix("G3"), "CCW turn → G3 (got \(arcs[0].prefix(2)))")
    try expect(arcs[0].contains("X10.000 Y4.000"), "arc ends at (10,4): \(arcs[0])")
    try expect(arcs[0].contains("I-4.000 J0.000"), "arc center offset (−4,0): \(arcs[0])")
    try expect(r2.gcodeLines.contains { $0.hasPrefix("(Pivot 1: 90°") }, "pivot comment names 90° turn: \(r2.gcodeLines.filter { $0.hasPrefix("(Pivot") })")

    // 3. Reverse corner (CW → G2): (0,0)→(10,0)→(10,−10) turns −90°.
    let cw = VectorPath(points: [pt(0, 0), pt(10, 0), pt(10, -10)], isClosed: false)
    let r3 = DragKnifeToolpathEngine.compute(paths: [cw], params: params)
    let arcs3 = r3.gcodeLines.filter { $0.hasPrefix("G2") || $0.hasPrefix("G3") }
    try expect(arcs3.count == 1 && arcs3[0].hasPrefix("G2"), "CW turn → G2 (got \(arcs3.first?.prefix(2) ?? ""))")

    // 4. Small turn below threshold: no arc.
    let gentle = DragKnifeToolpathParams(bladeOffsetMm: 4.0, pivotThresholdDegrees: 10)
    let shallow = VectorPath(points: [pt(0, 0), pt(10, 0), pt(10.5, 0.04)], isClosed: false)
    let r4 = DragKnifeToolpathEngine.compute(paths: [shallow], params: gentle)
    try expect(!r4.gcodeLines.contains { $0.hasPrefix("G2") || $0.hasPrefix("G3") },
               "turn < threshold skips the pivot arc")

    // 5. Closed square: four 90° pivots, all CCW (G3).
    let square = VectorPath(points: [pt(0, 0), pt(20, 0), pt(20, 20), pt(0, 20)], isClosed: true)
    let r5 = DragKnifeToolpathEngine.compute(paths: [square], params: params)
    let arcs5 = r5.gcodeLines.filter { $0.hasPrefix("G2") || $0.hasPrefix("G3") }
    try expect(arcs5.count == 4, "closed square has 4 pivots (got \(arcs5.count))")
    try expect(arcs5.allSatisfy { $0.hasPrefix("G3") }, "all square turns are CCW")

    // 6. Multiple paths: featureCount = path count.
    let r6 = DragKnifeToolpathEngine.compute(paths: [line, lShape], params: params)
    try expect(r6.featureCount == 2, "featureCount = 2 paths")

    // 7. G-code envelope: percent, M30, Z plunge at −depth.
    try expect(r2.gcodeLines.first == "%" && r2.gcodeLines.last == "%", "percent envelope")
    try expect(r2.gcodeLines.contains("M30"), "M30 end")
    try expect(r2.gcodeLines.contains { $0 == "G1 Z-2.000 F300" }, "plunge to −2.0 at plunge rate")

    // 8. Codable round-trip + legacy decode.
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(DragKnifeToolpathParams.self, from: data)
    try expect(abs(back.bladeOffsetMm - 4.0) < 1e-9, "blade offset round-trips")
    let legacy = "{\"bladeOffsetMm\":6.0}".data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(DragKnifeToolpathParams.self, from: legacy)
    try expect(abs(legacyBack.bladeOffsetMm - 6.0) < 1e-9 && abs(legacyBack.cutDepthMm - 2.0) < 1e-9,
               "legacy decode keeps blade offset + default depth")

    // 9. Tree recalc path: dirty Drag Knife node regenerates.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Drag Knife 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(vectors: [lShape], material: nil, stockHeightMm: 25.0)
    try expect(regenerated.count == 1, "dirty drag knife node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=DRAG_KNIFE_TOOLPATH") == true,
               "regenerated has drag knife marker")

    print("ShopPilotVerifyDragKnife: PASS — offset center path, CCW/CW pivots, threshold skip, closed-square pivots, round-trip + legacy decode, tree recalc")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyDragKnife: FAIL — \(error)")
    exit(1)
}
