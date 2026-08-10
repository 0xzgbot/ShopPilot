import Foundation
import ShopPilotCore

/// SPK-0909 verify (CLT machine, no XCTest).
/// Hand-derived GOLDEN G-code for the specialty + rotary + laser engines —
/// every expectation below is traced from the engine semantics BY HAND (not
/// captured from output), so any regression in the emitted lines fails:
///   1. LASER CUT golden: 2-point line, 60% power, 2 passes → exact byte
///      sequence (pass loop, M3 S60/G1 F1200/M5, Z lift between passes).
///   2. LASER ENGRAVE golden: half-speed raster trace, M3 constant, M5 end.
///   3. ROTARY WRAP golden: X=78.5398mm on a Ø50mm stock → A=180° (half the
///      circumference); Y stays axial; CW vs CCW mirror the angle.
///   4. DRAG KNIFE golden: blade-offset start point (spindle center = p0 +
///      b·û) so the tip lands on the vector; pivot at the corner.
///   5. THREAD MILL golden: pitch-per-revolution Z descent (1.25mm pitch →
///      exactly 1.25mm Z per full revolution of 24 arc segments).
/// The AppSession glue (strategy generators + forms) is compile-checked by
/// the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Laser cut golden: line (0,0)→(10,0), 60%, 2 passes. ────────────
    let cut = LaserConfig(mode: .cut, powerPercent: 60, speedMmPerMin: 1200,
                          frequencyHz: 0, passes: 2, powerMode: .constant)
    let cutGcode = LaserEngine.gcodeForCut(config: cut, path: [(0, 0), (10, 0)])
    let cutGolden: [String] = [
        "; Laser cut — 2 pass(es), 60% power, 1200 mm/min",
        "; pass 1/2",
        "G0 X0.000 Y0.000",
        "M3 S60",
        "G1 F1200",
        "G1 X10.000 Y0.000",
        "G1 X0.000 Y0.000", // open path closes back to the start
        "M5",
        "; pass 2/2",
        "G0 Z5.0",
        "G0 X0.000 Y0.000",
        "M3 S60",
        "G1 F1200",
        "G1 X10.000 Y0.000",
        "G1 X0.000 Y0.000",
        "M5",
        "G0 Z5.0",
    ]
    try expect(cutGcode == cutGolden, "laser cut golden mismatch\n  got:  \(cutGcode)\n  want: \(cutGolden)")

    // ── 2. Laser engrave golden: half-speed raster. ───────────────────────
    let eng = LaserConfig(mode: .engrave, powerPercent: 40, speedMmPerMin: 1000,
                          frequencyHz: 0, passes: 1, powerMode: .constant)
    let engGcode = LaserEngine.gcodeForEngrave(config: eng, path: [(5, 5), (15, 5)])
    let engGolden: [String] = [
        "; Laser engrave — 40% power, 500 mm/min (raster)",
        "G0 X5.000 Y5.000",
        "M3 S40",
        "G1 F500",
        "G1 X15.000 Y5.000",
        "M5",
    ]
    try expect(engGcode == engGolden, "laser engrave golden mismatch\n  got:  \(engGcode)\n  want: \(engGolden)")

    // ── 3. Rotary wrap golden: X=78.5398mm on Ø50 → A=180°. ──────────────
    // Circumference = π·50 = 157.0796; 78.5398 is exactly half → 180°.
    let wrapParams = RotaryWrapToolpathParams(diameterMm: 50, cutDepthMm: 1.0,
                                              direction: .clockwise, safeZHeightMm: 5.0)
    let wrapPath = VectorPath(points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 78.5398, y: 20)],
                              isClosed: false)
    let wrapResult = RotaryWrapToolpathEngine.compute(paths: [wrapPath], params: wrapParams, stockHeightMm: 25)
    try expect(wrapResult.gcodeLines[0] == "%" && wrapResult.gcodeLines[1] == "O=ROTARY_WRAP_TOOLPATH",
               "wrap header markers")
    try expect(wrapResult.gcodeLines.contains("G0 A0.000 Y0.000"), "start X=0 → A=0")
    try expect(wrapResult.gcodeLines.contains { $0.hasPrefix("G1 A180.000 Y20.000") },
               "X=78.5398 (half circumference) → A=180°, Y stays axial (got \(wrapResult.gcodeLines.filter { $0.hasPrefix("G1 A") }))")

    // CCW mirrors: 360 − 180 = 180 (symmetric here); quarter circumference
    // 39.2699 → CW 90°, CCW 270°.
    let q = 39.2699
    var ccw = wrapParams
    ccw.direction = .counterClockwise
    let ccwPath = VectorPath(points: [VectorPoint(x: 0, y: 0), VectorPoint(x: q, y: 0)], isClosed: false)
    let ccwResult = RotaryWrapToolpathEngine.compute(paths: [ccwPath], params: ccw, stockHeightMm: 25)
    try expect(ccwResult.gcodeLines.contains { $0.hasPrefix("G1 A270.000 Y0.000") },
               "CCW quarter circumference → A=270° (got \(ccwResult.gcodeLines.filter { $0.hasPrefix("G1 A") }))")
    var cw = wrapParams
    cw.direction = .clockwise
    let cwResult = RotaryWrapToolpathEngine.compute(paths: [ccwPath], params: cw, stockHeightMm: 25)
    try expect(cwResult.gcodeLines.contains { $0.hasPrefix("G1 A90.000 Y0.000") },
               "CW quarter circumference → A=90° (got \(cwResult.gcodeLines.filter { $0.hasPrefix("G1 A") }))")

    // ── 4. Drag knife golden: blade offset start (spindle center). ───────
    // Path (0,0)→(10,0): û = (1,0); start center = (0 + b, 0) = (3, 0) for
    // b = 3mm — the tip lands on (0,0).
    let dragParams = DragKnifeToolpathParams(bladeOffsetMm: 3, cutDepthMm: 1.0,
                                             pivotThresholdDegrees: 45, safeZHeightMm: 5.0)
    let dragPath = VectorPath(points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0), VectorPoint(x: 20, y: 0)],
                              isClosed: false)
    let dragResult = DragKnifeToolpathEngine.compute(paths: [dragPath], params: dragParams, stockHeightMm: 25)
    try expect(dragResult.gcodeLines[1] == "O=DRAG_KNIFE_TOOLPATH", "drag knife marker")
    try expect(dragResult.gcodeLines.contains("G0 X3.000 Y0.000"),
               "drag knife center offsets by blade radius along û (got \(dragResult.gcodeLines.filter { $0.hasPrefix("G0 X") }))")
    // Straight line (no corner pivots): no G2 arcs emitted.
    try expect(!dragResult.gcodeLines.contains { $0.hasPrefix("G2") },
               "straight path emits no pivot arcs")

    // ── 5. Thread mill golden: pitch-per-revolution Z descent. ───────────
    let threadParams = ThreadMillParams(holeDiameterMm: 8, pitchMm: 1.25, threadLengthMm: 12,
                                        isInternal: true, toolDiameterMm: 4,
                                        feedRateMmPerMin: 400, plungeRateMmPerMin: 200,
                                        safeZHeightMm: 5, spindleRpm: 0)
    let threadResult = ThreadMillingToolpathEngine.compute(centerX: 0, centerY: 0, params: threadParams)
    let arcs = threadResult.gcodeLines.filter { $0.hasPrefix("G2 ") }
    // The helix ramps in one pitch above the thread start (topZ = −1.25) and
    // descends to the bottom (−12): travel = 10.75mm = 8.6 revolutions × 24
    // segments = 206.4 → 207 arcs. Hand-derived.
    try expect(arcs.count == 207, "helix arc count = ceil(10.75/1.25 × 24) = 207 (got \(arcs.count))")
    // Z descent per full revolution (24 arcs) must be exactly the pitch.
    let firstZ = zOf(arcs[0])
    let zAtOneRevolution = zOf(arcs[24])
    try expect(abs((firstZ - zAtOneRevolution) - 1.25) < 1e-6,
               "24 arc segments descend exactly one pitch (got \(firstZ - zAtOneRevolution))")

    print("ShopPilotVerify0909: PASS — hand-derived goldens: laser cut/engrave byte-exact, rotary wrap X→A + CW/CCW mirror, drag-knife blade offset, thread-mill pitch-per-revolution")
}

func zOf(_ line: String) -> Double {
    for token in line.split(whereSeparator: { $0 == " " }) {
        let w = String(token)
        if w.hasPrefix("Z"), let v = Double(w.dropFirst()) { return v }
    }
    return 0
}

do {
    try main()
} catch {
    print("ShopPilotVerify0909: FAIL — \(error)")
    exit(1)
}
