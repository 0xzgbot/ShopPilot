import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1120 verify (CLT machines, no XCTest).
/// Exercises the create-tool geometry bridge: rect/circle/line/polyline
/// factories plus `GeometryBridge` path conversion (closed/open semantics).

typealias P = ShopPilotGeometry.VectorPoint

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // Rect: origin normalized to the min corner; extents always non-negative.
    let r = CreateShapes.rect(from: P(x: 10, y: 20), to: P(x: -5, y: 5))
    guard case .rectangle(let o, let w, let h) = r else {
        throw VerifyError.failed("rect factory returned wrong case")
    }
    try expect(o.x == -5 && o.y == 5, "rect origin normalized: \(o)")
    try expect(w == 15 && h == 15, "rect extents: \(w) x \(h)")
    try expect(r.boundingRect.width == 15 && r.boundingRect.height == 15, "rect bounding rect")

    // Circle: center-anchored drag, radius = distance to rim point.
    let c = CreateShapes.circle(center: P(x: 0, y: 0), through: P(x: 3, y: 4))
    guard case .circle(let cc, let radius) = c else {
        throw VerifyError.failed("circle factory returned wrong case")
    }
    try expect(cc.x == 0 && cc.y == 0, "circle center")
    try expect(abs(radius - 5) < 1e-9, "circle radius from drag: \(radius)")

    // Line: endpoints preserved.
    let l = CreateShapes.line(from: P(x: 1, y: 2), to: P(x: 9, y: 8))
    guard case .line(let s, let e) = l else {
        throw VerifyError.failed("line factory returned wrong case")
    }
    try expect(s.x == 1 && s.y == 2, "line start")
    try expect(e.x == 9 && e.y == 8, "line end")

    // Polyline: vertices preserved.
    let pl = CreateShapes.polyline([
        P(x: 0, y: 0),
        P(x: 5, y: 5),
        P(x: 10, y: 0),
    ])
    guard case .freehand(let pts) = pl else {
        throw VerifyError.failed("polyline factory returned wrong case")
    }
    try expect(pts.count == 3, "polyline vertex count")

    // Bridge: rect closed with 5 sampled points; line open with 2 points.
    let rectPaths = GeometryBridge.toCorePaths([r])
    try expect(rectPaths.count == 1, "bridge rect count")
    try expect(rectPaths.first?.isClosed == true, "bridge rect closed")
    try expect(rectPaths.first?.points.count == 5, "bridge rect 5 points")

    let linePaths = GeometryBridge.toCorePaths([l])
    try expect(linePaths.first?.isClosed == false, "bridge line open")
    try expect(linePaths.first?.points.count == 2, "bridge line 2 points")

    let circlePaths = GeometryBridge.toCorePaths([c])
    try expect(circlePaths.first?.points.count == 49, "bridge circle 49 points")

    // Bridge: open polyline stays open; closed polyline (first == last) closes.
    let openPoints = [
        P(x: 0, y: 0),
        P(x: 5, y: 5),
        P(x: 10, y: 0),
    ]
    let openPaths = GeometryBridge.toCorePaths([CreateShapes.polyline(openPoints)])
    try expect(openPaths.first?.isClosed == false, "open polyline not closed")
    try expect(openPaths.first?.points.count == 3, "open polyline points")

    let closedPoints = openPoints + [P(x: 0, y: 0)]
    let closedPaths = GeometryBridge.toCorePaths([CreateShapes.polyline(closedPoints)])
    try expect(closedPaths.first?.isClosed == true, "closed polyline closes")

    print("SPK-1120 verification: PASS")
    print("  rect/circle/line/polyline factories OK")
    print("  bridge closed/open semantics OK")
    print("  sampled point counts OK")
}

do {
    try main()
} catch {
    fputs("SPK-1120 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
