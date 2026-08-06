import Foundation
import ShopPilotCore

/// SPK-0900 + SPK-0802 lean-slice verify (CLT machine, no XCTest).
/// Proves the four specialty engines:
///   1. PRISM: a 20×20 square at 5mm spacing / 90° bit → 4 grooves at
///      y = 2.5/7.5/12.5/17.5, each at Z = −(5/(2·tan45)) = −2.500. A narrow
///      4mm shape cuts shallower (depth = width/2 = 2.0).
///   2. FLUTING: open path, cut 4mm in 2mm passes → Z −2.000 then −4.000.
///   3. CHAMFER: 3mm width / 90° bit → Z −3.000 along the edges.
///   4. INLAY POCKET (female): V-carve flat-bottom at 6mm — V_CARVE marker +
///      a −6.000 plunge. INLAY PLUG (male): profile on-cut at 6mm —
///      PROFILE marker + −6.000 moves.
///   5. PERSIST: all four params round-trip Codable; legacy JSON (no keys)
///      decodes to defaults.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func closedSquare(_ side: Double) -> VectorPath {
    VectorPath(
        id: UUID(),
        points: [pt(0, 0), pt(side, 0), pt(side, side), pt(0, side), pt(0, 0)],
        isClosed: true
    )
}

func countG1X(_ gcode: [String]) -> Int {
    gcode.filter { $0.hasPrefix("G1 X") }.count
}

func main() throws {
    // ── 1. Prism ───────────────────────────────────────────────────────────
    let square = closedSquare(20)
    let prism = PrismToolpathEngine.compute(
        paths: [square],
        params: PrismToolpathParams(spacingMm: 5, vBitAngleDegrees: 90),
        stockHeightMm: 25.0
    )
    try expect(prism.gcodeLines.contains("O=PRISM_TOOLPATH"), "prism header marker")
    try expect(prism.featureCount == 4, "20mm square at 5mm spacing → 4 grooves (got \(prism.featureCount))")
    try expect(countG1X(prism.gcodeLines) == 4, "4 cut moves (one per groove)")
    let depthLines = prism.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(depthLines.allSatisfy { $0.contains("-2.500") },
               "all grooves at Z-2.500 (spacing/2 for 90° bit) got \(depthLines)")
    // Groove y positions present in comments.
    let comments = prism.gcodeLines.filter { $0.hasPrefix("(Groove") }.joined()
    for y in ["2.500", "7.500", "12.500", "17.500"] {
        try expect(comments.contains("y \(y)"), "groove row at y=\(y)")
    }

    // Narrow shape: 4mm wide → depth capped by run width.
    let narrow = VectorPath(
        id: UUID(),
        points: [pt(0, 0), pt(4, 0), pt(4, 20), pt(0, 20), pt(0, 0)],
        isClosed: true
    )
    let prismNarrow = PrismToolpathEngine.compute(
        paths: [narrow],
        params: PrismToolpathParams(spacingMm: 5, vBitAngleDegrees: 90),
        stockHeightMm: 25.0
    )
    let narrowDepths = prismNarrow.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(narrowDepths.allSatisfy { $0.contains("-2.000") },
               "4mm-wide rows cut at Z-2.000 (width/2) got \(narrowDepths)")

    // ── 2. Fluting ─────────────────────────────────────────────────────────
    let flutePath = VectorPath(id: UUID(), points: [pt(0, 0), pt(10, 0)], isClosed: false)
    let fluting = FlutingToolpathEngine.compute(
        paths: [flutePath],
        params: FlutingToolpathParams(cutDepthMm: 4, passDepthMm: 2),
        stockHeightMm: 25.0
    )
    try expect(fluting.gcodeLines.contains("O=FLUTING_TOOLPATH"), "fluting header marker")
    let fluteZs = fluting.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(fluteZs.count == 2, "2 step-down passes (got \(fluteZs))")
    try expect(fluteZs[0].contains("-2.000") && fluteZs[1].contains("-4.000"),
               "pass depths −2 then −4 got \(fluteZs)")
    try expect(countG1X(fluting.gcodeLines) == 2, "one cut move per pass (2 passes)")

    // ── 3. Chamfer ─────────────────────────────────────────────────────────
    let chamfer = ChamferToolpathEngine.compute(
        paths: [flutePath],
        params: ChamferToolpathParams(chamferWidthMm: 3, vBitAngleDegrees: 90),
        stockHeightMm: 25.0
    )
    try expect(chamfer.gcodeLines.contains("O=CHAMFER_TOOLPATH"), "chamfer header marker")
    let chamferZs = chamfer.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(chamferZs.allSatisfy { $0.contains("-3.000") },
               "chamfer at Z-3.000 (width/tan45) got \(chamferZs)")
    try expect(countG1X(chamfer.gcodeLines) == 1, "one chamfer cut along the edge")

    // ── 4. Inlay pocket + plug ─────────────────────────────────────────────
    var pocketParams = InlayToolpathParams()
    pocketParams.variant = .pocket
    let pocket = InlayToolpathEngine.computePocket(paths: [square], params: pocketParams, stockHeightMm: 25.0)
    try expect(pocket.gcodeLines.contains("O=V_CARVE_TOOLPATH"), "inlay pocket reuses the V-carve engine")
    try expect(pocket.gcodeLines.contains { $0.hasPrefix("G1 Z") && $0.contains("-6.000") },
               "pocket floor at −6.000 (flat depth)")

    var plugParams = InlayToolpathParams()
    plugParams.variant = .plug
    let plug = InlayToolpathEngine.computePlug(paths: [square], params: plugParams, stockHeightMm: 25.0)
    try expect(plug.gcodeLines.contains("O=PROFILE_TOOLPATH"), "inlay plug reuses the profile engine")
    try expect(plug.gcodeLines.contains { $0.hasPrefix("G1 Z") && $0.contains("-6.000") },
               "plug cut at −6.000 (inlay depth)")

    // ── 5. Persist: Codable round-trip + legacy decode ─────────────────────
    let prismData = try JSONEncoder().encode(PrismToolpathParams(spacingMm: 8, vBitAngleDegrees: 45))
    let prismBack = try JSONDecoder().decode(PrismToolpathParams.self, from: prismData)
    try expect(prismBack.spacingMm == 8 && prismBack.vBitAngleDegrees == 45, "prism params round-trip")

    let legacyPrism = try JSONDecoder().decode(PrismToolpathParams.self, from: Data("{}".utf8))
    try expect(legacyPrism.spacingMm == 6.0 && legacyPrism.vBitAngleDegrees == 90.0,
               "legacy prism JSON decodes to defaults")

    let legacyInlay = try JSONDecoder().decode(InlayToolpathParams.self, from: Data("{}".utf8))
    try expect(legacyInlay.variant == .pocket && legacyInlay.inlayDepthMm == 6.0,
               "legacy inlay JSON decodes to pocket @ 6mm")

    let fluteData = try JSONEncoder().encode(FlutingToolpathParams(cutDepthMm: 12))
    let fluteBack = try JSONDecoder().decode(FlutingToolpathParams.self, from: fluteData)
    try expect(fluteBack.cutDepthMm == 12, "fluting params round-trip")

    let chamferData = try JSONEncoder().encode(ChamferToolpathParams(chamferWidthMm: 5))
    let chamferBack = try JSONDecoder().decode(ChamferToolpathParams.self, from: chamferData)
    try expect(chamferBack.chamferWidthMm == 5, "chamfer params round-trip")

    print("ShopPilotVerifySpecialty: PASS - prism grooves+depths, fluting passes, chamfer bevel, inlay pocket/plug reuse, params round-trip + legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerifySpecialty: FAIL - \(error)")
    exit(1)
}
