import Foundation
import ShopPilotCore

/// SPK-0803 verify (CLT machine, no XCTest).
/// Proves the ARRAY-COPY + MERGE toolpath contract with the REAL G-code
/// transform engine (the legacy `ArrayCopyAndMergeEngine` only fabricates
/// ids/estimates and does NOT close this card):
///   1. MOTION PARSE: G0/G1/G2/G3 lines yield X/Y/Z words; comments, %,
///      O= markers and M-codes pass through untouched.
///   2. LINEAR ARRAY: N copies of a base program translated along X by
///      spacing — exact coordinates on the 2nd/3rd copies, base line
///      preserved, Z words intact, feed words intact.
///   3. ANGLE ARRAY: spacing along a 90° angle translates along +Y.
///   4. CIRCULAR ARRAY: copies placed on a radius sweep — copy positions on
///      the circle at 0°/90°/180°, rotation applied, sheet-center pivot.
///   5. MERGE: two programs concatenate in order with markers preserved;
///      blank-line separator between programs.
/// The session glue (generateArrayCopyToolpath / generateCircularArrayCopyToolpath /
/// generateMergedToolpath into the tree + Cut-menu dialogs) is compile-checked
/// by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let base = [
        "%",
        "O=PROFILE_TOOLPATH",
        "G21 G90",
        "G0 Z5.000",
        "G0 X10.000 Y10.000",
        "G1 Z-2.000 F1000",
        "G1 X50.000 Y10.000",
        "G1 X50.000 Y50.000",
        "G1 X10.000 Y50.000",
        "G1 X10.000 Y10.000",
        "G0 Z5.000",
        "M2",
    ]

    // ── 1. Motion parse + passthrough. ────────────────────────────────────
    let motion = ToolpathGCodeTransformer.motionTarget("G1 X12.5 Y-3.25 Z-1.5 F1500")
    try expect(motion != nil, "G1 line parses as motion")
    try expect(abs((motion?.x ?? 0) - 12.5) < 1e-9, "X word parsed")
    try expect(abs((motion?.y ?? 0) - (-3.25)) < 1e-9, "Y word parsed")
    try expect(abs((motion?.z ?? 0) - (-1.5)) < 1e-9, "Z word parsed")
    try expect(ToolpathGCodeTransformer.motionTarget("%") == nil, "% is not motion")
    try expect(ToolpathGCodeTransformer.motionTarget("O=PROFILE_TOOLPATH") == nil, "O= marker is not motion")
    try expect(ToolpathGCodeTransformer.motionTarget("M2") == nil, "M-code is not motion")
    try expect(ToolpathGCodeTransformer.motionTarget("(comment)") == nil, "comment is not motion")

    // ── 2. Linear array along +X. ─────────────────────────────────────────
    let params = LinearArrayCopyParams(count: 3, spacing: 20.0, angle: 0.0)
    let linear = ToolpathGCodeTransformer.linearArray(base: base, params: params)
    try expect(linear.copyCount == 3, "three copies requested")
    try expect(linear.lines.count == base.count * 3, "each copy repeats the base program")
    try expect(linear.lines[0] == base[0] && linear.lines[1] == base[1], "header/marker pass through")
    // 2nd copy: base lines at index base.count ..< 2*base.count → X +20.
    let copy1Start = base.count
    try expect(linear.lines[copy1Start + 4] == "G0 X30.000 Y10.000",
               "2nd copy X translated by 20 (got \(linear.lines[copy1Start + 4]))")
    try expect(linear.lines[copy1Start + 5] == "G1 Z-2.000 F1000",
               "Z + feed words preserved on 2nd copy")
    // 3rd copy: X +40.
    let copy2Start = base.count * 2
    try expect(linear.lines[copy2Start + 6] == "G1 X90.000 Y10.000",
               "3rd copy X translated by 40 (got \(linear.lines[copy2Start + 6]))")

    // ── 3. Angle array along +Y (90°). ────────────────────────────────────
    let vertical = LinearArrayCopyParams(count: 2, spacing: 15.0, angle: 90.0)
    let vResult = ToolpathGCodeTransformer.linearArray(base: base, params: vertical)
    try expect(vResult.lines[base.count + 4] == "G0 X10.000 Y25.000",
               "90° spacing translates along Y (got \(vResult.lines[base.count + 4]))")

    // ── 4. Circular array on a radius sweep. ──────────────────────────────
    let circular = CircularArrayCopyParams(count: 4, centerX: 0, centerY: 0,
                                           startAngle: 0, endAngle: 270, radius: 50)
    let ring = ToolpathGCodeTransformer.circularArray(base: base, params: circular)
    try expect(ring.copyCount == 4, "four ring copies")
    try expect(ring.lines.count == base.count * 4, "ring repeats the base per copy")
    // Copy 0 occupies lines 0..<base.count. Its 4th line (base index 4,
    // "G0 X10 Y10") rotates 0° then translates (cos0·50, sin0·50) = (50,0).
    try expect(ring.lines[4] == "G0 X60.000 Y10.000",
               "ring copy at 0° sits at +X radius (got \(ring.lines[4]))")
    // Copy 1 (lines base.count ..< 2·base.count): angle 90° → rotate (10,10)
    // in place to (-10,10), translate (cos90·50, sin90·50) = (0,50) → (-10,60).
    try expect(ring.lines[base.count + 4] == "G0 X-10.000 Y60.000",
               "ring copy at 90° rotated + translated (got \(ring.lines[base.count + 4]))")
    // Copy 2 (lines 2·base.count ..< 3·base.count): angle 180° → rotate
    // (10,10) to (-10,-10), translate (-50,0) → (-60,-10).
    try expect(ring.lines[2 * base.count + 4] == "G0 X-60.000 Y-10.000",
               "ring copy at 180° (got \(ring.lines[2 * base.count + 4]))")

    // ── 5. Merge preserves programs + markers. ────────────────────────────
    let programA = ["%", "O=PROFILE_TOOLPATH", "G1 X10 Y10", "M2"]
    let programB = ["%", "O=POCKET_TOOLPATH", "G1 X20 Y20", "M2"]
    let merged = ToolpathGCodeTransformer.merge(programs: [programA, programB])
    try expect(merged.count == 9, "merge = A + blank + B (got \(merged.count) lines)")
    try expect(merged.contains("O=PROFILE_TOOLPATH"), "A marker preserved")
    try expect(merged.contains("O=POCKET_TOOLPATH"), "B marker preserved")
    try expect(merged.firstIndex(of: "O=PROFILE_TOOLPATH")! < merged.firstIndex(of: "O=POCKET_TOOLPATH")!,
               "program order preserved")

    // ── 6. ArrayCopyParamsJSON persists the op config. ────────────────────
    let persisted = ArrayCopyParamsJSON(kind: "circular", count: 6, radius: 50, centerX: 300, centerY: 200)
    let pData = try JSONEncoder().encode(persisted)
    let pBack = try JSONDecoder().decode(ArrayCopyParamsJSON.self, from: pData)
    try expect(pBack.kind == "circular" && pBack.count == 6, "kind/count round-trip")
    try expect(abs(pBack.radius - 50) < 1e-9 && abs(pBack.centerX - 300) < 1e-9, "geometry round-trips")

    print("ShopPilotVerify0803: PASS — real G-code transform engine: motion parse, linear/angle/circular arrays (exact coords), merge order + markers, params persist")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0803: FAIL — \(error)")
    exit(1)
}
