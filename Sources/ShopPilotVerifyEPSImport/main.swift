import Foundation
import ShopPilotCore
import ShopPilotGeometry

// MARK: - Verify helpers

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

// MARK: - Fixtures

func writeFixture(_ content: String, named name: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShopPilotVerifyEPSImport-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

/// Closed rectangle: 10,10 → 90,10 → 90,90 → 10,90 → back to 10,10, then closepath.
let rectEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 100 100
newpath
10 10 moveto
90 10 lineto
90 90 lineto
10 90 lineto
10 10 lineto
closepath
stroke
"""

/// Open polyline: no closepath, ends at 90,90.
let openPolylineEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 100 100
newpath
10 10 moveto
90 10 lineto
90 90 lineto
stroke
"""

/// Cubic: (0,0) with control points (0,50),(50,50) to (50,0) — bows up.
let curveEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 50 50
newpath
0 0 moveto
0 50 50 50 50 0 curveto
stroke
"""

/// Two independent closed paths (second starts after a newpath).
let twoPathsEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 100 100
newpath
10 10 moveto
50 10 lineto
50 50 lineto
10 10 lineto
closepath
stroke
newpath
60 60 moveto
90 60 lineto
90 90 lineto
60 60 lineto
closepath
stroke
"""

/// BoundingBox starts at (10,20) — coordinates must be offset by minX/minY.
let offsetBBoxEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 10 20 110 120
newpath
10 20 moveto
50 40 lineto
stroke
"""

/// Noise operators (colors, linewidth, gsave/grestore, text) must be skipped.
let noisyEPS = """
%!PS-Adobe-3.0 EPSF-3.0
%%BoundingBox: 0 0 100 100
%%Creator: EPSImporter verify
1 0 0 setrgbcolor
0.5 setlinewidth
gsave
(Hello World) show
grestore
newpath
10 10 moveto
90 10 lineto
90 90 lineto
10 10 lineto
closepath
0.5 setlinewidth
stroke
0 0 0 setrgbcolor
"""

// MARK: - Tests

func main() throws {
    // ── 1. Closed rectangle ──────────────────────────────────────────────
    let rectPath = try writeFixture(rectEPS, named: "rect.eps")
    let rectResult = EPSImporter.importEPS(at: rectPath)
    try expect(rectResult.success, "rect: import success")
    try expect(rectResult.pathCount == 1, "rect: pathCount == 1")
    try expect(rectResult.shapes.count == 1, "rect: one shape")
    try expect(rectResult.fileSizeBytes > 0, "rect: fileSizeBytes reported")
    try expect(rectResult.errorMessage == nil, "rect: no error message")
    guard case .freehand(let rectPts) = rectResult.shapes[0] else {
        throw VerifyError.failed("rect: shape is not a .freehand")
    }
    try expect(rectPts.count >= 4, "rect: 4+ points (got \(rectPts.count))")
    try expect(rectPts.first == rectPts.last, "rect: first == last (closed)")
    try expect(rectResult.shapes[0].isClosedShape, "rect: isClosedShape true")
    try expectClose(rectPts.first!.x, 10, "rect: first x (bbox 0 0 100 100, no offset)")
    try expectClose(rectPts.first!.y, 10, "rect: first y")
    try expectClose(rectPts.map(\.x).max()!, 90, "rect: max x == 90")
    try expectClose(rectPts.map(\.y).max()!, 90, "rect: max y == 90")

    // Result must be importable by the app via GeometryBridge.
    let rectCore = GeometryBridge.toCorePaths(rectResult.shapes)
    try expect(rectCore.count == 1, "rect: toCorePaths produces 1 path")
    try expect(rectCore[0].isClosed, "rect: toCorePaths marks the path closed")
    try expect(rectCore[0].points.count == rectPts.count, "rect: toCorePaths preserves points")

    // ── 2. Open polyline stays open ──────────────────────────────────────
    let openPath = try writeFixture(openPolylineEPS, named: "open.eps")
    let openResult = EPSImporter.importEPS(at: openPath)
    try expect(openResult.success, "open: import success")
    try expect(openResult.shapes.count == 1, "open: one shape")
    guard case .freehand(let openPts) = openResult.shapes[0] else {
        throw VerifyError.failed("open: shape is not a .freehand")
    }
    try expect(openPts.count == 3, "open: 3 points")
    try expect(openPts.first != openPts.last, "open: first != last (stays open)")
    try expect(!openResult.shapes[0].isClosedShape, "open: isClosedShape false")
    let openCore = GeometryBridge.toCorePaths(openResult.shapes)
    try expect(openCore[0].isClosed == false, "open: toCorePaths keeps it open")

    // ── 3. curveto sampled into a curved freehand ────────────────────────
    let curvePath = try writeFixture(curveEPS, named: "curve.eps")
    let curveResult = EPSImporter.importEPS(at: curvePath)
    try expect(curveResult.success, "curve: import success")
    try expect(curveResult.shapes.count == 1, "curve: one shape")
    guard case .freehand(let curvePts) = curveResult.shapes[0] else {
        throw VerifyError.failed("curve: shape is not a .freehand")
    }
    try expect(curvePts.count >= 10, "curve: sampled to many points (got \(curvePts.count))")
    try expectClose(curvePts.first!.x, 0, "curve: starts at x 0")
    try expectClose(curvePts.first!.y, 0, "curve: starts at y 0")
    try expectClose(curvePts.last!.x, 50, "curve: ends at x 50")
    try expectClose(curvePts.last!.y, 0, "curve: ends at y 0")
    let curveMaxY = curvePts.map(\.y).max()!
    try expect(curveMaxY > 5, "curve: bows away from the straight chord (max y \(curveMaxY))")

    // ── 4. Two separate paths → two shapes ───────────────────────────────
    let twoPath = try writeFixture(twoPathsEPS, named: "two.eps")
    let twoResult = EPSImporter.importEPS(at: twoPath)
    try expect(twoResult.success, "two: import success")
    try expect(twoResult.pathCount == 2, "two: pathCount == 2")
    try expect(twoResult.shapes.count == 2, "two: two shapes")
    try expect(twoResult.shapes[0].isClosedShape && twoResult.shapes[1].isClosedShape, "two: both closed")

    // ── 5. Scale parameter scales coordinates ────────────────────────────
    let scaled = EPSImporter.importEPS(at: rectPath, scale: 2.0)
    try expect(scaled.success, "scale: import success")
    guard case .freehand(let scaledPts) = scaled.shapes[0] else {
        throw VerifyError.failed("scale: shape is not a .freehand")
    }
    try expectClose(scaledPts.first!.x, 20, "scale: first x doubled (10 → 20)")
    try expectClose(scaledPts.first!.y, 20, "scale: first y doubled")
    try expectClose(scaledPts.map(\.x).max()!, 180, "scale: max x doubled (90 → 180)")

    // ── 6. Garbage input → success=false, no crash ───────────────────────
    let garbagePath = try writeFixture("this is not postscript at all — just prose.\n", named: "garbage.eps")
    let garbage = EPSImporter.importEPS(at: garbagePath)
    try expect(!garbage.success, "garbage: success == false")
    try expect(garbage.errorMessage != nil, "garbage: error message present")
    try expect(garbage.shapes.isEmpty, "garbage: no shapes")
    try expect(garbage.pathCount == 0, "garbage: pathCount == 0")

    let missing = EPSImporter.importEPS(at: "/nonexistent/does-not-exist.eps")
    try expect(!missing.success, "missing file: success == false")
    try expect(missing.errorMessage != nil, "missing file: error message present")

    // ── 7. BoundingBox offsets coordinates (minX/minY subtracted) ────────
    let bboxPath = try writeFixture(offsetBBoxEPS, named: "offset.eps")
    let bboxResult = EPSImporter.importEPS(at: bboxPath)
    try expect(bboxResult.success, "bbox: import success")
    guard case .freehand(let bboxPts) = bboxResult.shapes[0] else {
        throw VerifyError.failed("bbox: shape is not a .freehand")
    }
    try expect(bboxPts.count == 2, "bbox: 2 points")
    try expectClose(bboxPts[0].x, 0, "bbox: minX subtracted (10 → 0)")
    try expectClose(bboxPts[0].y, 0, "bbox: minY subtracted (20 → 0)")
    try expectClose(bboxPts[1].x, 40, "bbox: 50 - 10 == 40")
    try expectClose(bboxPts[1].y, 20, "bbox: 40 - 20 == 20")

    // ── Bonus: noise operators are skipped gracefully ────────────────────
    let noisyPath = try writeFixture(noisyEPS, named: "noisy.eps")
    let noisy = EPSImporter.importEPS(at: noisyPath)
    try expect(noisy.success, "noisy: import success")
    try expect(noisy.shapes.count == 1, "noisy: colors/linewidth/text skipped, one shape left")
    guard case .freehand(let noisyPts) = noisy.shapes[0] else {
        throw VerifyError.failed("noisy: shape is not a .freehand")
    }
    try expect(noisyPts.first == noisyPts.last, "noisy: closepath still honored after noise")

    print("ShopPilotVerifyEPSImport: PASS — bbox offset, scale, closed rect, open polyline, curveto sampling, multi-path, garbage handling, noise skip")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyEPSImport: FAIL — \(error)")
    exit(1)
}
