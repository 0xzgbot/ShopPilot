import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1301 verify (CLT machine, no XCTest).
/// Proves the dogbone corner relief engine contract:
///   1. A 100x60 rect with a 6mm bit yields 4 reliefs (one per corner).
///   2. Each relief center sits on the 45° inward bisector: per-axis offset
///      from the corner is exactly r/√2 (r = 3, within 1e-6).
///   3. Each relief circle passes through its corner: distance(center, corner)
///      == radius within 1e-6.
///   4. Every relief center is inside the pocket bounds (inset r/√2 from each
///      edge).
///   5. Non-positive bit diameter returns [] (guard).
///   6. reliefPolygon returns `segments` points, each at distance `radius`
///      from the center (within 1e-6).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let r = 3.0
    let inset = r / sqrt(2.0)
    let bounds = Rect(minX: 0, minY: 0, maxX: 100, maxY: 60)

    // ── 1. Four reliefs. ──────────────────────────────────────────────────
    let reliefs = Dogbone.cornerReliefs(for: bounds, bitDiameter: 6.0)
    try expect(reliefs.count == 4, "100x60 rect + 6mm bit yields 4 reliefs (got \(reliefs.count))")

    // ── 2–4. Per-corner geometry. ─────────────────────────────────────────
    let corners: [VectorPoint] = [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 100, y: 0),
        VectorPoint(x: 100, y: 60),
        VectorPoint(x: 0, y: 60),
    ]
    try expect(reliefs.count == corners.count, "one relief per corner")
    for (i, relief) in reliefs.enumerated() {
        let corner = corners[i]

        // 2. Bisector placement: per-axis offset magnitude == r/√2.
        let dx = relief.center.x - corner.x
        let dy = relief.center.y - corner.y
        try expect(abs(abs(dx) - inset) < 1e-6,
                   "corner \(i): x-offset == r/√2 (got \(dx), want ±\(inset))")
        try expect(abs(abs(dy) - inset) < 1e-6,
                   "corner \(i): y-offset == r/√2 (got \(dy), want ±\(inset))")

        // 3. Circle passes through the corner.
        let dist = hypot(dx, dy)
        try expect(abs(dist - r) < 1e-6,
                   "corner \(i): circle passes through corner (dist \(dist), want \(r))")

        // 4. Center inside the pocket bounds, inset r/√2 from each edge.
        try expect(relief.center.x >= bounds.minX + inset - 1e-6
                       && relief.center.x <= bounds.maxX - inset + 1e-6,
                   "corner \(i): center x in-bounds (got \(relief.center.x))")
        try expect(relief.center.y >= bounds.minY + inset - 1e-6
                       && relief.center.y <= bounds.maxY - inset + 1e-6,
                   "corner \(i): center y in-bounds (got \(relief.center.y))")
    }

    // ── 5. Guard on non-positive bit diameter. ────────────────────────────
    try expect(Dogbone.cornerReliefs(for: bounds, bitDiameter: 0).isEmpty,
               "bit diameter 0 returns []")
    try expect(Dogbone.cornerReliefs(for: bounds, bitDiameter: -2.5).isEmpty,
               "negative bit diameter returns []")

    // ── 6. reliefPolygon. ─────────────────────────────────────────────────
    let poly16 = Dogbone.reliefPolygon(reliefs[0], segments: 16)
    try expect(poly16.count == 16, "16-segment polygon (got \(poly16.count))")
    for p in poly16 {
        let d = hypot(p.x - reliefs[0].center.x, p.y - reliefs[0].center.y)
        try expect(abs(d - r) < 1e-6, "polygon vertex at radius r (got \(d))")
    }
    let poly32 = Dogbone.reliefPolygon(reliefs[1], segments: 32)
    try expect(poly32.count == 32, "32-segment polygon (got \(poly32.count))")

    print("ShopPilotVerify1301: PASS — dogbone corner relief: 4 reliefs, center on 45° bisector at r/√2 per axis, circle through corner, centers in-bounds, bit-diameter guard, polygon vertices at radius")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1301: FAIL — \(error)")
    exit(1)
}
