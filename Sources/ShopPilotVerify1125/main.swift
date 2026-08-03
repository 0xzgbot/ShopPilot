import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1125 verify without XCTest (CLT-only machines).
/// Proves the SVG import → session document chain:
///   1. SVGImporter parses real-world SVG (viewBox, smooth curves, repeated
///      coordinate pairs, primitive elements) into VectorShapes.
///   2. Parsed shapes assemble into a Job's layer vectors (the session-document
///      representation) and round-trip through the `.shoppilot` package.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

// MARK: - Fixture

/// A realistic SVG: viewBox + all path command classes + primitive elements.
let fixtureSVG = """
<svg width="1000" height="800" viewBox="0 0 100 80" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="40" height="30" fill="none"/>
  <circle cx="70" cy="20" r="8"/>
  <ellipse cx="30" cy="60" rx="12" ry="6"/>
  <line x1="0" y1="70" x2="90" y2="70"/>
  <polyline points="5,75 20,75 20,79"/>
  <polygon points="60,60 80,60 70,75"/>
  <path d="M 5 5 L 15 5 15 15 5 15 Z"/>
  <path d="M 50 40 C 60 30, 80 30, 90 40 S 100 60, 90 70"/>
  <path d="M 10 40 Q 20 30, 30 40 T 50 40"/>
  <path d="M 20 50 A 10 10 0 0 1 40 50"/>
</svg>
"""

// MARK: - Helpers

/// Sample a geometry shape into Core points (mirrors GeometryBridge).
func corePoints(of shape: ShopPilotGeometry.VectorShape) -> [ShopPilotCore.VectorPoint] {
    func c(_ p: ShopPilotGeometry.VectorPoint) -> ShopPilotCore.VectorPoint {
        ShopPilotCore.VectorPoint(x: p.x, y: p.y)
    }
    func circle(_ center: ShopPilotGeometry.VectorPoint, _ radius: Double) -> [ShopPilotCore.VectorPoint] {
        (0...48).map { i in
            let t = Double(i) / 48 * 2 * .pi
            return ShopPilotCore.VectorPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
        }
    }
    switch shape {
    case .line(let s, let e): return [c(s), c(e)]
    case .rectangle(let o, let w, let h):
        return [c(o), c(ShopPilotGeometry.VectorPoint(x: o.x + w, y: o.y)),
                c(ShopPilotGeometry.VectorPoint(x: o.x + w, y: o.y + h)),
                c(ShopPilotGeometry.VectorPoint(x: o.x, y: o.y + h)), c(o)]
    case .circle(let center, let r): return circle(center, r)
    case .ellipse(let center, let rx, let ry, _):
        return (0...48).map { i in
            let t = Double(i) / 48 * 2 * .pi
            return ShopPilotCore.VectorPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
        }
    case .polygon(let center, let r, let sides, _):
        var pts: [ShopPilotCore.VectorPoint] = (0..<sides).map { i in
            let t = Double(i) / Double(sides) * 2 * .pi
            return ShopPilotCore.VectorPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    case .star(let center, let outer, let inner, let points, _):
        var pts: [ShopPilotCore.VectorPoint] = []
        for i in 0..<(points * 2) {
            let t = Double(i) / Double(points * 2) * 2 * .pi
            let r = i.isMultiple(of: 2) ? outer : inner
            pts.append(ShopPilotCore.VectorPoint(x: center.x + r * cos(t), y: center.y + r * sin(t)))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    case .arc(let center, let r, let start, let end):
        let sweep = end - start
        return (0...24).map { i in
            let t = start + sweep * Double(i) / 24
            return ShopPilotCore.VectorPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
        }
    case .freehand(let pts): return pts.map(c)
    }
}

func main() throws {
    // 1. Full fixture parse.
    let result = SVGImporter.parse(fixtureSVG)
    try expect(result.success, "fixture parse success")
    try expect(result.shapes.count == 10, "fixture shape count: \(result.shapes.count)")
    try expect(result.documentSize == SVGDocumentSize(width: 1000, height: 800), "document size from width/height")

    // viewBox scale is 10x (1000/100), translate 0.
    guard case .rectangle(let origin, let width, let height) = result.shapes[0] else { throw VerifyError.failed("shapes[0] not rect") }
    let pathRect = (origin: origin, width: width, height: height)
    try expectClose(pathRect.origin.x, 50, "path rect origin.x (10*5 → viewBox 5..15 ×10)")
    try expectClose(pathRect.origin.y, 50, "path rect origin.y")
    try expectClose(pathRect.width, 100, "path rect width")
    try expectClose(pathRect.height, 100, "path rect height")

    // Smooth cubic C + S: endpoints land at 10× coordinates.
    guard case .freehand(let smoothCurve) = result.shapes[1] else { throw VerifyError.failed("shapes[1] not freehand") }
    try expect(smoothCurve.count == 17, "C+S freehand point count \(smoothCurve.count)")
    try expectClose(smoothCurve.last!.x, 900, "C+S end x")
    try expectClose(smoothCurve.last!.y, 700, "C+S end y")

    // Smooth quadratic Q + T.
    guard case .freehand(let quadCurve) = result.shapes[2] else { throw VerifyError.failed("shapes[2] not freehand") }
    try expect(quadCurve.count == 17, "Q+T freehand point count \(quadCurve.count)")
    try expectClose(quadCurve.last!.x, 500, "Q+T end x")
    try expectClose(quadCurve.last!.y, 400, "Q+T end y")

    // Arc.
    guard case .freehand(let arcCurve) = result.shapes[3] else { throw VerifyError.failed("shapes[3] not freehand") }
    try expect(arcCurve.count == 17, "arc freehand point count \(arcCurve.count)")
    try expectClose(arcCurve.last!.x, 400, "arc end x")
    try expectClose(arcCurve.last!.y, 500, "arc end y")

    // Primitives.
    guard case .rectangle(let rectOrigin, let rectWidth, let rectHeight) = result.shapes[4] else { throw VerifyError.failed("shapes[4] not rect") }
    let rectEl = (origin: rectOrigin, width: rectWidth, height: rectHeight)
    try expectClose(rectEl.origin.x, 100, "rect element origin.x")
    try expectClose(rectEl.origin.y, 100, "rect element origin.y")
    try expectClose(rectEl.width, 400, "rect element width")
    try expectClose(rectEl.height, 300, "rect element height")

    guard case .circle(let circleCenter, let circleRadius) = result.shapes[5] else { throw VerifyError.failed("shapes[5] not circle") }
    let circleEl = (center: circleCenter, radius: circleRadius)
    try expectClose(circleEl.center.x, 700, "circle center.x")
    try expectClose(circleEl.center.y, 200, "circle center.y")
    try expectClose(circleEl.radius, 80, "circle radius")

    guard case .ellipse(let ellCenter, let ellRx, let ellRy, _) = result.shapes[6] else { throw VerifyError.failed("shapes[6] not ellipse") }
    let ellipseEl = (center: ellCenter, radiusX: ellRx, radiusY: ellRy)
    try expectClose(ellipseEl.center.x, 300, "ellipse center.x")
    try expectClose(ellipseEl.radiusX, 120, "ellipse radiusX")
    try expectClose(ellipseEl.radiusY, 60, "ellipse radiusY")

    guard case .line(let lineStart, let lineEnd) = result.shapes[7] else { throw VerifyError.failed("shapes[7] not line") }
    let lineEl = (start: lineStart, end: lineEnd)
    try expectClose(lineEl.start.x, 0, "line start.x")
    try expectClose(lineEl.start.y, 700, "line start.y")
    try expectClose(lineEl.end.x, 900, "line end.x")
    try expectClose(lineEl.end.y, 700, "line end.y")

    guard case .freehand(let polylineEl) = result.shapes[8] else { throw VerifyError.failed("shapes[8] not polyline") }
    try expect(polylineEl.count == 3, "polyline point count")

    guard case .freehand(let polygonEl) = result.shapes[9] else { throw VerifyError.failed("shapes[9] not polygon") }
    try expect(polygonEl.count == 4, "polygon point count (closed)")
    try expect(
        abs(polygonEl.first!.x - polygonEl.last!.x) < 1e-6 && abs(polygonEl.first!.y - polygonEl.last!.y) < 1e-6,
        "polygon closed"
    )

    // 2. Implicit repeated coordinate pairs.
    let repeated = try SVGImporter.parsePathData("M 0 0 10 0 10 10 0 10 Z")
    try expect(repeated.count == 1, "repeated pairs produce one shape")
    guard case .rectangle(let repOrigin, let repWidth, let repHeight) = repeated[0] else { throw VerifyError.failed("repeated pairs not rect") }
    let repRect = (origin: repOrigin, width: repWidth, height: repHeight)
    try expectClose(repRect.width, 10, "repeated rect width")
    try expectClose(repRect.height, 10, "repeated rect height")

    let relativeRepeated = try SVGImporter.parsePathData("m 5 5 10 0 10 10")
    try expect(relativeRepeated.count == 1, "relative repeated pairs produce one shape")
    guard case .freehand(let relPts) = relativeRepeated[0] else { throw VerifyError.failed("relative repeated not freehand") }
    try expect(relPts.count == 3, "relative repeated points")
    try expectClose(relPts[1].x, 15, "relative second point x")
    try expectClose(relPts[2].x, 25, "relative third point x")
    try expectClose(relPts[2].y, 15, "relative third point y")

    // 3. SVG import → session document → .shoppilot package round-trip.
    var job = Job(name: "SVG Import Job")
    var sheet = Sheet(name: "Design", width: 1000, depth: 800, height: 20)
    var layer = Layer(name: "Imported SVG")
    for shape in result.shapes {
        let pts = corePoints(of: shape)
        var isClosed = true
        if case .line = shape { isClosed = false }
        if case .arc = shape { isClosed = false }
        layer.addVector(ShopPilotCore.VectorPath(name: "SVG Shape", points: pts, isClosed: isClosed))
    }
    sheet.addLayer(layer)
    job.addSheet(sheet)

    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1125-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let packageURL = temp.appendingPathComponent("svg-import.shoppilot")
    try DocumentSaver().save(ShopPilotPackagePayload(job: job), to: packageURL)
    let loaded = try DocumentLoader().loadPayload(from: packageURL)
    let vectors = loaded.job.sheets.flatMap(\.layers).flatMap(\.vectors)
    try expect(vectors.count == result.shapes.count, "round-trip vector count \(vectors.count)")
    for (index, vector) in vectors.enumerated() {
        try expect(vector.points.count >= 2, "vector \(index) has ≥2 points")
    }

    // 4. Robust error handling.
    let garbage = SVGImporter.parse("this is not an svg at all")
    try expect(garbage.shapes.isEmpty, "garbage yields no shapes")
    try expect(garbage.success, "garbage is not fatal")
    let truncatedPath = SVGImporter.parse("<svg><path d=\"M 5 5 C 1\"/></svg>")
    try expect(truncatedPath.success, "truncated path not fatal")
    try expect(truncatedPath.shapes.isEmpty, "truncated path yields no shapes")

    print("SPK-1125 verification: PASS")
    print("  \(result.shapes.count) shapes parsed from realistic SVG (viewBox 10x, C/S/Q/T/A, primitives)")
    print("  implicit repeated coordinate pairs OK")
    print("  SVG shapes → session Job vectors → .shoppilot round-trip OK (\(vectors.count) vectors)")
    print("  garbage / truncated input handled without crash")
}

do {
    try main()
} catch {
    fputs("SPK-1125 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
