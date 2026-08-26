import Foundation
import ShopPilotCore

// SPK-2120b — Inlay rim order: V-walls then floor clearance.
// AC: Toggle, default V-first ON for inlay; ordinary V-carve keeps
//     clearance-before-V; first cut moves are V then endmill floor.
//     InlayToolpathEngine.computePocket wires vFirst + clearancePassEnabled.
//     No G-code after the first M30 except a trailing %.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

/// Ordered O= sections that actually contain CUT (G1 XY) moves. Marker-only
/// assertions let SPK-2120b ship a floor section with zero cut moves; attribute
/// every move to its owning section instead.
func cuttingSections(_ g: [String]) -> [String] {
    var section = "PREAMBLE", out: [String] = []
    for l in g {
        if l.hasPrefix("O=") { section = String(l.dropFirst(2)); continue }
        guard l.hasPrefix("G1"), l.contains("X") || l.contains("Y") else { continue }
        if out.last != section { out.append(section) }
    }
    return out
}

/// Assert that after the first M30, the only remaining line is a trailing %.
func assertNoGcodeAfterFirstM30(_ lines: [String], _ label: String) {
    guard let m30 = lines.firstIndex(of: "M30") else {
        expect(false, "\(label): no M30 found")
        return
    }
    let nonEmpty = lines[(m30 + 1)...].filter { !$0.isEmpty }
    expect(nonEmpty == ["%"], "\(label): no G-code after first M30 except trailing %")
    expect(lines.filter { $0 == "M30" }.count == 1, "\(label): exactly one M30")
}

func main() throws {
    let rect = VectorPath(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 20, y: 0),
        VectorPoint(x: 20, y: 10), VectorPoint(x: 0, y: 10),
    ], isClosed: true)

    // ── 1. Params: default vFirst = false (ordinary V-carve). ──────────────
    let p = VCarveParams()
    try expect(p.vFirst == false, "init default vFirst = false (clearance-before-V)")
    let roundtrip = try JSONDecoder().decode(VCarveParams.self, from: try JSONEncoder().encode(p))
    try expect(roundtrip.vFirst == false, "round-trip keeps vFirst = false")

    // ── 2. Engine: vFirst OFF → clearance before V-bit. ────────────────────
    var ordinary = VCarveParams()
    ordinary.clearancePassEnabled = true
    ordinary.vFirst = false
    let ordinaryRes = VCarveEngine.compute(vectors: [rect], params: ordinary)
    if let clearIdx = ordinaryRes.gcodeLines.firstIndex(where: { $0.contains("VCARVE_CLEARANCE") }),
       let vbitIdx = ordinaryRes.gcodeLines.firstIndex(where: { $0 == "O=V_CARVE_TOOLPATH" }) {
        try expect(clearIdx < vbitIdx, "ordinary V-carve: clearance before V-bit")
    } else {
        try expect(ordinaryRes.gcodeLines.contains { $0 == "O=V_CARVE_TOOLPATH" },
                   "ordinary V-carve: V-bit pass present")
    }
    try expect(!ordinaryRes.gcodeLines.contains { $0.contains("V-walls first") },
               "ordinary V-carve: no inlay marker")
    assertNoGcodeAfterFirstM30(ordinaryRes.gcodeLines, "ordinary V-carve")

    // ── 3. Engine: vFirst ON without inlayInteriorFloor → around-letter. ──
    // Valley-form toggle must NOT pocket out glyph interiors.
    var inlay = VCarveParams()
    inlay.clearancePassEnabled = true
    inlay.vFirst = true
    let inlayRes = VCarveEngine.compute(vectors: [rect], params: inlay)
    try expect(inlayRes.gcodeLines.contains { $0.contains("V-walls first") },
               "ordinary vFirst: V-walls-first marker present")
    try expect(inlayRes.gcodeLines.contains { $0.contains("around-letter clearance") },
               "ordinary vFirst: around-letter follow-up (not interior floor)")
    try expect(!inlayRes.gcodeLines.contains { $0.contains("floor clearance after V-walls") },
               "ordinary vFirst: no inlay interior-floor marker")
    assertNoGcodeAfterFirstM30(inlayRes.gcodeLines, "ordinary vFirst V-carve")

    // ── 4. No clearance pass → vFirst has no effect. ──────────────────────
    var noClear = VCarveParams()
    noClear.clearancePassEnabled = false
    noClear.vFirst = true
    let noClearRes = VCarveEngine.compute(vectors: [rect], params: noClear)
    try expect(!noClearRes.gcodeLines.contains { $0.contains("V-walls first") },
               "no clearance pass: no inlay marker regardless of vFirst")
    assertNoGcodeAfterFirstM30(noClearRes.gcodeLines, "no-clearance V-carve")

    // ── 5. InlayToolpathEngine.computePocket wires vFirst + interior floor. ─
    let pocketParams = InlayToolpathParams(
        variant: .pocket, inlayDepthMm: 3.0, vBitAngleDegrees: 60, toolDiameterMm: 3.0)
    try expect(pocketParams.vFirst == true, "inlay params default vFirst = true")
    let pocketRes = InlayToolpathEngine.computePocket(paths: [rect], params: pocketParams, stockHeightMm: 25.0)
    // CUT MOVES, not markers: V-walls first, then a floor that actually cuts.
    let pocketCuts = cuttingSections(pocketRes.gcodeLines)
    try expect(pocketCuts == ["V_CARVE_TOOLPATH", "VCARVE_CLEARANCE"],
               "inlay pocket cut order: V-walls then endmill floor — got \(pocketCuts)")
    try expect(pocketRes.gcodeLines.contains { $0.contains("V-walls first") },
               "inlay pocket: V-walls-first marker present")
    try expect(pocketRes.gcodeLines.contains { $0.contains("floor clearance after V-walls") },
               "inlay pocket: floor clearance marker present")
    try expect(pocketRes.gcodeLines.contains { $0.contains("Clearance tool: 3.0mm") },
               "inlay pocket: floor mill Ø copied from InlayToolpathParams.toolDiameterMm")
    assertNoGcodeAfterFirstM30(pocketRes.gcodeLines, "inlay pocket")

    // ── 6. Inlay pocket with vFirst OFF → ordinary (no interior floor). ──
    var pocketOrdinary = InlayToolpathParams(variant: .pocket, inlayDepthMm: 3.0, vBitAngleDegrees: 60)
    pocketOrdinary.vFirst = false
    let pocketOrdRes = InlayToolpathEngine.computePocket(paths: [rect], params: pocketOrdinary, stockHeightMm: 25.0)
    try expect(cuttingSections(pocketOrdRes.gcodeLines) == ["V_CARVE_TOOLPATH"],
               "inlay pocket (vFirst off): ordinary — no interior floor fill")
    try expect(!pocketOrdRes.gcodeLines.contains { $0.contains("V-walls first") },
               "inlay pocket (vFirst off): no inlay marker")
    assertNoGcodeAfterFirstM30(pocketOrdRes.gcodeLines, "inlay pocket (vFirst off)")

    // ── 7. Ordinary sign board (letter inside) still clears BEFORE the V. ─
    // Board must be wide enough to leave clearable gaps beside the letter's
    // tool-radius + 1 mm protection band, else the pass has nothing to cut.
    let boardOutline = VectorPath(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 30, y: 0),
        VectorPoint(x: 30, y: 18), VectorPoint(x: 0, y: 18),
    ], isClosed: true)
    let letter = VectorPath(points: [
        VectorPoint(x: 12, y: 7), VectorPoint(x: 18, y: 7),
        VectorPoint(x: 18, y: 11), VectorPoint(x: 12, y: 11),
    ], isClosed: true)
    var board = VCarveParams()
    board.clearancePassEnabled = true
    let boardRes = VCarveEngine.compute(vectors: [boardOutline, letter], params: board)
    try expect(cuttingSections(boardRes.gcodeLines) == ["VCARVE_CLEARANCE", "V_CARVE_TOOLPATH"],
               "sign board: clearance cuts before V-bit (ordinary path unchanged)")
    assertNoGcodeAfterFirstM30(boardRes.gcodeLines, "sign board")

    // ── 8. Valley-form vFirst on a sign must NOT fill letter interiors. ───
    let bigBoard = VectorPath(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 80, y: 0),
        VectorPoint(x: 80, y: 50), VectorPoint(x: 0, y: 50),
    ], isClosed: true)
    let bigLetter = VectorPath(points: [
        VectorPoint(x: 25, y: 15), VectorPoint(x: 55, y: 15),
        VectorPoint(x: 55, y: 35), VectorPoint(x: 25, y: 35),
    ], isClosed: true)
    var signFirst = VCarveParams()
    signFirst.clearancePassEnabled = true
    signFirst.vFirst = true
    let signFirstRes = VCarveEngine.compute(vectors: [bigBoard, bigLetter], params: signFirst)
    try expect(cuttingSections(signFirstRes.gcodeLines) == ["V_CARVE_TOOLPATH", "VCARVE_CLEARANCE"],
               "sign + vFirst: V then around-letter clearance — got \(cuttingSections(signFirstRes.gcodeLines))")
    try expect(signFirstRes.gcodeLines.contains { $0.contains("around-letter clearance") },
               "sign + vFirst: around-letter marker")
    try expect(!signFirstRes.gcodeLines.contains { $0.contains("floor clearance after V-walls") },
               "sign + vFirst: must not use inlay interior floor")
    assertNoGcodeAfterFirstM30(signFirstRes.gcodeLines, "sign + vFirst")

    print(failures == 0
          ? "ShopPilotVerify2120b: PASS"
          : "ShopPilotVerify2120b: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
