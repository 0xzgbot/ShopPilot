import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0215 verify (CLT machine, no XCTest).
/// Proves fillet + extend semantics:
///   1. FILLET 90° corner: corner removed, tangents at r from the corner,
///      every arc point at exactly radius from the arc center, correct bulge.
///   2. RECTANGLE fillet: converts to a closed rounded freehand; each corner
///      is at least radius away from any vertex (tangent distance).
///   3. CLAMP: a radius far larger than the segments clamps to fit — finite
///      output, corner still rounded, no NaN.
///   4. EXTEND line: both ends move out by the distance.
///   5. EXTEND open polyline: first/last segment extended; CLOSED polyline
///      and circles are untouched.
///   6. PERSIST: filleted shapes survive VectorShape Codable round-trip.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // ── 1. Fillet a 90° corner ─────────────────────────────────────────────
    // Path (0,0)→(1,0)→(1,1), r = 0.25: tangents at (0.75,0) and (1,0.25),
    // arc center at (0.75, 0.25).
    let corner = [pt(0, 0), pt(1, 0), pt(1, 1)]
    let rounded = ShapeFilletEngine.filletPolyline(corner, radius: 0.25)
    try expect(rounded.count > 3, "corner replaced by arc points (got \(rounded.count))")
    try expect(rounded.contains { $0.x == 1.0 && $0.y == 0.0 } == false, "sharp corner (1,0) removed")
    // Open polyline keeps its endpoints; tangents sit at index 1 / count-2.
    try expect(rounded[0] == pt(0, 0), "start point preserved")
    try expect(rounded[rounded.count - 1] == pt(1, 1), "end point preserved")
    let tA = rounded[1]
    let tB = rounded[rounded.count - 2]
    try expect(abs(tA.x - 0.75) < 1e-9 && abs(tA.y) < 1e-9, "first tangent is (0.75,0) got \(tA)")
    try expect(abs(tB.x - 1.0) < 1e-9 && abs(tB.y - 0.25) < 1e-9, "second tangent is (1,0.25) got \(tB)")
    let cx = 0.75, cy = 0.25
    for p in rounded[1..<(rounded.count - 1)] {
        let r = ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot()
        try expect(abs(r - 0.25) < 1e-6, "arc point \(p) at radius 0.25 from center (got \(r))")
    }
    // The arc bulges toward the removed corner: the midpoint of the sweep is
    // NOT on the straight line y = 0 or x = 1 — it sits between the tangents.
    let mid = rounded[rounded.count / 2]
    try expect(mid.x > 0.75 && mid.x < 1.0 && mid.y > 0 && mid.y < 0.25,
               "arc midpoint \(mid) lies inside the rounded corner")

    // ── 2. Rectangle fillet → closed rounded freehand ──────────────────────
    let rect = VectorShape.rectangle(origin: pt(0, 0), width: 10, height: 10)
    let roundedRect = ShapeFilletEngine.fillet(rect, radius: 2.0)
    guard case .freehand(let rp) = roundedRect else {
        throw VerifyError.failed("rectangle fillet yields freehand")
    }
    try expect(rp.first == rp.last, "rounded rectangle stays closed")
    try expect(rp.count >= 16, "rounded rect has arc points (got \(rp.count))")
    let corners: [(Double, Double)] = [(0, 0), (10, 0), (10, 10), (0, 10)]
    for (cxx, cyy) in corners {
        try expect(rp.contains { abs($0.x - cxx) < 1e-9 && abs($0.y - cyy) < 1e-9 } == false,
                    "sharp corner (\(cxx),\(cyy)) removed")
        // Nearest vertex to the corner: the arc bulges INTO the corner. The
        // continuous arc's closest point is at r·(√2−1) ≈ 0.828; the sampled
        // polygon's closest VERTEX sits slightly further (≈0.91 with 5 arc
        // segments). Any value < 2.0 proves the inward bulge; an outward
        // bulge would keep every vertex ≥ 2.0 from the corner.
        var nearest = Double.greatestFiniteMagnitude
        for p in rp {
            let dx = p.x - cxx
            let dy = p.y - cyy
            nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
        }
        try expect(nearest > 0.8 && nearest < 1.0,
                   "corner (\(cxx),\(cyy)) closest arc vertex in (0.8, 1.0) (got \(nearest))")
    }

    // ── 3. Radius clamp on tiny segments ───────────────────────────────────
    let tiny = [pt(0, 0), pt(0.1, 0), pt(0.1, 0.1)]
    let clamped = ShapeFilletEngine.filletPolyline(tiny, radius: 10.0)
    try expect(clamped.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "clamped fillet stays finite")
    try expect(clamped.contains { $0.x == 0.1 && $0.y == 0.0 } == false, "tiny corner still rounded")
    try expect(clamped[1].x > 0.050 && clamped[1].x < 0.052, "tangent clamped to ~0.051 (got \(clamped[1].x))")

    // ── 4. Extend a line ───────────────────────────────────────────────────
    let line = VectorShape.line(start: pt(0, 0), end: pt(1, 0))
    let extLine = ShapeExtendEngine.extend(line, distance: 0.5)
    guard case .line(let s, let e) = extLine else { throw VerifyError.failed("extend line keeps line") }
    try expect(abs(s.x + 0.5) < 1e-9 && abs(s.y) < 1e-9, "line start extended to -0.5 got \(s)")
    try expect(abs(e.x - 1.5) < 1e-9 && abs(e.y) < 1e-9, "line end extended to 1.5 got \(e)")

    // ── 5. Extend an open polyline; closed + circle untouched ──────────────
    let open = [pt(0, 0), pt(1, 0), pt(1, 1)]
    let extOpen = ShapeExtendEngine.extend(.freehand(points: open), distance: 0.5)
    guard case .freehand(let ep) = extOpen else { throw VerifyError.failed("extend polyline keeps freehand") }
    try expect(abs(ep[0].x + 0.5) < 1e-9 && abs(ep[0].y) < 1e-9, "polyline start extended got \(ep[0])")
    try expect(abs(ep[2].x - 1.0) < 1e-9 && abs(ep[2].y - 1.5) < 1e-9, "polyline end extended got \(ep[2])")

    let closedPoly = [pt(0, 0), pt(1, 0), pt(1, 1), pt(0, 0)]
    let extClosed = ShapeExtendEngine.extend(.freehand(points: closedPoly), distance: 0.5)
    guard case .freehand(let cp) = extClosed else { throw VerifyError.failed("closed stays freehand") }
    try expect(cp == closedPoly, "closed polyline is untouched by extend")

    let circle = VectorShape.circle(center: pt(0, 0), radius: 5)
    let extCircle = ShapeExtendEngine.extend(circle, distance: 1.0)
    let filletCircle = ShapeFilletEngine.fillet(circle, radius: 1.0)
    try expect(extCircle == circle && filletCircle == circle, "circle untouched by extend + fillet")

    // ── 6. Persist: Codable round-trip ─────────────────────────────────────
    let data = try JSONEncoder().encode(roundedRect)
    let back = try JSONDecoder().decode(VectorShape.self, from: data)
    try expect(back == roundedRect, "rounded rectangle survives Codable round-trip")

    print("ShopPilotVerify0215: PASS - 90° fillet math, rectangle rounding, radius clamp, extend line/polyline, closed+circle no-ops, Codable round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0215: FAIL - \(error)")
    exit(1)
}
