import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0210 verify (CLT machine, no XCTest).
/// Golden CLTs for OFFSET + BOOLEAN — expectations derived BY HAND from the
/// engine semantics (never captured from the engine), fail on ANY regression:
///   OFFSET (miter-join math, v' = v + d·(n1+n2)/(1+n1·n2)):
///   1. CCW 50×50 square offset +5 → exact corners (−5,−5),(55,−5),(55,55),
///      (−5,55) + explicit closing duplicate (5 points, 1e-9 tolerance).
///   2. `offsetShape` rectangle +5 → rectangle (−5,−5) 60×60.
///   3. Collapse guards: circle r5 offset −10 → []; 50×50 rect inset −25 →
///      [] (miter collapses to a point, zero-area guard trips).
///   BOOLEAN (rect strips / bbox / overlap semantics):
///   4. subtract A(0,0,50,50) − B(20,20,30,30) → exactly 2 strips:
///      (0,0,20,50) + (20,0,30,20) (left strip + bottom strip; right/top are
///      zero-width because B shares the A max edges).
///   5. union → bounding box (0,0,50,50); intersect → overlap (20,20,30,30).
///   6. Disjoint subtract → subject unchanged; covering subtract → empty.
/// The 14-XCTest file presence claim from 2026-07-29 is superseded by this
/// executable proof.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectPoint(_ p: VectorPoint, _ x: Double, _ y: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(p.x - x) > tolerance || abs(p.y - y) > tolerance {
        throw VerifyError.failed("\(msg): expected (\(x), \(y)), got (\(p.x), \(p.y))")
    }
}

/// Extract (originX, originY, width, height) from a rectangle shape.
func rectFields(_ shape: VectorShape) -> (Double, Double, Double, Double)? {
    guard case .rectangle(let origin, let w, let h) = shape else { return nil }
    return (min(origin.x, origin.x + w), min(origin.y, origin.y + h), abs(w), abs(h))
}

func expectRect(_ shape: VectorShape, _ minX: Double, _ minY: Double, _ w: Double, _ h: Double, _ msg: String) throws {
    guard let (gx, gy, gw, gh) = rectFields(shape) else {
        throw VerifyError.failed("\(msg): not a rectangle shape")
    }
    if abs(gx - minX) > 1e-9 || abs(gy - minY) > 1e-9 || abs(gw - w) > 1e-9 || abs(gh - h) > 1e-9 {
        throw VerifyError.failed("\(msg): expected (\(minX), \(minY)) \(w)x\(h), got (\(gx), \(gy)) \(gw)x\(gh)")
    }
}

func main() throws {
    // ── 1. Offset golden: CCW square miter corners. ────────────────────────
    let square: [VectorPoint] = [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
        VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50),
    ]
    let offset = VectorOffsetCalculator.offsetClosedPolyline(points: square, by: 5)
    guard let offset else { throw VerifyError.failed("square offset must succeed") }
    try expect(offset.offsetPath.count == 5, "offset path is 4 corners + explicit closing duplicate (got \(offset.offsetPath.count))")
    try expectPoint(offset.offsetPath[0], -5, -5, "corner 0 (bottom-left) mitered outward")
    try expectPoint(offset.offsetPath[1], 55, -5, "corner 1 (bottom-right) mitered outward")
    try expectPoint(offset.offsetPath[2], 55, 55, "corner 2 (top-right) mitered outward")
    try expectPoint(offset.offsetPath[3], -5, 55, "corner 3 (top-left) mitered outward")
    try expectPoint(offset.offsetPath[4], -5, -5, "closing duplicate")

    // ── 2. Shape dispatcher: rectangle offset → expanded rect. ─────────────
    let expanded = VectorOffsetCalculator.offsetShape(
        .rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50),
        by: 5
    )
    try expect(expanded.count == 1, "rect offset yields one shape")
    try expectRect(expanded[0], -5, -5, 60, 60, "rect offset +5 expands to 60x60 at (-5,-5)")

    // ── 3. Collapse guards. ────────────────────────────────────────────────
    let collapsedCircle = VectorOffsetCalculator.offsetShape(
        .circle(center: VectorPoint(x: 0, y: 0), radius: 5),
        by: -10
    )
    try expect(collapsedCircle.isEmpty, "circle offset past its radius collapses to nothing")

    let collapsedRect = VectorOffsetCalculator.offsetShape(
        .rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50),
        by: -25
    )
    try expect(collapsedRect.isEmpty, "rect inset to zero area collapses to nothing")

    // ── 4. Boolean golden: subtract strips. ────────────────────────────────
    let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50)
    let b = VectorShape.rectangle(origin: VectorPoint(x: 20, y: 20), width: 30, height: 30)
    let diff = BooleanOps.subtract(a, b)
    try expect(diff.polygons.count == 2, "A-B decomposes into exactly 2 strips (got \(diff.polygons.count))")
    let stripFields = diff.polygons.compactMap(rectFields).sorted { ($0.0, $0.1) < ($1.0, $1.1) }
    try expect(stripFields.count == 2, "both strips are rectangles")
    try expectRect(diff.polygons[0], 0, 0, 20, 50, "left strip (0,0)-(20,50)")
    try expectRect(diff.polygons[1], 20, 0, 30, 20, "bottom strip (20,0)-(50,20)")

    // ── 5. Union / intersect goldens. ──────────────────────────────────────
    let union = BooleanOps.union(a, b)
    try expect(union.polygons.count == 1, "union yields one rect")
    try expectRect(union.polygons[0], 0, 0, 50, 50, "union bounding box")

    let intersection = BooleanOps.intersect(a, b)
    try expect(intersection.polygons.count == 1, "intersect yields one rect")
    try expectRect(intersection.polygons[0], 20, 20, 30, 30, "overlap region")

    // ── 6. Disjoint / covering subtract. ───────────────────────────────────
    let far = VectorShape.rectangle(origin: VectorPoint(x: 100, y: 100), width: 10, height: 10)
    let disjoint = BooleanOps.subtract(a, far)
    try expect(disjoint.polygons.count == 1 && disjoint.polygons[0] == a,
               "disjoint subtract returns the subject unchanged")

    let covering = VectorShape.rectangle(origin: VectorPoint(x: -10, y: -10), width: 100, height: 100)
    let emptied = BooleanOps.subtract(a, covering)
    try expect(emptied.polygons.isEmpty, "covering subtract empties the subject")

    print("ShopPilotVerify0210: PASS — hand-derived offset goldens (miter corners, rect expand, collapse guards) + boolean goldens (subtract strips, union bbox, intersect overlap, disjoint/covering)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0210: FAIL — \(error)")
    exit(1)
}
