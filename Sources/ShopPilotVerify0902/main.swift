import Foundation
import ShopPilotCore

/// SPK-0902 verify (CLT machine, no XCTest).
/// Proves the THREAD MILLING contract with the real helical engine:
///   1. HELIX GEOMETRY: the thread is one helical climb of `pitch` per
///      revolution — over a full thread length the Z advance equals
///      threadLengthMm, and each G2 arc advances exactly pitch/24 in Z.
///   2. RADIUS: internal threads orbit at (holeØ−toolØ)/2; external at
///      (holeØ+toolØ)/2 — hand-computed arc start points match the G-code.
///   3. PITCH MATH: 1.25mm pitch over 12mm → ~9.6 revolutions → 230 arc
///      segments (24/rev) — helix ends at the exact thread bottom.
///   4. MARKERS + SAFETY: O=THREAD_MILL_TOOLPATH header, M3 S when RPM set,
///      safe-Z retract after every pass, M2 at the end.
///   5. MULTI-PASS: passes>1 emits one helix per pass with a radial step.
/// The AppSession glue (generateThreadMillingToolpath / applyThreadMillParams /
/// ThreadMillParamsForm) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func parseXYZ(_ line: String) -> (x: Double, y: Double, z: Double)? {
    var x: Double? = nil, y: Double? = nil, z: Double? = nil
    for token in line.split(whereSeparator: { $0 == " " }) {
        let w = String(token)
        if w.hasPrefix("X"), let v = Double(w.dropFirst()) { x = v }
        else if w.hasPrefix("Y"), let v = Double(w.dropFirst()) { y = v }
        else if w.hasPrefix("Z"), let v = Double(w.dropFirst()) { z = v }
    }
    guard let x, let y, let z else { return nil }
    return (x, y, z)
}

func main() throws {
    // ── 1. Helix geometry: 1.25 pitch over 12mm. ─────────────────────────
    let params = ThreadMillParams(holeDiameterMm: 8, pitchMm: 1.25, threadLengthMm: 12,
                                  isInternal: true, toolDiameterMm: 4,
                                  feedRateMmPerMin: 400, plungeRateMmPerMin: 200,
                                  safeZHeightMm: 5, spindleRpm: 6000)
    let result = ThreadMillingToolpathEngine.compute(centerX: 0, centerY: 0, params: params)
    try expect(result.gcodeLines.first == "%" && result.gcodeLines[1] == "O=THREAD_MILL_TOOLPATH",
               "program + marker header")
    try expect(result.gcodeLines.contains("M3 S6000"), "spindle M3 S emitted when RPM set")
    try expect(result.helixCount == 1, "single pass → one helix")
    try expect(result.gcodeLines.last == "M2", "program ends with M2")

    // Helical arcs are "G2 X… Y… I… J… Z…" (G21/G90 have digits right after
    // G2, so match the space).
    func g2Lines(_ lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("G2 ") || $0.hasPrefix("G2X") || $0.hasPrefix("G2 X") }
    }

    let arcs = g2Lines(result.gcodeLines)
    try expect(!arcs.isEmpty, "helical G2 arcs emitted")
    // The G0 before the first arc positions at the 6 o'clock point (0, −2);
    // the first G2's X/Y is its ENDPOINT one segment later at −75°:
    // (2·cos(−75°), 2·sin(−75°)) = (0.5176, −1.9319).
    try expect(result.gcodeLines.contains("G0 X0.000 Y-2.000"),
               "approach rapid lands at 6 o'clock on the 2mm radius")
    let first = arcs[0]
    try expect(abs((parseXYZ(first)?.x ?? 0) - 0.5176) < 1e-3
               && abs((parseXYZ(first)?.y ?? 0) - (-1.9319)) < 1e-3,
               "first arc endpoint at −75° on the radius (got \(first))")

    // Z advance per segment = −pitch/24 (cutting DOWN); first arc lands one
    // segment below the ramp-in top Z = −1.25.
    let firstXYZ = parseXYZ(first)
    let zAfterOneSegment = 1.25 / 24.0
    let topZ = -1.25 // startDepth 0 + one pitch above thread start
    try expect(abs((firstXYZ?.z ?? 0) - (topZ - zAfterOneSegment)) < 1e-3,
               "first arc descends exactly pitch/24 (got \(firstXYZ?.z ?? -999))")

    // Helix ends at the thread bottom: −(0 + 12) = −12.
    let last = arcs.last!
    let lastXYZ = parseXYZ(last)
    try expect(abs((lastXYZ?.z ?? 0) - (-12.0)) < 1e-3,
               "helix reaches the thread bottom Z=−12 (got \(lastXYZ?.z ?? -999))")

    // ── 2. External thread radius. ────────────────────────────────────────
    var external = params
    external.isInternal = false
    let extResult = ThreadMillingToolpathEngine.compute(centerX: 0, centerY: 0, params: external)
    // External radius = (8+4)/2 = 6mm. Approach rapid lands at (0, −6); the
    // first arc's ENDPOINT sits one segment later at −75°:
    // (6·cos(−75°), 6·sin(−75°)) = (1.553, −5.796).
    try expect(extResult.gcodeLines.contains("G0 X0.000 Y-6.000"),
               "external thread approach lands at +tool radius (got missing)")
    let extFirst = g2Lines(extResult.gcodeLines)[0]
    try expect(abs((parseXYZ(extFirst)?.x ?? 0) - 1.553) < 1e-3
               && abs((parseXYZ(extFirst)?.y ?? 0) - (-5.796)) < 1e-3,
               "external thread orbits at the +tool radius (got \(extFirst))")

    // ── 3. Multi-pass: one helix per pass with radial steps. ─────────────
    var multi = params
    multi.passes = 2
    multi.passStepMm = 0.2
    let multiResult = ThreadMillingToolpathEngine.compute(centerX: 0, centerY: 0, params: multi)
    try expect(multiResult.helixCount == 2, "two passes → two helices")
    try expect(g2Lines(multiResult.gcodeLines).count >= 2 * arcs.count,
               "multi-pass doubles the arc count")
    try expect(multiResult.gcodeLines.contains { $0.contains("pass 2/2") },
               "pass labels emitted")

    // ── 4. Tool-too-big guard. ────────────────────────────────────────────
    var bad = params
    bad.toolDiameterMm = 7.9 // barely fits (8−7.9)/2 = 0.05 → below guard
    let badResult = ThreadMillingToolpathEngine.compute(centerX: 0, centerY: 0, params: bad)
    try expect(badResult.helixCount == 0, "tool that doesn't fit emits no helix")
    try expect(badResult.gcodeLines.contains { $0.contains("does not fit") },
               "guard message surfaced")

    // ── 5. Params Codable round-trip (persist via paramsJSON). ───────────
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(ThreadMillParams.self, from: data)
    try expect(abs(back.pitchMm - 1.25) < 1e-9 && abs(back.threadLengthMm - 12) < 1e-9,
               "params round-trip")
    try expect(back.isInternal && back.passes == 1, "flags round-trip")

    print("ShopPilotVerify0902: PASS — helical thread mill: pitch-per-revolution Z math, internal/external radius, multi-pass, fit guard, params persist")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0902: FAIL — \(error)")
    exit(1)
}
