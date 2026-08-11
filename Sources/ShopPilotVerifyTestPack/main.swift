import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// Test-pack verifier (CLT machine, no XCTest).
/// Proves every generated test-pack file LOADS through the real importers
/// and produces usable content — a test file you can't open is worthless.
///   1. complex_artwork.svg → SVGImporter: ≥ 12 shapes, no errors
///   2. complex_plate.dxf   → DXFParser:   ≥ 14 shapes, no errors
///   3. terrain_mesh.stl    → STLHeightfieldImporter: > 4000 triangles,
///      heightfield rasterizes non-empty
///   4. MasterTest.shoppilot → DocumentLoader: 2 sheets, 5 toolpaths,
///      non-empty G-code

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let pack = cwd.appendingPathComponent("fixtures/testpack")

    // ── 1. SVG ────────────────────────────────────────────────────────────
    let svgURL = pack.appendingPathComponent("complex_artwork.svg")
    let svgText = try String(contentsOf: svgURL, encoding: .utf8)
    let svgResult = SVGImporter.parse(svgText)
    try expect(svgResult.shapes.count >= 12, "SVG: expected ≥12 shapes, got \(svgResult.shapes.count)")
    try expect(svgResult.errors.isEmpty, "SVG: unexpected errors \(svgResult.errors)")

    // ── 2. DXF ────────────────────────────────────────────────────────────
    let dxfURL = pack.appendingPathComponent("complex_plate.dxf")
    let dxfText = try String(contentsOf: dxfURL, encoding: .utf8)
    let dxfResult = DXFParser.parse(dxfText)
    try expect(dxfResult.shapes.count >= 14, "DXF: expected ≥14 shapes, got \(dxfResult.shapes.count)")
    try expect(dxfResult.errors.isEmpty, "DXF: unexpected errors \(dxfResult.errors)")

    // ── 3. STL terrain ────────────────────────────────────────────────────
    let stlURL = pack.appendingPathComponent("terrain_mesh.stl")
    let stlResult = STLHeightfieldImporter.importSTL(at: stlURL.path, cellSizeMm: 2.0)
    try expect(stlResult.success, "STL: import failed — \(stlResult.errorMessage ?? "?")")
    try expect(stlResult.triangleCount > 4000, "STL: expected >4000 triangles, got \(stlResult.triangleCount)")
    if let hf = stlResult.heightfield {
        try expect(!hf.heights.isEmpty, "STL: heightfield rasterized empty")
        let maxH = hf.heights.max() ?? 0
        try expect(maxH > 4.0, "STL: terrain too flat (maxH \(maxH))")
    } else {
        throw VerifyError.failed("STL: no heightfield")
    }

    // ── 4. MasterTest.shoppilot ───────────────────────────────────────────
    let docURL = pack.appendingPathComponent("MasterTest.shoppilot")
    let loaded = try DocumentLoader().loadPayload(from: docURL)
    try expect(loaded.job.sheets.count == 2, "doc: expected 2 sheets")
    let front = loaded.job.sheets.first { $0.name == "Front" }
    try expect(front?.layers.count == 3, "doc: Front should have 3 layers")
    try expect(loaded.toolpaths.count == 5, "doc: expected 5 toolpaths")
    let gcodeTotal = loaded.toolpaths
        .compactMap { $0.toolpathResult }
        .reduce(0) { $0 + $1.components(separatedBy: .newlines).count }
    try expect(gcodeTotal > 500, "doc: expected >500 G-code lines, got \(gcodeTotal)")

    print("ShopPilotVerifyTestPack: PASS — SVG \(svgResult.shapes.count) shapes, DXF \(dxfResult.shapes.count) entities, "
          + "STL \(stlResult.triangleCount) triangles (heightfield \(stlResult.heightfield?.heights.count ?? 0) cells), "
          + "doc 2 sheets / 5 toolpaths / \(gcodeTotal) G-code lines")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyTestPack: FAIL — \(error)")
    exit(1)
}
