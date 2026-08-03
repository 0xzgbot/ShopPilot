import Foundation
import ShopPilotGeometry

/// SPK-1101j verify without XCTest (CLT-only machines).
/// Proves the rotate-selection-90°-around-centroid geometry:
///   1. `selectionCentroid(of:)` is the center of the union bounding box.
///   2. `VectorShape.rotated(byDegrees:around:)` maps every point by the exact
///      90° rotation matrix about the centroid.
///   3. Axis-aligned rectangles swap width/height at 90° (and stay put at 360°).
///   4. Freehand polylines, lines, circles and ellipses rotate exactly.
///   5. Four 90° rotations compose to the identity (within tolerance).

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

    // 2. Exact 90° rotation about the centroid (CCW, y-up model space).
    //    (x, y) → (cx - (y - cy), cy + (x - cx))
    let p = VectorPoint(x: 70, y: 5)  // right of centroid, below it
    let rotatedPoint = VectorShape.line(start: p, end: p)
        .rotated(byDegrees: 90, around: centroid)
    guard case .line(let s, _) = rotatedPoint else { throw VerifyError.failed("line lost type") }
    try expectPoint(s, 70, 45, "point rotated 90° (70,5)→(70,45)")

    // 3. Rectangle: 90° about its own centroid (50,20) swaps width/height and
    //    keeps the centroid fixed; 360° is identity.
    let rectCentroid = selectionCentroid(of: [rect])!   // (50, 20)
    try expectPoint(rectCentroid, 50, 20, "rect own centroid")
    let rotatedRect = rect.rotated(byDegrees: 90, around: rectCentroid)
    guard case .rectangle(let ro, let rw, let rh) = rotatedRect else {
        throw VerifyError.failed("rect at 90° must stay a rectangle")
    }
    try expectClose(rw, 40, "rect width after 90°")
    try expectClose(rh, 100, "rect height after 90°")
    try expectPoint(ro, 30, -30, "rect origin after 90°")
    // The rotated rect's centroid stays fixed at (50, 20).
    let rrCentroid = selectionCentroid(of: [rotatedRect])!
    try expectPoint(rrCentroid, 50, 20, "rect centroid invariant under 90°")

    let identity = rect.rotated(byDegrees: 360, around: rectCentroid)
    guard case .rectangle(let io, let iw, let ih) = identity else {
        throw VerifyError.failed("rect at 360° must stay a rectangle")
    }
    try expectClose(iw, 100, "rect width after 360°")
    try expectClose(ih, 40, "rect height after 360°")
    try expectPoint(io, 0, 0, "rect origin after 360°")

    // 4. Freehand polyline rotates every vertex exactly.
    let poly = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0),
        VectorPoint(x: 100, y: 40), VectorPoint(x: 0, y: 40),
    ])
    let rotatedPoly = poly.rotated(byDegrees: 90, around: centroid)
    guard case .freehand(let rp) = rotatedPoly else { throw VerifyError.failed("freehand lost type") }
    try expect(rp.count == 4, "poly vertex count preserved")
    // (0,0) about (50,25): (50 - (0-25), 25 + (0-50)) = (75, -25)
    try expectPoint(rp[0], 75, -25, "poly vertex 0 rotated")
    // (100,0): (50 - (0-25), 25 + (100-50)) = (75, 75)
    try expectPoint(rp[1], 75, 75, "poly vertex 1 rotated")

    // 5. Circle center rotates, radius preserved.
    let circle = VectorShape.circle(center: VectorPoint(x: 80, y: 30), radius: 12)
    let rotatedCircle = circle.rotated(byDegrees: 90, around: centroid)
    guard case .circle(let cc, let cr) = rotatedCircle else { throw VerifyError.failed("circle lost type") }
    // (80,30) about (50,25): (50 - (30-25), 25 + (80-50)) = (45, 55)
    try expectPoint(cc, 45, 55, "circle center rotated")
    try expectClose(cr, 12, "circle radius preserved")

    // 6. Ellipse rotation adds to its rotation parameter (center + spin).
    let ellipse = VectorShape.ellipse(center: VectorPoint(x: 30, y: 20), radiusX: 10, radiusY: 5, rotation: 0.1)
    let rotatedEllipse = ellipse.rotated(byDegrees: 90, around: centroid)
    guard case .ellipse(let ec, let erx, let ery, let erot) = rotatedEllipse else {
        throw VerifyError.failed("ellipse lost type")
    }
    // (30,20) about (50,25): (50 - (20-25), 25 + (30-50)) = (55, 5)
    try expectPoint(ec, 55, 5, "ellipse center rotated")
    try expectClose(erx, 10, "ellipse rx preserved")
    try expectClose(ery, 5, "ellipse ry preserved")
    try expectClose(erot, 0.1 + .pi / 2, "ellipse rotation += 90°", tolerance: 1e-9)

    // 7. Four 90° rotations compose to identity.
    var shape = poly
    for _ in 0..<4 {
        shape = shape.rotated(byDegrees: 90, around: centroid)
    }
    guard case .freehand(let finalPoints) = shape else { throw VerifyError.failed("freehand lost type after 4×90°") }
    let originalPoints = points(of: poly)
    for (i, fp) in finalPoints.enumerated() {
        try expectClose(fp.x, originalPoints[i].x, "4×90° vertex \(i).x")
        try expectClose(fp.y, originalPoints[i].y, "4×90° vertex \(i).y")
    }

    // 8. Multi-shape selection rotates as a group: relative offsets preserved.
    let group = [rect, line]
    let groupCentroid = selectionCentroid(of: group)!
    let rotatedGroup = group.map { $0.rotated(byDegrees: 90, around: groupCentroid) }
    // The line's midpoint (50,50) → (50 - (50-25), 25 + (50-50)) = (25, 25)
    guard case .line(let ls, let le) = rotatedGroup[1] else { throw VerifyError.failed("group line lost type") }
    let mid = VectorPoint(x: (ls.x + le.x) / 2, y: (ls.y + le.y) / 2)
    try expectPoint(mid, 25, 25, "group line midpoint rotated about group centroid")

    print("SPK-1101j verification: PASS")
    print("  selectionCentroid of rect(0,0,100,40)+line(10..90,50) = (50,25) ✓")
    print("  exact 90° matrix mapping ✓  rect w/h swap 100×40 → 40×100 ✓")
    print("  freehand/circle/ellipse rotate exactly ✓  4×90° = identity ✓")
    print("  multi-shape group rotation about shared centroid ✓")
}

do {
    try main()
} catch {
    fputs("SPK-1101j verification: FAIL — \(error)\n", stderr)
    exit(1)
}
