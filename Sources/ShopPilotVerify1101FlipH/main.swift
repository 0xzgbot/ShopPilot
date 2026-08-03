import Foundation
import ShopPilotGeometry

/// SPK-1101 feed verify without XCTest (CLT-only machines).
/// Proves the flip-horizontal (mirror across vertical centerline) geometry:
///   1. `selectionCentroid(of:)` is the center of the union bounding box.
///   2. Point reflection: (x, y) → (2·cx − x, y) about the vertical line x = cx.
///   3. Line endpoints mirror exactly.
///   4. Rectangle: origin moves to the mirrored corner bbox, w/h preserved.
///   5. Circle: center mirrors, radius preserved.
///   6. Arc: center mirrors; angles map θ → π − θ with start/end swapped so the
///      sweep is preserved; every sample point lands on the mirrored arc.
///   7. Ellipse: center mirrors, rotation negates, radii preserved.
///   8. Polygon: center mirrors, rotation negates, radius/sides preserved.
///   9. Star: center mirrors, rotation negates, radii/points preserved.
///  10. Freehand polylines mirror every vertex exactly.
///  11. Group flip about the selection centroid keeps the centroid fixed.
///  12. Flip twice composes to identity (within tolerance).

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

/// Manually mirror a point across the vertical line x = cx.
func manualMirror(_ p: VectorPoint, cx: Double) -> VectorPoint {
    VectorPoint(x: 2 * cx - p.x, y: p.y)
}

func main() throws {
    let cx = 50.0
    let centerline = VectorPoint(x: cx, y: 0)  // y value is ignored by the mirror

    // 1. Selection centroid = union bounding-box center.
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 40)
    let line = VectorShape.line(start: VectorPoint(x: 10, y: 50), end: VectorPoint(x: 90, y: 50))
    let selection = [rect, line]
    guard let centroid = selectionCentroid(of: selection) else {
        throw VerifyError.failed("selectionCentroid returned nil for non-empty selection")
    }
    // Union bbox: x 0...100, y 0...50 → centroid (50, 25).
    try expectPoint(centroid, 50, 25, "union centroid")
    try expect(selectionCentroid(of: []) == nil, "selectionCentroid of empty selection is nil")

    // 2. Point reflection about the vertical centerline.
    let p = VectorPoint(x: 70, y: 5)
    let reflected = VectorShape.line(start: p, end: p).flippedHorizontally(about: centerline)
    guard case .line(let s, _) = reflected else { throw VerifyError.failed("point lost line type") }
    try expectPoint(s, 30, 5, "point reflected (70,5) → (30,5)")

    // 3. Line: both endpoints mirror.
    let mirroredLine = line.flippedHorizontally(about: centerline)
    guard case .line(let ms, let me) = mirroredLine else { throw VerifyError.failed("line lost type") }
    try expectPoint(ms, 90, 50, "line start mirrored")
    try expectPoint(me, 10, 50, "line end mirrored")

    // 4. Rectangle: origin moves to the mirrored corner bbox; w/h preserved.
    let offRect = VectorShape.rectangle(origin: VectorPoint(x: 20, y: 10), width: 40, height: 30)
    let mirroredRect = offRect.flippedHorizontally(about: centerline)
    guard case .rectangle(let ro, let rw, let rh) = mirroredRect else {
        throw VerifyError.failed("rect must stay a rectangle")
    }
    // Original x-span 20...60 → mirrored 40...80; y-span 10...40 unchanged.
    try expectPoint(ro, 40, 10, "rect origin after mirror")
    try expectClose(rw, 40, "rect width preserved")
    try expectClose(rh, 30, "rect height preserved")

    // 5. Circle: center mirrors, radius preserved.
    let circle = VectorShape.circle(center: VectorPoint(x: 80, y: 30), radius: 12)
    let mirroredCircle = circle.flippedHorizontally(about: centerline)
    guard case .circle(let cc, let cr) = mirroredCircle else { throw VerifyError.failed("circle lost type") }
    try expectPoint(cc, 20, 30, "circle center mirrored")
    try expectClose(cr, 12, "circle radius preserved")

    // 6. Arc: center mirrors, angles map θ → π − θ with endpoints swapped.
    let arc = VectorShape.arc(center: VectorPoint(x: 50, y: 20), radius: 10, startAngle: 0.3, endAngle: 1.1)
    let mirroredArc = arc.flippedHorizontally(about: centerline)
    guard case .arc(let ac, let ar, let asa, let aea) = mirroredArc else {
        throw VerifyError.failed("arc lost type")
    }
    try expectPoint(ac, 50, 20, "arc center on centerline stays")
    try expectClose(ar, 10, "arc radius preserved")
    try expectClose(asa, .pi - 1.1, "arc startAngle = π − old end")
    try expectClose(aea, .pi - 0.3, "arc endAngle = π − old start")
    // Sample the original arc's midpoint angle; its mirror must land on the new arc.
    let midTheta = (0.3 + 1.1) / 2
    let sample = VectorPoint(
        x: 50 + 10 * cos(midTheta),
        y: 20 + 10 * sin(midTheta)
    )
    let mirroredSample = manualMirror(sample, cx: 50)
    try expect(mirroredArc.contains(mirroredSample), "mirrored arc contains the mirrored sample point")

    // 7. Ellipse: center mirrors, rotation negates, radii preserved.
    let ellipse = VectorShape.ellipse(center: VectorPoint(x: 30, y: 20), radiusX: 10, radiusY: 5, rotation: 0.7)
    let mirroredEllipse = ellipse.flippedHorizontally(about: centerline)
    guard case .ellipse(let ec, let erx, let ery, let erot) = mirroredEllipse else {
        throw VerifyError.failed("ellipse lost type")
    }
    try expectPoint(ec, 70, 20, "ellipse center mirrored")
    try expectClose(erx, 10, "ellipse rx preserved")
    try expectClose(ery, 5, "ellipse ry preserved")
    try expectClose(erot, -0.7, "ellipse rotation negated")

    // 8. Polygon: center mirrors, rotation negates, radius/sides preserved.
    let polygon = VectorShape.polygon(center: VectorPoint(x: 60, y: 0), radius: 15, sides: 6, rotation: 0.4)
    let mirroredPolygon = polygon.flippedHorizontally(about: centerline)
    guard case .polygon(let pc, let pr, let ps, let prot) = mirroredPolygon else {
        throw VerifyError.failed("polygon lost type")
    }
    try expectPoint(pc, 40, 0, "polygon center mirrored")
    try expectClose(pr, 15, "polygon radius preserved")
    try expect(ps == 6, "polygon sides preserved")
    try expectClose(prot, -0.4, "polygon rotation negated")

    // 9. Star: center mirrors, rotation negates, radii/points preserved.
    let star = VectorShape.star(center: VectorPoint(x: 70, y: 30), outerRadius: 20, innerRadius: 8, points: 5, rotation: 0.9)
    let mirroredStar = star.flippedHorizontally(about: centerline)
    guard case .star(let sc, let sor, let sir, let sp, let srot) = mirroredStar else {
        throw VerifyError.failed("star lost type")
    }
    try expectPoint(sc, 30, 30, "star center mirrored")
    try expectClose(sor, 20, "star outer radius preserved")
    try expectClose(sir, 8, "star inner radius preserved")
    try expect(sp == 5, "star points preserved")
    try expectClose(srot, -0.9, "star rotation negated")

    // 10. Freehand: every vertex mirrors exactly.
    let poly = VectorShape.freehand(points: [
        VectorPoint(x: 10, y: 10), VectorPoint(x: 90, y: 10),
        VectorPoint(x: 90, y: 40), VectorPoint(x: 10, y: 40),
    ])
    let mirroredPoly = poly.flippedHorizontally(about: centerline)
    guard case .freehand(let mp) = mirroredPoly else { throw VerifyError.failed("freehand lost type") }
    try expect(mp.count == 4, "freehand vertex count preserved")
    try expectPoint(mp[0], 90, 10, "poly vertex 0 mirrored")
    try expectPoint(mp[1], 10, 10, "poly vertex 1 mirrored")
    try expectPoint(mp[2], 10, 40, "poly vertex 2 mirrored")
    try expectPoint(mp[3], 90, 40, "poly vertex 3 mirrored")

    // 11. Group flip about the selection centroid keeps the centroid fixed.
    let group = [offRect, circle]
    let groupCentroid = selectionCentroid(of: group)!
    // Union bbox: rect x 20...60 ∪ circle x 68...92 → x 20...92;
    // y 10...42 (rect origin y=10 + height 30, circle center 30 + radius 12).
    // Centroid (56, 26).
    try expectPoint(groupCentroid, 56, 26, "group centroid")
    let flippedGroup = ShapeTransformer().flipHorizontal(shapes: group, about: groupCentroid)
    let flippedCentroid = selectionCentroid(of: flippedGroup)!
    try expectPoint(flippedCentroid, 56, 26, "group centroid invariant under flip")

    // 12. Flip twice composes to identity.
    var shape: VectorShape = poly
    shape = shape.flippedHorizontally(about: centerline)
    shape = shape.flippedHorizontally(about: centerline)
    guard case .freehand(let finalPoints) = shape else { throw VerifyError.failed("freehand lost type after double flip") }
    let originalPoints = [VectorPoint(x: 10, y: 10), VectorPoint(x: 90, y: 10),
                          VectorPoint(x: 90, y: 40), VectorPoint(x: 10, y: 40)]
    for (i, fp) in finalPoints.enumerated() {
        try expectClose(fp.x, originalPoints[i].x, "double-flip vertex \(i).x")
        try expectClose(fp.y, originalPoints[i].y, "double-flip vertex \(i).y")
    }

    print("SPK-1101 flip-horizontal verification: PASS")
    print("  selectionCentroid of rect(0,0,100,40)+line(10..90,50) = (50,25) ✓")
    print("  point (70,5) → (30,5) across x=50 ✓  line/rect/circle/freehand exact ✓")
    print("  arc θ → π−θ, sweep preserved, sample on arc ✓")
    print("  ellipse/polygon/star rotation negated, radii/sides preserved ✓")
    print("  group flip keeps selection centroid fixed ✓  double flip = identity ✓")
}

do {
    try main()
} catch {
    fputs("SPK-1101 flip-horizontal verification: FAIL — \(error)\n", stderr)
    exit(1)
}
