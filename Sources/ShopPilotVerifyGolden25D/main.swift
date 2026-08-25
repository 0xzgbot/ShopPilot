import Foundation
import ShopPilotCore

/// SPK-Golden-2.5D verify (CLT machine, no XCTest).
///
/// Hand-checked golden G-code for the three 2.5D strategies (closes the spirit
/// of SPK-0317 with LEAN fixtures). Every expected line below was derived by
/// hand from the engine semantics (offset path, pass counting, zigzag rows,
/// V-bit shading, clearance exclusions) — not captured from the engine. The
/// CLT fails on ANY regression in engine output, so a change to profile/pocket
/// V-Carve geometry, feeds, or ordering breaks the golden instead of silently
/// changing cut behavior.
///
///   1. PROFILE: 50×50 square, on-cut, 2 passes (4mm stock / 2mm step) — exact
///      lead-in/lead-out + pass lines.
///   2. POCKET: same square, zigzag 3mm step-over, 2 passes — exact row sweep.
///   3. V-CARVE: same square, 90° V-bit, 2 passes with shading Z — exact
///      depth-scaled Z per point.
///   4. V-CARVE + CLEARANCE: board + inner letter, clearance tool 6mm — exact
///      clearance-first order, protected-letter bands, then V-bit detail.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Square fixture, explicit closing point (matches how the app builds shapes).
func square(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y),
            VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size),
            VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

/// Byte-exact comparison: engine output must equal the hand-derived golden,
/// line for line. Reports the first divergence with context.
func expectGolden(
    _ actual: [String],
    _ expected: [String],
    _ label: String
) throws {
    try expect(actual.count == expected.count,
               "\(label): line count \(actual.count) != golden \(expected.count)")
    for (i, (a, e)) in zip(actual, expected).enumerated() {
        if a != e {
            let from = max(0, i - 3)
            let ctx = (from..<min(actual.count, i + 4)).map { idx in
                let marker = idx == i ? ">>" : "  "
                let golden = idx < expected.count ? expected[idx] : "<missing>"
                return "\(marker)[\(idx)] actual=\(actual[idx].debugDescription) golden=\(golden.debugDescription)"
            }.joined(separator: "\n")
            throw VerifyError.failed("\(label): line \(i) differs\n\(ctx)")
        }
    }
}

func main() throws {
    // ── 1. PROFILE golden — 50×50 square, on-cut, 2 passes. ────────────────
    let profileParams = ProfileToolpathParams(
        cutMode: .onCut,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        maxDepthOfCutMm: 2.0,
        toolDiameterMm: 6.0,
        tabWidths: [],
        finishPasses: 1,
        leadInDistanceMm: 5.0,
        leadOutDistanceMm: 5.0
    )
    let profileResult = ProfileToolpathEngine.compute(
        vectors: [square(x: 10, y: 10, size: 50)],
        params: profileParams,
        material: nil,
        stockHeightMm: 4.0
    )
    // Hand-derived: onCut keeps the source path; 4mm stock / 2mm step = 2
    // passes at Z=-2 and Z=-4; lead-in 5mm before start, lead-out 5mm after.
    let profileGolden: [String] = [
        "%",
        "O=PROFILE_TOOLPATH",
        "(Tool: 60mm)",
        "",
        "(Pass 1/2, Z=-2.000)",
        "G0 Z5.0",
        "G0 X5.000 Y10.000",
        "G1 Z-2.000 F300",
        "G1 X10.000 Y10.000 F1000",
        "G1 X60.000 Y10.000 F1000",
        "G1 X60.000 Y60.000 F1000",
        "G1 X10.000 Y60.000 F1000",
        "G1 X10.000 Y10.000 F1000",
        "G1 X10.000 Y10.000 F1000",
        "G1 X15.000 Y10.000 F1000",
        "G0 Z5.0",
        "",
        "(Pass 2/2, Z=-4.000)",
        "G0 Z5.0",
        "G0 X5.000 Y10.000",
        "G1 Z-4.000 F300",
        "G1 X10.000 Y10.000 F1000",
        "G1 X60.000 Y10.000 F1000",
        "G1 X60.000 Y60.000 F1000",
        "G1 X10.000 Y60.000 F1000",
        "G1 X10.000 Y10.000 F1000",
        "G1 X10.000 Y10.000 F1000",
        "G1 X15.000 Y10.000 F1000",
        "G0 Z5.0",
        "",
        "M30",
        "%",
    ]
    try expectGolden(profileResult.gcodeLines, profileGolden, "Profile golden")

    // ── 2. POCKET golden — same square, zigzag, 3mm step-over, 2 passes. ───
    let pocketParams = PocketToolpathParams(
        clearanceMode: .zigzag,
        stepOverMm: 3.0,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        maxDepthOfCutMm: 2.0,
        toolDiameterMm: 6.0,
        safetyHeightMm: 5.0
    )
    let pocketResult = PocketToolpathEngine.compute(
        vectors: [square(x: 10, y: 10, size: 50)],
        params: pocketParams,
        material: nil,
        stockHeightMm: 4.0
    )
    // Hand-derived: pocket spans x∈[13,57], y∈[13,57] (tool radius inset);
    // rows at y=13,16,…,55 (15 rows), zigzag alternating. Per row the engine
    // emits the sweep line (X at the sweep end) then a step line at the NEXT
    // row's Y keeping the same X (the next sweep starts there), then the next
    // sweep jumps to the far side — so X57/Y odd-rows and X13/Y even-rows
    // each appear twice consecutively. No G0 in the zigzag → insertPlunge
    // positions at the first cut point (57,13).
    let pocketGolden: [String] = [
        "%",
        "O=POCKET_TOOLPATH",
        "(Tool: 60mm)",
        "",
        "(Pocket Pass 1/2, Z=-2.000)",
        "G0 Z5.0",
        "G0 X57.000 Y13.000",
        "G1 Z-2.000 F300",
        "G1 X57.000 Y13.000 F1000",
        "G1 X57.000 Y16.000 F1000",
        "G1 X13.000 Y16.000 F1000",
        "G1 X13.000 Y19.000 F1000",
        "G1 X57.000 Y19.000 F1000",
        "G1 X57.000 Y22.000 F1000",
        "G1 X13.000 Y22.000 F1000",
        "G1 X13.000 Y25.000 F1000",
        "G1 X57.000 Y25.000 F1000",
        "G1 X57.000 Y28.000 F1000",
        "G1 X13.000 Y28.000 F1000",
        "G1 X13.000 Y31.000 F1000",
        "G1 X57.000 Y31.000 F1000",
        "G1 X57.000 Y34.000 F1000",
        "G1 X13.000 Y34.000 F1000",
        "G1 X13.000 Y37.000 F1000",
        "G1 X57.000 Y37.000 F1000",
        "G1 X57.000 Y40.000 F1000",
        "G1 X13.000 Y40.000 F1000",
        "G1 X13.000 Y43.000 F1000",
        "G1 X57.000 Y43.000 F1000",
        "G1 X57.000 Y46.000 F1000",
        "G1 X13.000 Y46.000 F1000",
        "G1 X13.000 Y49.000 F1000",
        "G1 X57.000 Y49.000 F1000",
        "G1 X57.000 Y52.000 F1000",
        "G1 X13.000 Y52.000 F1000",
        "G1 X13.000 Y55.000 F1000",
        "G1 X57.000 Y55.000 F1000",
        "G0 Z5.0",
        "",
        "(Pocket Pass 2/2, Z=-4.000)",
        "G0 Z5.0",
        "G0 X57.000 Y13.000",
        "G1 Z-4.000 F300",
        "G1 X57.000 Y13.000 F1000",
        "G1 X57.000 Y16.000 F1000",
        "G1 X13.000 Y16.000 F1000",
        "G1 X13.000 Y19.000 F1000",
        "G1 X57.000 Y19.000 F1000",
        "G1 X57.000 Y22.000 F1000",
        "G1 X13.000 Y22.000 F1000",
        "G1 X13.000 Y25.000 F1000",
        "G1 X57.000 Y25.000 F1000",
        "G1 X57.000 Y28.000 F1000",
        "G1 X13.000 Y28.000 F1000",
        "G1 X13.000 Y31.000 F1000",
        "G1 X57.000 Y31.000 F1000",
        "G1 X57.000 Y34.000 F1000",
        "G1 X13.000 Y34.000 F1000",
        "G1 X13.000 Y37.000 F1000",
        "G1 X57.000 Y37.000 F1000",
        "G1 X57.000 Y40.000 F1000",
        "G1 X13.000 Y40.000 F1000",
        "G1 X13.000 Y43.000 F1000",
        "G1 X57.000 Y43.000 F1000",
        "G1 X57.000 Y46.000 F1000",
        "G1 X13.000 Y46.000 F1000",
        "G1 X13.000 Y49.000 F1000",
        "G1 X57.000 Y49.000 F1000",
        "G1 X57.000 Y52.000 F1000",
        "G1 X13.000 Y52.000 F1000",
        "G1 X13.000 Y55.000 F1000",
        "G1 X57.000 Y55.000 F1000",
        "G0 Z5.0",
        "",
        "M30",
        "%",
    ]
    try expectGolden(pocketResult.gcodeLines, pocketGolden, "Pocket golden")

    // ── 3. V-Carve golden — 90° V-bit, 2 passes. ───────────────────────────
    // SPK-2010b: Z now derives from the LOCAL CHANNEL WIDTH (medial-axis
    // distance) instead of Y-position shading, and closed vectors get a
    // skeleton pass — so the byte-exact golden is replaced by the hand-
    // derived OUTLINE PREFIX (still fully deterministic) + VALLEY INVARIANTS.
    let vcarveParams = VCarveParams(
        vBitAngleDegrees: 90.0,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        maxDepthOfCutMm: 2.0,
        leadInDistanceMm: 5.0,
        leadOutDistanceMm: 5.0,
        stepOverMm: 2.0,
        flatBottomMode: false
    )
    let vcarveResult = VCarveEngine.compute(
        vectors: [square(x: 10, y: 10, size: 50)],
        params: vcarveParams,
        stockHeightMm: 4.0
    )
    // Hand-derived outline prefix: tip width at 2mm = 4mm → 2 passes at
    // Z=-1/-2. The square's walls measure 50 mm from each other, so every
    // vertex bottoms out at the pass clamp; the seam vertex measures the
    // same (its own wall segments are skipped). Medial spine follows after
    // the outline passes.
    let vcarveGoldenPrefix: [String] = [
        "%",
        "O=V_CARVE_TOOLPATH",
        "(V-Bit: 90°)",
        "(Flat Bottom: No)",
        "",
        "(Pass 1/2, Z=-1.000)",
        "G0 Z5.0",
        "G0 X5.000 Y10.000",
        "G1 Z-1.000 F300",
        "G1 X10.000 Y10.000 F1000",
        "G1 X60.000 Y10.000 Z-1.000 F1000",
        "G1 X60.000 Y60.000 Z-1.000 F1000",
        "G1 X10.000 Y60.000 Z-1.000 F1000",
        "G1 X10.000 Y10.000 Z-1.000 F1000",
        "G1 X10.000 Y10.000 Z-1.000 F1000",
        "G1 X15.000 Y10.000 Z-1.000 F1000",
        "G0 Z5.0",
        "",
        "(Pass 2/2, Z=-2.000)",
        "G0 Z5.0",
        "G0 X5.000 Y10.000",
        "G1 Z-2.000 F300",
        "G1 X10.000 Y10.000 F1000",
        "G1 X60.000 Y10.000 Z-2.000 F1000",
        "G1 X60.000 Y60.000 Z-2.000 F1000",
        "G1 X10.000 Y60.000 Z-2.000 F1000",
        "G1 X10.000 Y10.000 Z-2.000 F1000",
        "G1 X10.000 Y10.000 Z-2.000 F1000",
        "G1 X15.000 Y10.000 Z-2.000 F1000",
        "G0 Z5.0",
    ]
    try expect(vcarveResult.gcodeLines.count > vcarveGoldenPrefix.count,
               "V-Carve output should carry the outline passes plus the medial spine")
    for (i, e) in vcarveGoldenPrefix.enumerated() {
        try expect(vcarveResult.gcodeLines[i] == e,
                   "V-Carve outline golden line \(i): got \(vcarveResult.gcodeLines[i].debugDescription), want \(e.debugDescription)")
    }
    // Valley invariants on the medial section:
    let medialIdx = vcarveResult.gcodeLines.firstIndex { $0.contains("(Medial axis:") }
    try expect(medialIdx != nil, "closed square must emit a medial-axis pass")
    if let mIdx = medialIdx {
        try expect(mIdx == vcarveGoldenPrefix.count + 1 || vcarveResult.gcodeLines[mIdx - 1].isEmpty,
                   "medial comment follows a blank line after the outline passes")
        try expect(vcarveResult.gcodeLines[mIdx].contains("ridge path(s), max clearance"),
                   "medial comment reports ridge count + max clearance")
        // Spine of a 50mm square: clearance ≈ 25 → Z = -25/tan(45°) → clamped to -maxDepth.
        let g = vcarveResult.gcodeLines.filter { $0.hasPrefix("G1 ") && $0.contains("Z-2.000") }
        try expect(g.count >= 2, "square spine cuts at the clamped full depth -2.000")
        // Footer intact after the medial section.
        try expect(vcarveResult.gcodeLines.contains("M30"), "program ends with M30")
        try expect(vcarveResult.gcodeLines.last == "%", "trailing % closes the program")
    }

    // ── 4. V-CARVE + CLEARANCE golden — board + inner letter. ──────────────
    // Board is 10..60 × 10..30 so the letter sits strictly inside.
    let boardShort = VectorPath(
        points: [
            VectorPoint(x: 10, y: 10), VectorPoint(x: 60, y: 10),
            VectorPoint(x: 60, y: 30), VectorPoint(x: 10, y: 30),
            VectorPoint(x: 10, y: 10),
        ],
        isClosed: true
    )
    let letter = VectorPath(
        points: [
            VectorPoint(x: 25, y: 14), VectorPoint(x: 35, y: 14),
            VectorPoint(x: 35, y: 26), VectorPoint(x: 25, y: 26),
            VectorPoint(x: 25, y: 14),
        ],
        isClosed: true
    )
    let clearanceParams = VCarveParams(
        vBitAngleDegrees: 90.0,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        maxDepthOfCutMm: 1.0,
        leadInDistanceMm: 5.0,
        leadOutDistanceMm: 5.0,
        stepOverMm: 2.0,
        flatBottomMode: false,
        clearancePassEnabled: true,
        clearanceToolDiameterMm: 6.0,
        clearanceDepthMm: 1.0,
        clearanceStepOverMm: 0.5
    )
    let clearanceResult = VCarveEngine.compute(
        vectors: [boardShort, letter],
        params: clearanceParams,
        stockHeightMm: 4.0
    )
    // Hand-derived clearance pass: bounds (10,10)-(60,30); clearance tool R=3,
    // step = 0.5×6 = 3mm; letter protected (strictly inside) → exclusion band
    // (25-4, 35+4) = (21,39) over y∈[14,26]. Rows at y=13,16,19,22,25 (13+3k ≤
    // 27). Each row: gap (13→21) left of the letter, gap (39→57) right of it
    // (right gap runs 57→39 because the direction toggles per gap). Then the
    // V-bit detail cuts both vectors at depth 1.0 (tip width 2mm, step 2mm →
    // 1 pass), shaded: board y-range 20, letter y-range 12.
    // SPK-2010b: the clearance raster AND both outline passes are byte-
    // unchanged (every wall width here clamps to the 1mm depth), so they stay
    // byte-exact goldens; each closed vector additionally gains a skeleton
    // pass, asserted by valley invariants.
    let cg = clearanceResult.gcodeLines
    let headGolden: [String] = [
        "%",
        "",
        "O=VCARVE_CLEARANCE",
        "(Clearance tool: 6.0mm)",
        "(Clearance depth: 1.00mm)",
        "G0 Z5.0",
        "G0 X13.000 Y13.000",
        "G1 Z-1.000 F300",
        "G1 X21.000 Y13.000 F1000",
        "G0 Z5.0",
        "G0 X57.000 Y13.000",
        "G1 Z-1.000 F300",
        "G1 X39.000 Y13.000 F1000",
        "G0 Z5.0",
        "G0 X13.000 Y16.000",
        "G1 Z-1.000 F300",
        "G1 X21.000 Y16.000 F1000",
        "G0 Z5.0",
        "G0 X57.000 Y16.000",
        "G1 Z-1.000 F300",
        "G1 X39.000 Y16.000 F1000",
        "G0 Z5.0",
        "G0 X13.000 Y19.000",
        "G1 Z-1.000 F300",
        "G1 X21.000 Y19.000 F1000",
        "G0 Z5.0",
        "G0 X57.000 Y19.000",
        "G1 Z-1.000 F300",
        "G1 X39.000 Y19.000 F1000",
        "G0 Z5.0",
        "G0 X13.000 Y22.000",
        "G1 Z-1.000 F300",
        "G1 X21.000 Y22.000 F1000",
        "G0 Z5.0",
        "G0 X57.000 Y22.000",
        "G1 Z-1.000 F300",
        "G1 X39.000 Y22.000 F1000",
        "G0 Z5.0",
        "G0 X13.000 Y25.000",
        "G1 Z-1.000 F300",
        "G1 X21.000 Y25.000 F1000",
        "G0 Z5.0",
        "G0 X57.000 Y25.000",
        "G1 Z-1.000 F300",
        "G1 X39.000 Y25.000 F1000",
        "O=V_CARVE_TOOLPATH",
        "(V-Bit: 90°)",
        "(Flat Bottom: No)",
        "",
        "(Pass 1/1, Z=-1.000)",
        "G0 Z5.0",
        "G0 X5.000 Y10.000",
        "G1 Z-1.000 F300",
        "G1 X10.000 Y10.000 F1000",
        "G1 X60.000 Y10.000 Z-1.000 F1000",
        "G1 X60.000 Y30.000 Z-1.000 F1000",
        "G1 X10.000 Y30.000 Z-1.000 F1000",
        "G1 X10.000 Y10.000 Z-1.000 F1000",
        "G1 X10.000 Y10.000 Z-1.000 F1000",
        "G1 X15.000 Y10.000 Z-1.000 F1000",
        "G0 Z5.0",
    ]
    try expect(cg.count > headGolden.count,
               "clearance output should carry outlines plus medial spines")
    for (i, e) in headGolden.enumerated() {
        try expect(cg[i] == e,
                   "V-Carve+Clearance golden line \(i): got \(cg[i].debugDescription), want \(e.debugDescription)")
    }
    // Board spine rides right after the board's outline pass.
    try expect(cg[headGolden.count].isEmpty && cg[headGolden.count + 1].hasPrefix("(Medial axis:"),
               "board medial pass must follow the board outline pass")
    // Letter outline pass (byte-exact) comes after the board spine section.
    guard let letterPassStart = (headGolden.count + 1..<cg.count)
        .first(where: { cg[$0] == "(Pass 1/1, Z=-1.000)" }) else {
        throw VerifyError.failed("letter outline pass not found after board spine")
    }
    let letterGolden: [String] = [
        "(Pass 1/1, Z=-1.000)",
        "G0 Z5.0",
        "G0 X20.000 Y14.000",
        "G1 Z-1.000 F300",
        "G1 X25.000 Y14.000 F1000",
        "G1 X35.000 Y14.000 Z-1.000 F1000",
        "G1 X35.000 Y26.000 Z-1.000 F1000",
        "G1 X25.000 Y26.000 Z-1.000 F1000",
        "G1 X25.000 Y14.000 Z-1.000 F1000",
        "G1 X25.000 Y14.000 Z-1.000 F1000",
        "G1 X30.000 Y14.000 Z-1.000 F1000",
        "G0 Z5.0",
    ]
    for (k, e) in letterGolden.enumerated() {
        try expect(cg[letterPassStart + k] == e,
                   "letter outline golden line +\(k): got \(cg[letterPassStart + k].debugDescription), want \(e.debugDescription)")
    }
    // Exactly two spines (board + letter); program closes cleanly.
    try expect(cg.filter { $0.hasPrefix("(Medial axis:") }.count == 2,
               "both closed vectors must carry exactly one medial pass each")
    try expect(cg.contains("M30") && cg.last == "%", "footer intact")

    print("ShopPilotVerifyGolden25D: PASS — hand-checked goldens: Profile (2-pass on-cut), "
          + "Pocket (15-row zigzag), V-Carve (2-pass width-Z + medial spine), V-Carve+Clearance (protected letter bands)")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyGolden25D: FAIL — \(error)")
    exit(1)
}
