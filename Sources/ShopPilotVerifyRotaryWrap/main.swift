import Foundation
import ShopPilotCore

/// SPK-0904 lean slice — Rotary Wrap toolpath. Verifies the real wrap math:
/// X (flat unwrap mm) maps to A-axis degrees via circumference (X = ¼
/// circumference → A 90°), direction flips the sweep, Y stays the axial
/// dimension, marker + envelope, persistence + legacy decode, tree recalc.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // Ø50 → circumference 157.08. A line across one full wrap:
    // (0,0) → (157.08, 10) should map to A 0 → A 360 (0) at Y 10.
    let wrap = VectorPath(points: [pt(0, 0), pt(157.07963267949, 10)], isClosed: false)
    let params = RotaryWrapToolpathParams(diameterMm: 50.0, cutDepthMm: 1.5)
    let result = RotaryWrapToolpathEngine.compute(paths: [wrap], params: params)

    // 1. Marker + envelope.
    try expect(result.gcodeLines.contains("O=ROTARY_WRAP_TOOLPATH"), "rotary wrap marker")
    try expect(result.gcodeLines.first == "%" && result.gcodeLines.last == "%", "percent envelope")
    try expect(result.gcodeLines.contains("M30"), "M30 end")
    try expect(result.gcodeLines.contains("G1 Z-1.500 F300"), "plunge to −1.5 at plunge rate")

    // 2. X → A: start A0, end A360 (= A0 after modulo) — both are A0.000.
    let start = result.gcodeLines.first { $0.hasPrefix("G0 A0.000 Y0.000") }
    try expect(start != nil, "start maps to A0 Y0 (got \(result.gcodeLines.filter { $0.hasPrefix("G0 A") }.prefix(2)))")
    let end = result.gcodeLines.first { $0.hasPrefix("G1 A") && $0.contains("Y10.000") }
    try expect(end?.contains("A0.000") == true, "full circumference wraps to A0 (got \(end ?? "nil"))")

    // 3. Quarter wrap: X = circumference/4 = 39.27 → A 90°.
    let quarter = VectorPath(points: [pt(0, 0), pt(39.269908169872, 5)], isClosed: false)
    let rq = RotaryWrapToolpathEngine.compute(paths: [quarter], params: params)
    let qMove = rq.gcodeLines.first { $0.hasPrefix("G1 A") && $0.contains("Y5.000") }
    try expect(qMove?.contains("A90.000") == true, "quarter circumference → A90 (got \(qMove ?? "nil"))")

    // 4. Direction: counter-clockwise mirrors the sweep (X ¼ → A 270).
    let ccw = RotaryWrapToolpathParams(diameterMm: 50.0, direction: .counterClockwise)
    let rc = RotaryWrapToolpathEngine.compute(paths: [quarter], params: ccw)
    let cMove = rc.gcodeLines.first { $0.hasPrefix("G1 A") && $0.contains("Y5.000") }
    try expect(cMove?.contains("A270.000") == true, "CCW quarter → A270 (got \(cMove ?? "nil"))")

    // 5. Y axis preserved exactly (not rotated).
    let diag = VectorPath(points: [pt(0, 2), pt(39.269908169872, 8)], isClosed: false)
    let rd = RotaryWrapToolpathEngine.compute(paths: [diag], params: params)
    try expect(rd.gcodeLines.contains { $0.hasPrefix("G0 A0.000 Y2.000") }, "start keeps Y2")
    try expect(rd.gcodeLines.contains { $0.hasPrefix("G1 A90.000 Y8.000") }, "end keeps Y8")

    // 6. Feature count = path count; time estimate positive.
    try expect(result.featureCount == 1, "1 wrapped path")
    try expect(result.estimatedTimeSeconds > 0, "time estimate positive")

    // 7. Params round-trip + legacy decode.
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(RotaryWrapToolpathParams.self, from: data)
    try expect(abs(back.diameterMm - 50.0) < 1e-9, "diameter round-trips")
    let legacy = "{\"diameterMm\":80.0}".data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(RotaryWrapToolpathParams.self, from: legacy)
    try expect(abs(legacyBack.diameterMm - 80.0) < 1e-9 && abs(legacyBack.cutDepthMm - 1.0) < 1e-9,
               "legacy decode keeps diameter + default depth")

    // 8. Tree recalc: dirty Rotary Wrap node regenerates.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Rotary Wrap 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(vectors: [wrap], material: nil, stockHeightMm: 25.0)
    try expect(regenerated.count == 1, "dirty rotary wrap node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=ROTARY_WRAP_TOOLPATH") == true,
               "regenerated has rotary wrap marker")

    print("ShopPilotVerifyRotaryWrap: PASS — X→A mapping (quarter=90°, full=0°), CCW mirror (270°), Y preserved, round-trip + legacy decode, tree recalc")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyRotaryWrap: FAIL — \(error)")
    exit(1)
}
