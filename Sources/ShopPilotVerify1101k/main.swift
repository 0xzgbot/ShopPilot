import Foundation
import ShopPilotGeometry

/// SPK-1101k verify without XCTest (CLT-only machines).
/// Proves the scale-selection-1.1×-about-centroid geometry:
///   1. `selectionCentroid(of:)` is the center of the union bounding box.
///   2. `VectorShape.scaled(by:about:)` maps every point by the exact 1.1×
///      uniform scale about the centroid; the centroid itself stays fixed.
///   3. Axis-aligned rectangles keep their shape: origin moves, w/h × 1.1.
///   4. Circles/ellipses scale radii by 1.1; rotation parameters preserved.
///   5. Freehand polylines scale every vertex exactly.
///   6. Multi-shape selection scales as a group about the shared centroid.
///   7. Scale by 1.1 then by 1/1.1 composes to identity (within tolerance).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func expectPoint(_ p: VectorPoint, _ x: Double, _ y: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    try expectClose(p.x, x, "\(msg).x", tolerance: tolerance)
    try expectClose(p.y, y, "\(msg).y", tolerance: tolerance)
}

// MARK: - Helpers

func points(of shape: VectorShape) -> [VectorPoint] {
    switch shape {
    case .line(let s, let e): return [s, e]
    case .circle(let c, _): return [c]
    case .rectangle(let o, let w, let h):
        return [o, VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h), VectorPoint(x: o.x, y: o.y + h)]
    case .arc(let c, _, _, _): return [c]
    case .ellipse(let c, _, _, _): return [c]
    case .polygon(let c, _, _, _): return [c]
    case .star(let c, _, _, _, _): return [c]
    case .freehand(let pts): return pts
    }
}

func main() throws {
    // 1. Selection centroid = union bounding-box center.
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 40)
    let line = VectorShape.line(start: VectorPoint(x: 10, y: 50), end: VectorPoint(x: 90, y: 50))
    let selection = [rect, line]
    guard let centroid = selectionCentroid(of: selection) else {
        throw VerifyError.failed("selectionCentroid returned nil for non-empty selection")
    }
    // Union bbox: x 0...100, y 0...50 → centroid (50, 25).
    try expectPoint(centroid, 50, 25, "union centroid")

    // 2. Exact 1.1× uniform scale about the centroid.
    //    (x, y) → (cx + (x - cx)·1.1, cy + (y - cy)·1.1)
    let p = VectorPoint(x: 70, y: 5)  // right of centroid, below it
    let scaledPoint = VectorShape.line(start: p, end: p)
        .scaled(by: 1.1, about: centroid)
    guard case .line(let s, _) = scaledPoint else { throw VerifyError.failed("line lost type") }
    // (70,5): (50 + 20·1.1, 25 + (-20)·1.1) = (72, 3)
    try expectPoint(s, 72, 3, "point scaled 1.1× (70,5)→(72,3)")

    // 3. Rectangle: 1.1× about its own centroid (50,20) scales w/h by 1.1 and
    //    keeps the centroid fixed; the origin moves along the ray.
    let rectCentroid = selectionCentroid(of: [rect])!   // (50, 20)
    try expectPoint(rectCentroid, 50, 20, "rect own centroid")
    let scaledRect = rect.scaled(by: 1.1, about: rectCentroid)
    guard case .rectangle(let so, let sw, let sh) = scaledRect else {
        throw VerifyError.failed("rect scaled uniformly must stay a rectangle")
    }
    try expectClose(sw, 110, "rect width after 1.1×")
    try expectClose(sh, 44, "rect height after 1.1×")
    // Origin (0,0): (50 + (-50)·1.1, 20 + (-20)·1.1) = (-5, -2)
    try expectPoint(so, -5, -2, "rect origin after 1.1×")
    // The scaled rect's centroid stays fixed at (50, 20).
    let srCentroid = selectionCentroid(of: [scaledRect])!
    try expectPoint(srCentroid, 50, 20, "rect centroid invariant under uniform scale")

    // 4. Circle: center moves, radius × 1.1.
    let circle = VectorShape.circle(center: VectorPoint(x: 80, y: 30), radius: 12)
    let scaledCircle = circle.scaled(by: 1.1, about: centroid)
    guard case .circle(let cc, let cr) = scaledCircle else { throw VerifyError.failed("circle lost type") }
    // (80,30) about (50,25): (50 + 30·1.1, 25 + 5·1.1) = (83, 30.5)
    try expectPoint(cc, 83, 30.5, "circle center scaled")
    try expectClose(cr, 13.2, "circle radius × 1.1")

    // 5. Ellipse: center moves, radii × 1.1, rotation parameter preserved.
    let ellipse = VectorShape.ellipse(center: VectorPoint(x: 30, y: 20), radiusX: 10, radiusY: 5, rotation: 0.7)
    let scaledEllipse = ellipse.scaled(by: 1.1, about: centroid)
    guard case .ellipse(let ec, let erx, let ery, let erot) = scaledEllipse else {
        throw VerifyError.failed("ellipse lost type")
    }
    // (30,20) about (50,25): (50 + (-20)·1.1, 25 + (-5)·1.1) = (28, 19.5)
    try expectPoint(ec, 28, 19.5, "ellipse center scaled")
    try expectClose(erx, 11, "ellipse rx × 1.1")
    try expectClose(ery, 5.5, "ellipse ry × 1.1")
    try expectClose(erot, 0.7, "ellipse rotation preserved")

    // 6. Freehand polyline scales every vertex exactly.
    let poly = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0),
        VectorPoint(x: 100, y: 40), VectorPoint(x: 0, y: 40),
    ])
    let scaledPoly = poly.scaled(by: 1.1, about: centroid)
    guard case .freehand(let sp) = scaledPoly else { throw VerifyError.failed("freehand lost type") }
    try expect(sp.count == 4, "poly vertex count preserved")
    // (0,0) about (50,25): (50 - 50·1.1, 25 - 25·1.1) = (-5, -2.5)
    try expectPoint(sp[0], -5, -2.5, "poly vertex 0 scaled")
    // (100,0): (50 + 50·1.1, 25 - 25·1.1) = (105, -2.5)
    try expectPoint(sp[1], 105, -2.5, "poly vertex 1 scaled")

    // 7. Multi-shape selection scales as a group: relative offsets preserved.
    let group = [rect, line]
    let groupCentroid = selectionCentroid(of: group)!   // (50, 25)
    let scaledGroup = ShapeTransformer().scale(shapes: group, factor: 1.1, about: groupCentroid)
    // The line's midpoint (50,50) stays on the vertical ray: (50, 25 + 25·1.1) = (50, 52.5)
    guard case .line(let ls, let le) = scaledGroup[1] else { throw VerifyError.failed("group line lost type") }
    let mid = VectorPoint(x: (ls.x + le.x) / 2, y: (ls.y + le.y) / 2)
    try expectPoint(mid, 50, 52.5, "group line midpoint scaled about group centroid")

    // 8. Scale by 1.1 then by 1/1.1 composes to identity.
    var shape = poly
    shape = shape.scaled(by: 1.1, about: centroid)
    shape = shape.scaled(by: 1.0 / 1.1, about: centroid)
    guard case .freehand(let finalPoints) = shape else { throw VerifyError.failed("freehand lost type after round-trip") }
    let originalPoints = points(of: poly)
    for (i, fp) in finalPoints.enumerated() {
        try expectClose(fp.x, originalPoints[i].x, "round-trip vertex \(i).x", tolerance: 1e-9)
        try expectClose(fp.y, originalPoints[i].y, "round-trip vertex \(i).y", tolerance: 1e-9)
    }

    print("SPK-1101k verification: PASS")
    print("  selectionCentroid of rect(0,0,100,40)+line(10..90,50) = (50,25) ✓")
    print("  exact 1.1× matrix mapping ✓  rect 100×40 → 110×44, centroid fixed ✓")
    print("  circle r 12→13.2 ✓  ellipse rx/ry ×1.1, rotation kept ✓")
    print("  freehand every vertex ×1.1 ✓  group scale about shared centroid ✓")
    print("  1.1× then ÷1.1 = identity ✓")
}

do {
    try main()
} catch {
    fputs("SPK-1101k verification: FAIL — \(error)\n", stderr)
    exit(1)
}
