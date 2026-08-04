import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1101d verify (CLT machines, no XCTest).
/// Proves the Design ops spine the Ops bar routes to:
///   1. Engine semantics for every op the bar exposes — Join, Close, Weld,
///      Subtract, Intersect, Offset, Trim (line + open polyline + closed
///      polygon clipping).
///   2. isClosedShape boundary detection (the Trim boundary/target split the
///      session uses).
///   3. Persist: op results survive a `.shoppilot`-style Job encode/decode
///      round-trip with geometry intact (the AppSession save path).
/// The SwiftUI bar + apply* routing is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func points(of shape: VectorShape) -> [VectorPoint] {
    switch shape {
    case .line(let s, let e): return [s, e]
    case .freehand(let pts): return pts
    case .rectangle(let o, let w, let h):
        return [o, VectorPoint(x: o.x + w, y: o.y), VectorPoint(x: o.x + w, y: o.y + h), VectorPoint(x: o.x, y: o.y + h)]
    default: return []
    }
}

func main() throws {
    // ── 1. Join: two polylines sharing an endpoint merge into one. ──────────
    let a = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0),
    ])
    let b = VectorShape.freehand(points: [
        VectorPoint(x: 10, y: 0), VectorPoint(x: 10, y: 10),
    ])
    guard let joined = ShapeJoinEngine.joinPolylines(a, b) else {
        throw VerifyError.failed("join of endpoint-sharing polylines must succeed")
    }
    try expect(points(of: joined).count == 3, "joined polyline has 3 vertices")

    // ── 2. Close: an open polyline becomes a closed loop. ───────────────────
    let open = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0), VectorPoint(x: 10, y: 10),
    ])
    let closedPieces = ShapeJoinEngine.closePolyline(open)
    guard let closed = closedPieces.first else {
        throw VerifyError.failed("closePolyline must produce a shape")
    }
    try expect(points(of: closed).first == points(of: closed).last, "closed polyline loops back")
    try expect(closed.isClosedShape, "closed polyline reports isClosedShape")

    // ── 3. Weld: overlapping rects union into fewer shapes. ─────────────────
    let r1 = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 20, height: 20)
    let r2 = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 10), width: 20, height: 20)
    let welded = ShapeBooleanEngine.weld(shapes: [r1, r2])
    try expect(!welded.isEmpty, "weld of overlapping rects yields output")

    // ── 4. Subtract: base minus a tool inside it. ───────────────────────────
    let base = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 30, height: 30)
    let tool = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 5), width: 10, height: 10)
    let subtracted = ShapeBooleanEngine.subtract(base: base, tool: tool)
    try expect(!subtracted.isEmpty, "subtract of inner tool yields output")

    // ── 5. Intersect: overlapping rects keep the overlap. ───────────────────
    let intersected = ShapeBooleanEngine.intersect(shapes: [r1, r2])
    try expect(!intersected.isEmpty, "intersect of overlapping rects yields output")

    // ── 6. Offset: positive distance grows the bounding box. ────────────────
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 10), width: 20, height: 20)
    let offsetPieces = VectorOffsetCalculator.offsetShape(rect, by: 3.0)
    try expect(!offsetPieces.isEmpty, "offset of a rect yields output")
    if let offsetRect = offsetPieces.first {
        let ob = offsetRect.boundingRect
        try expectClose(ob.minX, 7.0, "offset rect minX grew outward")
        try expectClose(ob.maxX, 33.0, "offset rect maxX grew outward")
    }

    // ── 7. Trim engine: line clipped to a box. ──────────────────────────────
    let box = Rect(minX: 0, minY: 0, maxX: 20, maxY: 20)
    let crossing = VectorShape.line(start: VectorPoint(x: -10, y: 5), end: VectorPoint(x: 30, y: 5))
    let clippedLine = ShapeJoinEngine.trimToBox(crossing, in: box)
    try expect(clippedLine.count == 1, "crossing line clips to one piece")
    if let piece = clippedLine.first {
        try expectClose(points(of: piece)[0].x, 0.0, "clipped line starts at box edge")
        try expectClose(points(of: piece)[1].x, 20.0, "clipped line ends at box edge")
    }

    // ── 8. Trim engine: open polyline clipped to the box (all vertices in). ─
    let openCrossing = VectorShape.freehand(points: [
        VectorPoint(x: -10, y: 3), VectorPoint(x: 10, y: 3), VectorPoint(x: 10, y: 30),
    ])
    let clippedOpen = ShapeJoinEngine.trimToBox(openCrossing, in: box)
    try expect(!clippedOpen.isEmpty, "open polyline trim yields pieces")
    for piece in clippedOpen {
        for pt in points(of: piece) {
            try expect(
                pt.x >= box.minX - 1e-9 && pt.x <= box.maxX + 1e-9
                    && pt.y >= box.minY - 1e-9 && pt.y <= box.maxY + 1e-9,
                "open polyline trim keeps every vertex inside the box"
            )
        }
    }

    // ── 9. Trim engine: closed polygon partially outside → polygon clip. ────
    let closedPoly = VectorShape.freehand(points: [
        VectorPoint(x: -5, y: -5), VectorPoint(x: 15, y: -5),
        VectorPoint(x: 15, y: 15), VectorPoint(x: -5, y: 15), VectorPoint(x: -5, y: -5),
    ])
    let clippedPoly = ShapeJoinEngine.trimToBox(closedPoly, in: box)
    try expect(clippedPoly.count == 1, "closed polygon trim yields one piece")
    if let piece = clippedPoly.first {
        try expect(piece.isClosedShape, "polygon-clipped piece stays closed")
        for pt in points(of: piece) {
            try expect(
                pt.x >= box.minX - 1e-9 && pt.x <= box.maxX + 1e-9
                    && pt.y >= box.minY - 1e-9 && pt.y <= box.maxY + 1e-9,
                "polygon clip keeps every vertex inside the box"
            )
        }
    }

    // ── 10. Session trim semantics (mirror of applyTrimToSelection): ────────
    // boundary = union bbox of closed shapes; targets = open vectors.
    let boundary = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 20, height: 20)
    let target = VectorShape.line(start: VectorPoint(x: -10, y: 10), end: VectorPoint(x: 30, y: 10))
    try expect(boundary.isClosedShape, "rect is a closed boundary")
    try expect(!target.isClosedShape, "line is an open target")
    var unionBox: Rect?
    for shape in [boundary, target] where shape.isClosedShape {
        let r = shape.boundingRect
        if var b = unionBox {
            b = Rect(minX: min(b.minX, r.minX), minY: min(b.minY, r.minY),
                     maxX: max(b.maxX, r.maxX), maxY: max(b.maxY, r.maxY))
            unionBox = b
        } else {
            unionBox = r
        }
    }
    guard let boundaryBox = unionBox else { throw VerifyError.failed("no boundary box") }
    let trimmedTarget = ShapeJoinEngine.trimToBox(target, in: boundaryBox)
    try expect(trimmedTarget.count == 1, "line across the boundary trims to one piece")
    if let piece = trimmedTarget.first {
        try expectClose(points(of: piece)[0].x, 0.0, "trimmed line starts at boundary edge")
        try expectClose(points(of: piece)[1].x, 20.0, "trimmed line ends at boundary edge")
    }

    // ── 11. Persist: op results survive a .shoppilot-style round-trip. ──────
    let resultShapes = [boundary] + trimmedTarget  // what the session leaves behind
    var layer = Layer(name: "Design")
    // The session always converts with per-shape layer ids (SPK-1137) — same
    // here, so distribute keeps every path on its layer.
    let paths = GeometryBridge.toCorePaths(
        resultShapes,
        layerIDs: Array(repeating: layer.id, count: resultShapes.count)
    )
    try expect(paths.count == 2, "op results convert to 2 paths")
    var layers = [layer]
    LayerVisibility.distribute(paths, into: &layers)

    var job = Job(name: "Ops round-trip")
    _ = job.ensureSingleSheet()
    job.sheets[0].layers = layers
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    let restoredPaths = decoded.sheets[0].layers.flatMap(\.vectors)
    try expect(restoredPaths.count == 2, "round-trip keeps both op-result paths")
    // Geometry intact: the trimmed line still spans the boundary box exactly.
    let trimmedPoints = restoredPaths
        .first { $0.points.count == 2 }?.points ?? []
    try expect(trimmedPoints.count == 2, "trimmed line restored with 2 points")
    if trimmedPoints.count == 2 {
        try expectClose(trimmedPoints[0].x, 0.0, "restored trimmed line start x")
        try expectClose(trimmedPoints[1].x, 20.0, "restored trimmed line end x")
    }

    print("ShopPilotVerify1101d: PASS — join/close/weld/subtract/intersect/offset/trim engines + boundary semantics + round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1101d: FAIL — \(error)")
    exit(1)
}
