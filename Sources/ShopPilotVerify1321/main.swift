import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1321 verify (CLT machine, no XCTest).
/// Proves the VECTOR BOUNDARY contract (parity item C17):
///   1. SAMPLING: 2 rectangles → dense point cloud (> 40 points).
///   2. CONVEX HULL: 4-corner rect cloud → exactly 4 hull points, CCW
///      (positive signed shoelace), bounding box matches the rect,
///      duplicates removed.
///   3. MULTI-SHAPE: two separated squares → one 4-point hull spanning both
///      (minX 0 … maxX 30).
///   4. OFFSET: +2 grows the boundary area, −2 shrinks it, 0 matches the
///      un-offset hull within 1e-6.
///   5. AREA: 10×10 square hull ≈ 100; empty shapes → [] with area 0.
///   6. DEGENERATE: < 3 points pass through unchanged (no crash).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance {
        throw VerifyError.failed("\(msg) (got \(a), expected \(b) ± \(tolerance))")
    }
}

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> VectorShape {
    .rectangle(origin: VectorPoint(x: x, y: y), width: w, height: h)
}

/// Signed shoelace — positive ⇒ counter-clockwise winding.
func signedShoelace(_ pts: [VectorPoint]) -> Double {
    guard pts.count >= 3 else { return 0 }
    var sum = 0.0
    for i in 0..<pts.count {
        let a = pts[i]
        let b = pts[(i + 1) % pts.count]
        sum += a.x * b.y - b.x * a.y
    }
    return sum / 2.0
}

func main() throws {
    // ── 1. Dense sampling. ───────────────────────────────────────────────
    let twoRects = [rect(0, 0, 10, 10), rect(20, 0, 10, 10)]
    let cloud = VectorBoundary.points(from: twoRects)
    try expect(cloud.count > 40, "2 rectangles sample to > 40 points (got \(cloud.count))")

    // ── 2. Convex hull of one rect: 4 corners, CCW, bbox matches. ────────
    let oneRect = [rect(0, 0, 10, 10)]
    let oneCloud = VectorBoundary.points(from: oneRect)
    let hull = VectorBoundary.convexHull(oneCloud)
    try expect(hull.count == 4, "rect hull = exactly 4 points (got \(hull.count))")
    try expect(signedShoelace(hull) > 0, "rect hull is CCW (positive signed shoelace)")
    try expect(VectorBoundary.area(hull) > 0, "rect hull area is positive")
    let xs = hull.map(\.x)
    let ys = hull.map(\.y)
    try expect(xs.min()! == 0 && xs.max()! == 10 && ys.min()! == 0 && ys.max()! == 10,
               "rect hull bounding box = (0,0)–(10,10)")

    // Duplicates removed: a cloud with repeated corners still yields 4.
    let dupeCloud = oneCloud + oneCloud
    try expect(VectorBoundary.convexHull(dupeCloud).count == 4,
               "duplicate cloud hull = 4 points (duplicates removed)")

    // ── 3. Two separated squares → one hull spanning both. ───────────────
    let bothHull = VectorBoundary.convexHull(cloud)
    try expect(bothHull.count == 4, "two squares → 4-point hull (got \(bothHull.count))")
    let bx = bothHull.map(\.x)
    try expect(bx.min()! == 0 && bx.max()! == 30, "hull spans minX 0 → maxX 30")

    // ── 4. Boundary path offset. ─────────────────────────────────────────
    let base = VectorBoundary.boundaryPath(for: oneRect, offsetMm: 0)
    let areaBase = VectorBoundary.area(base)
    try expectClose(areaBase, VectorBoundary.area(hull), "offset 0 == un-offset hull area")

    let out2 = VectorBoundary.boundaryPath(for: oneRect, offsetMm: 2)
    try expect(VectorBoundary.area(out2) > areaBase, "offset +2 grows the boundary area")

    let in2 = VectorBoundary.boundaryPath(for: oneRect, offsetMm: -2)
    try expect(VectorBoundary.area(in2) < areaBase, "offset −2 shrinks the boundary area")

    // ── 5. Area + empty shapes. ──────────────────────────────────────────
    try expectClose(VectorBoundary.area(hull), 100.0, "10×10 hull area ≈ 100")
    try expect(VectorBoundary.boundaryPath(for: []).isEmpty, "empty shapes → empty boundary path")
    try expect(VectorBoundary.points(from: []).isEmpty, "empty shapes → empty point cloud")
    try expect(VectorBoundary.area([]) == 0, "area of empty polygon = 0")

    // ── 6. Degenerate: < 3 points pass through unchanged (no crash). ─────
    let two = [VectorPoint(x: 1, y: 2), VectorPoint(x: 3, y: 4)]
    let twoHull = VectorBoundary.convexHull(two)
    try expect(twoHull.count == 2, "2 points pass through unchanged")
    try expect(twoHull.first == two.first, "2-point hull preserves points as-is")
    try expect(VectorBoundary.convexHull([VectorPoint(x: 5, y: 6)]).count == 1,
               "1 point passes through unchanged")
    try expect(VectorBoundary.convexHull([]).isEmpty, "empty hull = empty")

    print("ShopPilotVerify1321: PASS — dense sampling, CCW convex hull (dedupe, bbox, multi-shape span), centroid-ray offset (+2 grows / −2 shrinks / 0 identical), shoelace area ≈ 100, empty + degenerate pass-through")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1321: FAIL — \(error)")
    exit(1)
}
