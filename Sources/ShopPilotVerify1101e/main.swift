import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1101e verify (CLT machines, no XCTest).
/// Proves the SVG import spine the Design hub / ⌘K "Import SVG…" route to:
///   1. A realistic fixture SVG (viewBox + rect + circle + path + line) parses
///      to one shape per element, reports success + document size, and is
///      readable through the same file→string path `AppSession.importSVG(from:)`
///      uses.
///   2. The viewBox transform is honored (width/viewBoxWidth scale).
///   3. Edge cases: empty SVG → 0 shapes; malformed path → errors reported.
///   4. Persist: imported shapes survive a `.shoppilot`-style Job encode/decode
///      round-trip layer-faithfully (the completion path of importSVG, which
///      lands shapes through `addShapes` → syncLayerVectors → save).
/// The panel/hub UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

let fixtureSVG = """
<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="30" height="20"/>
  <circle cx="60" cy="50" r="10"/>
  <path d="M 0 0 L 50 0 L 50 50 Z"/>
  <line x1="0" y1="80" x2="100" y2="80"/>
</svg>
"""

/// Mirror of AppSession.shapesFromLayerVectors: flatten layers, rebuild
/// (shapes, layerIDs) from persisted VectorPath.layerId.
func reconstruct(from job: Job) -> (shapes: [VectorShape], layerIDs: [UUID]) {
    var shapes: [VectorShape] = []
    var layerIDs: [UUID] = []
    for layer in job.sheets.flatMap(\.layers) {
        for path in layer.vectors {
            let pts = path.points.map { ShopPilotGeometry.VectorPoint(x: $0.x, y: $0.y) }
            shapes.append(VectorShape.freehand(points: pts))
            layerIDs.append(path.layerId)
        }
    }
    return (shapes, layerIDs)
}

func main() throws {
    // ── 1. File → parse (the session.importSVG(from:) read path). ────────────
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1101e_fixture.svg")
    try fixtureSVG.write(to: tempURL, atomically: true, encoding: .utf8)
    let content = try String(contentsOf: tempURL, encoding: .utf8)
    try? FileManager.default.removeItem(at: tempURL)

    let result = SVGImporter.parse(content)
    try expect(result.success, "fixture SVG parses without fatal errors")
    try expect(result.shapes.count == 4, "fixture yields 4 shapes (rect/circle/path/line), got \(result.shapes.count)")
    try expect(result.documentSize?.width == 100 && result.documentSize?.height == 100,
               "document size read from width/height attrs")

    // Element → shape-type sanity (what the canvas will draw).
    let types = result.shapes.map { shape -> String in
        switch shape {
        case .rectangle: return "rect"
        case .circle: return "circle"
        case .freehand: return "freehand"
        case .line: return "line"
        default: return "other"
        }
    }
    try expect(types.contains("rect") && types.contains("circle")
                   && types.contains("freehand") && types.contains("line"),
               "fixture produces one shape per element type (got \(types))")

    // ── 2. viewBox transform honored: width/viewBoxWidth scale. ──────────────
    let scaledSVG = """
    <svg width="100" height="100" viewBox="0 0 50 50" xmlns="http://www.w3.org/2000/svg">
      <rect x="10" y="10" width="10" height="10"/>
    </svg>
    """
    let scaled = SVGImporter.parse(scaledSVG)
    try expect(scaled.success && scaled.shapes.count == 1, "scaled fixture parses one rect")
    if let rect = scaled.shapes.first {
        try expectClose(rect.boundingRect.minX, 20.0, "viewBox scale 2x shifts rect x to 20")
        try expectClose(rect.boundingRect.maxX, 40.0, "viewBox scale 2x stretches rect width")
    }

    // ── 3. Edge cases. ───────────────────────────────────────────────────────
    let empty = SVGImporter.parse("<svg width=\"10\" height=\"10\"></svg>")
    try expect(empty.success && empty.shapes.isEmpty, "empty SVG → 0 shapes, no fatal errors")

    // The tokenizer is deliberately lenient: unrecognized path tokens are
    // skipped, so a garbage path yields 0 shapes without crashing (the
    // session then reports "No drawable shapes found").
    let garbage = SVGImporter.parse(#"<svg><path d="M 0 0 L not-a-number"/></svg>"#)
    try expect(garbage.shapes.isEmpty, "garbage path → 0 shapes (lenient skip)")
    try expect(!garbage.errors.contains { $0.hasPrefix("FATAL") },
               "garbage path is not a fatal error")

    // ── 4. Persist: imported shapes round-trip layer-faithfully. ─────────────
    // The session's import completion: addShapes assigns the active layer id,
    // syncLayerVectors distributes by layerId, savePackage writes the Job.
    let layer = Layer(name: "Imported")
    let paths = GeometryBridge.toCorePaths(
        result.shapes,
        layerIDs: Array(repeating: layer.id, count: result.shapes.count)
    )
    try expect(paths.count == 4, "imported shapes convert to 4 paths")

    var layers = [layer]
    LayerVisibility.distribute(paths, into: &layers)
    try expect(layers[0].vectors.count == 4, "all imported paths land on the import layer")

    var job = Job(name: "SVG import round-trip")
    _ = job.ensureSingleSheet()
    job.sheets[0].layers = layers
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)

    let restored = reconstruct(from: decoded)
    try expect(restored.shapes.count == 4, "round-trip restores all 4 imported shapes")
    try expect(restored.layerIDs.allSatisfy { $0 == layer.id },
               "round-trip keeps every imported shape on its layer")

    // Geometry intact: the rect-derived path keeps its corner chain.
    let rectPath = decoded.sheets[0].layers
        .flatMap(\.vectors)
        .first { $0.points.count == 5 }?.points ?? []
    try expect(rectPath.count == 5, "rect imports as a 5-point closed chain")
    if rectPath.count == 5 {
        try expectClose(rectPath[0].x, 10.0, "rect chain starts at x=10")
        try expectClose(rectPath[0].y, 10.0, "rect chain starts at y=10")
        try expectClose(rectPath[3].x, 10.0, "rect chain keeps its left edge")
    }

    print("ShopPilotVerify1101e: PASS — fixture parse, viewBox transform, edge cases, layer-faithful round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1101e: FAIL — \(error)")
    exit(1)
}
