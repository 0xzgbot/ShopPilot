import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-SHAKEd verify (CLT): import → persist → export round-trip matrix.
///
/// Proves each format family end-to-end on the committed fixtures:
///   1. SVG → shapes → .shoppilot: parse `fixtures/import/happy_compose.svg`,
///      convert to Core paths, save a Job package, reload, assert geometry
///      survives.
///   2. DXF → shapes: parse `fixtures/import/happy_square.dxf` (closed square
///      LWPOLYLINE + LINE + CIRCLE), assert exact geometry.
///   3. STL → heightfield: `fixtures/import/happy_box.stl` rasterizes to a
///      10×10 grid at the 10mm box top.
///   4. .shoppilot payload save/open: the SPK-SHAKEb fixture packages
///      (`Calibration.shoppilot`, `Sign.shoppilot`) load, keep their layers,
///      vectors, and toolpaths (Profile marker / V-Carve marker), and their
///      G-code posts through GRBLPostProcessor with move parity.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) < tol }

func fixture(_ rel: String) throws -> URL {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(rel)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw VerifyError.failed("fixture missing: \(rel)")
    }
    return url
}

func main() throws {
    var total = 0
    func ok(_ name: String) { total += 1; print("  ok   \(name)") }

    // ── 1. SVG → shapes → .shoppilot package round-trip. ────────────────────
    print("== SVG → shapes → .shoppilot ==")
    let svgContent = try String(contentsOf: fixture("fixtures/import/happy_compose.svg"), encoding: .utf8)
    let svg = SVGImporter.parse(svgContent)
    try expect(svg.success, "happy_compose.svg parses")
    try expect(svg.shapes.count == 4, "4 shapes (rect/circle/closed/open), got \(svg.shapes.count)")
    try expect(svg.documentSize?.width == 100 && svg.documentSize?.height == 80,
               "document size from width/height attrs")
    ok("SVG parses: 4 shapes, 100×80 doc")

    let layerID = UUID()
    let paths = GeometryBridge.toCorePaths(
        svg.shapes,
        layerIDs: Array(repeating: layerID, count: svg.shapes.count)
    )
    try expect(paths.count == 4, "shapes → 4 Core paths")
    let layer = Layer(id: layerID, name: "Imported", vectors: paths)
    let sheet = Sheet(name: "Sheet 1", width: 100, depth: 80, height: 18, layers: [layer])
    let job = Job(name: "SVG Round-Trip", sheets: [sheet])

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk-shaked-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let pkgURL = tmpDir.appendingPathComponent("svg_rt.shoppilot")
    try DocumentSaver().save(job, to: pkgURL)
    let loaded = try DocumentLoader().loadPayload(from: pkgURL)
    try expect(loaded.job.name == "SVG Round-Trip", "package reloads with the same job name")
    guard let loadedLayer = loaded.job.sheets.first?.layers.first else {
        throw VerifyError.failed("package reload keeps the layer")
    }
    try expect(loadedLayer.vectors.count == 4, "4 vectors survive save/open (got \(loadedLayer.vectors.count))")
    try expect(loadedLayer.vectors.allSatisfy { !$0.points.isEmpty },
               "every vector keeps its point data")
    let allPts = loadedLayer.vectors.flatMap { $0.points }
    let minX = allPts.map(\.x).min() ?? -1
    let maxX = allPts.map(\.x).max() ?? -1
    let minY = allPts.map(\.y).min() ?? -1
    let maxY = allPts.map(\.y).max() ?? -1
    try expect(near(minX, 5) && near(maxX, 95) && near(minY, 5) && near(maxY, 75),
               "design bbox survives save/open (rect 5..95 × 5..75, got \(minX)..\(maxX) × \(minY)..\(maxY))")
    ok("SVG → .shoppilot save/open round-trip: 4 vectors, bbox intact")

    // ── 2. DXF → shapes. ─────────────────────────────────────────────────────
    print("== DXF → shapes ==")
    let dxfContent = try String(contentsOf: fixture("fixtures/import/happy_square.dxf"), encoding: .utf8)
    let dxf = DXFParser.parse(dxfContent)
    try expect(dxf.success, "happy_square.dxf parses")
    try expect(dxf.shapes.count == 3, "3 entities (square/line/circle), got \(dxf.shapes.count)")
    guard case .freehand(let sq) = dxf.shapes[0] else {
        throw VerifyError.failed("shape 0 is the closed square polyline")
    }
    try expect(sq.count == 5 && sq.first == sq.last, "square polyline closed, 5 points")
    try expect(near(sq[1].x, 40) && near(sq[1].y, 10) && near(sq[2].x, 40) && near(sq[2].y, 40),
               "square geometry 10→40")
    guard case .line(let s, let e) = dxf.shapes[1] else {
        throw VerifyError.failed("shape 1 is the LINE")
    }
    try expect(near(s.x, 5) && near(s.y, 5) && near(e.x, 5) && near(e.y, 55), "LINE geometry")
    guard case .circle(let c, let r) = dxf.shapes[2] else {
        throw VerifyError.failed("shape 2 is the CIRCLE")
    }
    try expect(near(c.x, 70) && near(c.y, 30) && near(r, 8), "CIRCLE center (70,30) r=8")
    ok("DXF parses: closed square + line + circle with exact geometry")

    // ── 3. STL → heightfield. ────────────────────────────────────────────────
    print("== STL → heightfield ==")
    let box = STLHeightfieldImporter.importSTL(
        at: try fixture("fixtures/import/happy_box.stl").path,
        cellSizeMm: 2.0, scale: 1.0
    )
    try expect(box.success, "happy_box.stl imports")
    try expect(box.triangleCount == 12, "12 triangles (got \(box.triangleCount))")
    guard let hf = box.heightfield else { throw VerifyError.failed("heightfield produced") }
    try expect(hf.width == 10 && hf.height == 10, "20mm box @2mm cells → 10×10 grid")
    let top = try hf.height(atX: 10, y: 10) ?? { throw VerifyError.failed("center cell") }()
    try expect(near(top, 10), "center cell at box top 10mm (got \(top))")
    try expect(near(hf.maxHeight, 10), "maxHeight = box top")
    ok("STL rasterizes: 10×10 grid, top 10mm")

    // ── 4. .shoppilot fixture packages: load + toolpath export. ─────────────
    print("== .shoppilot package fixtures ==")
    let cal = try DocumentLoader().loadPayload(from: fixture("fixtures/shoppilot/Calibration.shoppilot"))
    try expect(cal.job.name == "Calibration", "Calibration package name")
    try expect(cal.job.sheets.first?.layers.first?.vectors.count == 1,
               "Calibration keeps its 50mm square vector")
    try expect(cal.toolpaths.count == 1 && cal.toolpaths[0].name == "Profile 1",
               "Calibration keeps the Profile 1 toolpath")
    guard let calGcode = cal.toolpaths[0].toolpathResult else {
        throw VerifyError.failed("Calibration toolpath has G-code")
    }
    try expect(calGcode.contains("O=PROFILE_TOOLPATH"), "Profile marker present")
    let calLines = calGcode.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(calLines.count >= 100, "Profile G-code has ≥100 lines (got \(calLines.count))")
    ok("Calibration.shoppilot loads: square + Profile toolpath (\(calLines.count) lines)")

    let sign = try DocumentLoader().loadPayload(from: fixture("fixtures/shoppilot/Sign.shoppilot"))
    try expect(sign.job.name == "Sign SHOP", "Sign package name")
    let signSheet = try sign.job.sheets.first ?? { throw VerifyError.failed("sign sheet") }()
    try expect(signSheet.layers.first { $0.name == "Text" }?.vectors.count == 4,
               "Sign keeps 4 glyphs on the Text layer")
    try expect(signSheet.layers.first { $0.name == "Border" }?.vectors.count == 1,
               "Sign keeps 1 border vector")
    try expect(sign.toolpaths.count == 1 && sign.toolpaths[0].name == "V-Carve 1 (Recipe)",
               "Sign keeps the V-Carve recipe toolpath")
    guard let signGcode = sign.toolpaths[0].toolpathResult else {
        throw VerifyError.failed("Sign toolpath has G-code")
    }
    try expect(signGcode.contains("O=V_CARVE_TOOLPATH"), "V-Carve marker present")
    let signLines = signGcode.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(signLines.count >= 400, "V-Carve G-code ≥400 lines (got \(signLines.count))")
    ok("Sign.shoppilot loads: 4 glyphs + border + V-Carve (\(signLines.count) lines)")

    // ── 5. G-code export: GRBL post keeps move parity. ──────────────────────
    print("== G-code export (GRBL post) ==")
    let calG1 = calLines.filter { $0.contains("G1") }
    let posted = GRBLPostProcessor.grbl().process(gcodeLines: calLines).gcodeString
    try expect(posted.contains("G21"), "GRBL wrapper sets G21")
    try expect(posted.contains("G90"), "GRBL wrapper sets G90")
    try expect(posted.contains("M2"), "GRBL wrapper has M2 program end")
    try expect(posted.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("%"),
               "GRBL wrapper closes with % framing")
    let postedG1 = posted.components(separatedBy: .newlines).filter { $0.contains("G1") }
    try expect(postedG1.count == calG1.count,
               "move parity: every raw G1 survives the post (\(calG1.count) → \(postedG1.count))")
    ok("GRBL post: wrapper + move parity (\(calG1.count) G1 moves)")

    print("\nRESULT: SPK-SHAKEd \(total) checks — PASS")
}

do {
    try main()
} catch {
    print("FAIL: \(error)")
    exit(1)
}
