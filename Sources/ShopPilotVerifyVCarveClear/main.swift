import Foundation
import ShopPilotCore

/// SPK-VCarveClear verify (CLT machine, no XCTest).
/// Proves the V-Carve clearance-tool pass:
///   1. DEFAULT OFF: with the default params the output has NO clearance
///      marker — existing V-carve behavior is unchanged.
///   2. ORDER: when enabled, O=VCARVE_CLEARANCE appears BEFORE
///      O=V_CARVE_TOOLPATH (clearance runs first, V-bit detail after).
///   3. GEOMETRY: clearance raster clears the WIDE open bands but skips a
///      tool-radius + margin band around every vector — an inner glyph's
///      X-range has no clearance cut at overlapping rows, while the open
///      bands on both sides ARE cut, and full-width rows exist below/above
///      the glyph.
///   4. V-BIT INTACT: the V-carve block (marker + cut moves) still follows.
///   5. PERSIST: VCarveParams round-trips the clearance fields; legacy JSON
///      (pre-clearance keys only) decodes with the pass disabled.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y), VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size), VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

/// (x, y) of every G1/G0 motion line in `lines`.
func motionPoints(_ lines: [String]) -> [(x: Double, y: Double)] {
    var pts: [(x: Double, y: Double)] = []
    for line in lines {
        guard line.hasPrefix("G1") || line.hasPrefix("G0") else { continue }
        var x: Double?; var y: Double?
        for comp in line.split(separator: " ") {
            if comp.hasPrefix("X") { x = Double(comp.dropFirst()) }
            if comp.hasPrefix("Y") { y = Double(comp.dropFirst()) }
        }
        if let x = x, let y = y { pts.append((x, y)) }
    }
    return pts
}

func main() throws {
    // Outer sign board + inner "letter" glyph.
    let outer = makeClosedRect(x: 10, y: 10, size: 80)
    let glyph = makeClosedRect(x: 40, y: 40, size: 20)

    // ── 1. Default off: no clearance marker, V-carve unchanged. ─────────────
    let plain = VCarveEngine.compute(vectors: [outer, glyph], params: VCarveParams(), stockHeightMm: 25.0)
    try expect(plain.gcodeLines.contains("O=V_CARVE_TOOLPATH"), "default V-carve keeps its marker")
    try expect(!plain.gcodeLines.contains("O=VCARVE_CLEARANCE"), "default params emit NO clearance pass")

    // ── 2+3+4. Clearance on: order, geometry, V-bit intact. ────────────────
    var params = VCarveParams()
    params.clearancePassEnabled = true
    params.clearanceToolDiameterMm = 6.0
    params.clearanceDepthMm = 1.0
    params.clearanceStepOverMm = 0.4

    let result = VCarveEngine.compute(vectors: [outer, glyph], params: params, stockHeightMm: 25.0)
    let lines = result.gcodeLines

    guard let clearIdx = lines.firstIndex(of: "O=VCARVE_CLEARANCE"),
          let vcarveIdx = lines.firstIndex(of: "O=V_CARVE_TOOLPATH") else {
        throw VerifyError.failed("clearance pass must emit both markers")
    }
    try expect(clearIdx < vcarveIdx, "clearance pass runs BEFORE the V-bit pass")

    // Clearance section only.
    let clearSection = Array(lines[clearIdx..<vcarveIdx])
    let clearMoves = motionPoints(clearSection)
    try expect(clearMoves.count >= 4, "clearance block has real raster moves (\(clearMoves.count))")
    try expect(clearSection.contains { $0.hasPrefix("(Clearance tool:") }, "clearance block names its tool")

    // V-bit section still intact after.
    let vcarveSection = Array(lines[vcarveIdx...])
    try expect(vcarveSection.contains { $0.hasPrefix("G1") }, "V-bit cut moves follow the clearance pass")

    // Glyph band: tool radius 3 + 1mm margin → exclusion X-band (36, 64).
    // Clearance rows overlapping the glyph Y-range [37, 63]: no cut endpoint
    // inside the glyph's own X-range (40, 60); open bands on both sides cut.
    let overlappingRows = clearMoves.filter { $0.y >= 37 && $0.y <= 63 }
    try expect(!overlappingRows.isEmpty, "clearance rows overlap the glyph band")
    try expect(!overlappingRows.contains { $0.x > 40 && $0.x < 60 },
               "no clearance cut inside the glyph's X-range (stroke survives)")
    try expect(overlappingRows.contains { $0.x < 40 }, "open band LEFT of the glyph is cleared")
    try expect(overlappingRows.contains { $0.x > 60 }, "open band RIGHT of the glyph is cleared")

    // Full-width rows below the glyph (Y < 37): the whole interior is open.
    let fullRows = clearMoves.filter { $0.y < 37 }
    try expect(fullRows.contains { $0.x > 80 }, "full-width clearance row reaches the far side")

    // ── 3b. Letters-only (no board): clearance cuts BETWEEN shapes, never
    // inside one (protectAll path). Two 30mm rects at x 10 and 50 on a 80mm
    // union bbox → the gap band (~44-46mm) is cleared; rect interiors are not.
    let letterA = makeClosedRect(x: 10, y: 10, size: 30)
    let letterB = makeClosedRect(x: 50, y: 10, size: 30)
    let lettersOnly = VCarveEngine.compute(
        vectors: [letterA, letterB],
        params: params,
        stockHeightMm: 25.0
    )
    let loLines = lettersOnly.gcodeLines
    guard let loClear = loLines.firstIndex(of: "O=VCARVE_CLEARANCE"),
          let loVcarve = loLines.firstIndex(of: "O=V_CARVE_TOOLPATH") else {
        throw VerifyError.failed("letters-only clearance must emit both markers")
    }
    let loMoves = motionPoints(Array(loLines[loClear..<loVcarve]))
    try expect(loMoves.contains { $0.x > 43 && $0.x < 47 && $0.y > 12 && $0.y < 38 },
               "gap between the two letters is cleared")
    try expect(!loMoves.contains { $0.x > 12 && $0.x < 38 && $0.y > 12 && $0.y < 38 },
               "no clearance cut inside letter A's interior")
    try expect(!loMoves.contains { $0.x > 52 && $0.x < 78 && $0.y > 12 && $0.y < 38 },
               "no clearance cut inside letter B's interior")

    // ── 5. Persist: round-trip + legacy decode. ─────────────────────────────
    let data = try JSONEncoder().encode(params)
    let decoded = try JSONDecoder().decode(VCarveParams.self, from: data)
    try expect(decoded.clearancePassEnabled && decoded.clearanceToolDiameterMm == 6.0
               && decoded.clearanceDepthMm == 1.0 && abs(decoded.clearanceStepOverMm - 0.4) < 1e-9,
               "clearance fields round-trip through Codable")

    let legacyJSON = """
    {"vBitAngleDegrees": 90, "maxDepthOfCutMm": 2.0, "feedRateMmPerMin": 1000}
    """
    let legacy = try JSONDecoder().decode(VCarveParams.self, from: Data(legacyJSON.utf8))
    try expect(!legacy.clearancePassEnabled, "legacy JSON decodes with clearance disabled")
    try expect(legacy.clearanceToolDiameterMm == 6.0, "legacy JSON gets the clearance tool default")

    print("ShopPilotVerifyVCarveClear: PASS — default off, clearance-first order, glyph-band skip, open-band clear, V-bit intact, persist+legacy")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyVCarveClear: FAIL — \(error)")
    exit(1)
}
