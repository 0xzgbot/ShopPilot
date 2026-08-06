import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ShopPilotCore
import ShopPilotGeometry

/// Studio-surface verify (CLT machine, no XCTest) — the expected
/// features: text, bitmap trace, DXF export, STL export, quick engrave.
///   1. TEXT: TextTool renders glyph curves (CoreText) — non-empty shapes,
///      sensible bounding box for a known string.
///   2. TRACE: a black square on white, traced at 0.5 → ≥1 closed path.
///   3. DXF EXPORT: line/circle/rect/freehand → DXF that round-trips through
///      the project's own DXFParser with the same shape count.
///   4. STL EXPORT: 4×4 heightfield → ASCII STL that re-imports through
///      STLHeightfieldImporter with matching grid + triangle count.
///   5. QUICK ENGRAVE: fixed-depth single-pass G-code with the right marker.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func writePNG(_ rows: [[[UInt8]]], to url: URL) throws {
    let h = rows.count
    let w = rows[0].count
    var data = [UInt8](repeating: 0, count: w * h * 4)
    for r in 0..<h {
        for c in 0..<w {
            let o = (r * w + c) * 4
            for k in 0..<4 { data[o + k] = rows[r][c][k] }
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &data, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw VerifyError.failed("PNG context") }
    guard let img = ctx.makeImage() else { throw VerifyError.failed("PNG image") }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw VerifyError.failed("PNG destination")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw VerifyError.failed("PNG finalize") }
}

func tempURL(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

func main() throws {
    // ── 1. Text as vector glyphs ───────────────────────────────────────────
    let text = TextTool.createText(text: "AB", font: "Helvetica Neue", fontSize: 72, scale: 1.0)
    try expect(!text.isEmpty, "text renders glyph shapes")
    try expect(text.shapes.allSatisfy { if case .freehand = $0 { return true } else { return false } },
               "glyphs are freehand curves")
    let b = text.boundingRect
    try expect(b.width > 20 && b.height > 40, "two glyphs have a sensible bbox (got \(b.width)x\(b.height))")

    // ── 2. Bitmap trace: black square on white ─────────────────────────────
    let blackPx: [UInt8] = [0, 0, 0, 255]
    let whitePx: [UInt8] = [255, 255, 255, 255]
    // 20×20 image: black 10×10 square in the middle.
    var rows: [[[UInt8]]] = []
    for r in 0..<20 {
        var row: [[UInt8]] = []
        for c in 0..<20 {
            row.append((r >= 5 && r < 15 && c >= 5 && c < 15) ? blackPx : whitePx)
        }
        rows.append(row)
    }
    let pngURL = try tempURL("trace.png")
    try writePNG(rows, to: pngURL)
    let trace = BitmapTracer.trace(from: pngURL, quality: BitmapTraceQuality(threshold: 0.5), imageWidth: 100, imageHeight: 100)
    try expect(!trace.paths.isEmpty, "trace finds the square outline (got \(trace.paths.count) paths)")
    try expect(trace.paths.contains { $0.isClosed }, "at least one traced path is closed")
    // The square is 10/20 of the image → 50mm of 100mm.
    let traced = trace.paths[0]
    let tb = Rect(
        minX: traced.points.map { $0.x }.min() ?? 0,
        minY: traced.points.map { $0.y }.min() ?? 0,
        maxX: traced.points.map { $0.x }.max() ?? 0,
        maxY: traced.points.map { $0.y }.max() ?? 0
    )
    try expect(abs(tb.width - 50) < 8, "traced square ≈50mm wide (got \(tb.width))")

    // ── 3. DXF export round-trip ───────────────────────────────────────────
    let shapes: [VectorShape] = [
        .line(start: pt(0, 0), end: pt(10, 0)),
        .circle(center: pt(5, 5), radius: 3),
        .rectangle(origin: pt(0, 0), width: 10, height: 10),
        .freehand(points: [pt(0, 0), pt(4, 0), pt(4, 4), pt(0, 4), pt(0, 0)]),
    ]
    let dxf = VectorDXFExporter.dxfString(from: shapes)
    try expect(dxf.contains("0\nLINE") && dxf.contains("0\nCIRCLE") && dxf.contains("0\nLWPOLYLINE"),
               "DXF contains LINE, CIRCLE and LWPOLYLINE entities")
    let parsed = DXFParser.parse(dxf)
    try expect(parsed.shapes.count == 4, "DXF round-trips 4 shapes (got \(parsed.shapes.count))")
    try expect(parsed.errors.isEmpty, "no parser warnings on our own export")

    // ── 4. STL export round-trip ───────────────────────────────────────────
    // 4×4 heightfield: 10mm everywhere, 20mm center block.
    var heights = [Double](repeating: 10, count: 16)
    for r in 1...2 { for c in 1...2 { heights[r * 4 + c] = 20 } }
    let hf = HeightfieldData(width: 4, height: 4, cellSizeMm: 5, minX: 0, minY: 0, heights: heights)
    let stl = try HeightfieldSTLExporter.stlString(from: hf) ?? { throw VerifyError.failed("STL string") }()
    let expectedTriangles = 2 * 4 * 4 + 2 * (2 * 4 + 2 * 4) + 2   // top + walls + bottom
    try expect(stl.components(separatedBy: "facet normal").count - 1 == expectedTriangles,
               "triangle count \(expectedTriangles) (got \(stl.components(separatedBy: "facet normal").count - 1))")
    let stlURL = try tempURL("relief.stl")
    try stl.write(to: stlURL, atomically: true, encoding: .utf8)
    let reimport = STLHeightfieldImporter.importSTL(at: stlURL.path, cellSizeMm: 5, scale: 1.0)
    try expect(reimport.success, "exported STL re-imports")
    guard let back = reimport.heightfield else { throw VerifyError.failed("reimported heightfield") }
    try expect(back.width == 4 && back.height == 4, "reimported grid 4×4 (got \(back.width)x\(back.height))")
    try expect(abs(back.maxHeight - 20) < 1.0, "reimported peak ≈20mm (got \(back.maxHeight))")

    // ── 5. Quick Engrave ───────────────────────────────────────────────────
    let path = VectorPath(id: UUID(), points: [pt(0, 0), pt(10, 0), pt(10, 10)], isClosed: false)
    let eng = QuickEngraveToolpathEngine.compute(
        paths: [path],
        params: QuickEngraveToolpathParams(cutDepthMm: 1.5),
        stockHeightMm: 25.0
    )
    try expect(eng.gcodeLines.contains("O=QUICK_ENGRAVE_TOOLPATH"), "quick engrave marker")
    let zs = eng.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(zs.allSatisfy { $0.contains("-1.500") }, "single-pass fixed depth −1.5 (got \(zs))")
    try expect(eng.gcodeLines.filter { $0.hasPrefix("G1 X") }.count == 2,
               "two cut moves along the polyline")

    print("ShopPilotVerifyStudio: PASS - text glyphs, bitmap trace, DXF round-trip, STL round-trip, quick engrave")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyStudio: FAIL - \(error)")
    exit(1)
}
