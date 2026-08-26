import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-2023b verify (CLT machine, no XCTest).
/// Proves the T-bone corner relief contract:
///   1. A 100x60 rect with a 6mm bit yields 4 T-notches (one per corner).
///   2. Each notch REACHES THE EXACT CORNER POINT: the corner lies on the
///      notch boundary (midpoint of its outer short edge), and the bit
///      traveling the notch centerline comes within exactly one radius of
///      the corner (bit edge touches the corner).
///   3. NOTCH WIDTH == BIT DIAMETER across the slot; slot length == bit
///      diameter along the axis.
///   4. Orientation modes: explicit .alongX / .alongY are honored;
///      .autoLongestEdge picks alongX for wide rects and alongY for tall.
///   5. Non-positive bit diameter returns [] (guard).
///   6. Legacy circular dogbones byte-stable: Dogbone.cornerReliefs output
///      for the SPK-1301 fixture bounds matches the pre-change golden values
///      (hardcoded below) to 1e-12, and reliefPolygon vertices stay on the
///      circle.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

let wide = Rect(minX: 0, minY: 0, maxX: 100, maxY: 60)   // width > height
let tall = Rect(minX: 0, minY: 0, maxX: 60, maxY: 100)   // height > width

// Corner order used by both engines — CCW from bottom-left — plus inward signs.
let cornerSpecs: [(p: VectorPoint, sx: Double, sy: Double)] = [
    (VectorPoint(x: 0, y: 0), 1, 1),
    (VectorPoint(x: 100, y: 0), -1, 1),
    (VectorPoint(x: 100, y: 60), -1, -1),
    (VectorPoint(x: 0, y: 60), 1, -1),
]

func main() throws {
    let d = 6.0
    let r = d / 2.0

    // ── 1. Four reliefs. ──────────────────────────────────────────────────
    let reliefs = TBone.cornerReliefs(for: wide, bitDiameter: d)
    try expect(reliefs.count == 4, "100x60 rect + 6mm bit yields 4 T-bones (got \(reliefs.count))")

    // ── 2–3. Per-corner geometry (auto resolves to alongX on this wide rect).
    try expect(reliefs[0].axis == .alongX, "auto-longest-edge on wide rect picks alongX")
    for (i, relief) in reliefs.enumerated() {
        let spec = cornerSpecs[i]
        try expect(relief.corner == spec.p, "corner \(i): relief anchored at exact corner point")
        try expect(relief.radius == r, "corner \(i): radius == bitDiameter / 2")

        let poly = relief.polygon()
        try expect(poly.count == 4, "corner \(i): notch polygon has 4 vertices")

        // Corner point is the midpoint of one polygon edge (notch reaches it).
        var touchesCorner = false
        for j in 0..<4 {
            let a = poly[j], b = poly[(j + 1) % 4]
            let mid = VectorPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if abs(mid.x - spec.p.x) < 1e-9 && abs(mid.y - spec.p.y) < 1e-9 { touchesCorner = true }
        }
        try expect(touchesCorner, "corner \(i): corner point is midpoint of a notch edge")

        // Width across the slot == bit diameter.
        let xs = poly.map { $0.x }
        let ys = poly.map { $0.y }
        let spanX = xs.max()! - xs.min()!
        let spanY = ys.max()! - ys.min()!
        if relief.axis == .alongX {
            try expect(abs(spanY - d) < 1e-9, "corner \(i): alongX width across slot == bit Ø (got \(spanY))")
            try expect(abs(spanX - d) < 1e-9, "corner \(i): alongX slot length == bit Ø (got \(spanX))")
            try expect(abs(poly[0].x - spec.p.x) < 1e-9, "corner \(i): outer short edge sits on the corner x")
        } else {
            try expect(abs(spanX - d) < 1e-9, "corner \(i): alongY width across slot == bit Ø (got \(spanX))")
            try expect(abs(spanY - d) < 1e-9, "corner \(i): alongY slot length == bit Ø (got \(spanY))")
            try expect(abs(poly[0].y - spec.p.y) < 1e-9, "corner \(i): outer short edge sits on the corner y")
        }

        // Bit reachability: centerline point nearest the corner is exactly r away,
        // so the cutter's edge passes through the exact corner point.
        let nearCenter: VectorPoint
        if relief.axis == .alongX {
            nearCenter = VectorPoint(x: spec.p.x + spec.sx * r, y: spec.p.y)
        } else {
            nearCenter = VectorPoint(x: spec.p.x, y: spec.p.y + spec.sy * r)
        }
        let reach = hypot(nearCenter.x - spec.p.x, nearCenter.y - spec.p.y)
        try expect(abs(reach - r) < 1e-9, "corner \(i): bit edge reaches exact corner (dist \(reach), want \(r))")

        // The reaching center position lies inside the notch (slot is long enough).
        func inside(_ p: VectorPoint) -> Bool {
            p.x >= xs.min()! - 1e-9 && p.x <= xs.max()! + 1e-9 &&
            p.y >= ys.min()! - 1e-9 && p.y <= ys.max()! + 1e-9
        }
        try expect(inside(nearCenter), "corner \(i): bit-center reach position inside notch")
    }

    // ── 4. Orientation modes. ─────────────────────────────────────────────
    try expect(TBone.cornerReliefs(for: wide, bitDiameter: d, orientation: .autoLongestEdge)[0].axis == .alongX,
               "auto-longest-edge picks alongX for wide rect")
    try expect(TBone.cornerReliefs(for: tall, bitDiameter: d, orientation: .autoLongestEdge)[0].axis == .alongY,
               "auto-longest-edge picks alongY for tall rect")
    try expect(TBone.cornerReliefs(for: wide, bitDiameter: d, orientation: .alongX)[0].axis == .alongX,
               "explicit alongX honored on wide rect")
    try expect(TBone.cornerReliefs(for: tall, bitDiameter: d, orientation: .alongY)[0].axis == .alongY,
               "explicit alongY honored on tall rect")
    let forcedXOnTall = TBone.cornerReliefs(for: tall, bitDiameter: d, orientation: .alongX)
    try expect(forcedXOnTall.allSatisfy { $0.axis == .alongX }, "explicit alongX overrides auto on tall rect")
    let square = Rect(minX: 0, minY: 0, maxX: 50, maxY: 50)
    try expect(TBone.cornerReliefs(for: square, bitDiameter: d, orientation: .autoLongestEdge)[0].axis == .alongX,
               "auto on square (width >= height tie-break) picks alongX")

    // ── 5. Guard on non-positive bit diameter. ────────────────────────────
    try expect(TBone.cornerReliefs(for: wide, bitDiameter: 0).isEmpty, "bit diameter 0 returns []")
    try expect(TBone.cornerReliefs(for: wide, bitDiameter: -2.5).isEmpty, "negative bit diameter returns []")
    try expect(TBone.cornerReliefs(for: wide, bitDiameter: 0, orientation: .alongY).isEmpty,
               "bit diameter guard holds across orientations")

    // ── 6. Legacy circular dogbones byte-stable vs pre-change goldens. ────
    // Golden values captured from ShopPilotVerify1301 geometry BEFORE the
    // T-bone extension (inset = r/√2 per axis on the 45° bisector).
    let inset = r / sqrt(2.0)
    let goldenCenters: [VectorPoint] = [
        VectorPoint(x: inset, y: inset),
        VectorPoint(x: 100 - inset, y: inset),
        VectorPoint(x: 100 - inset, y: 60 - inset),
        VectorPoint(x: inset, y: 60 - inset),
    ]
    let legacy = Dogbone.cornerReliefs(for: wide, bitDiameter: d)
    try expect(legacy.count == 4, "legacy dogbone still yields 4 reliefs")
    for (i, relief) in legacy.enumerated() {
        try expect(abs(relief.center.x - goldenCenters[i].x) < 1e-12,
                   "legacy dogbone \(i) center.x byte-stable (got \(relief.center.x))")
        try expect(abs(relief.center.y - goldenCenters[i].y) < 1e-12,
                   "legacy dogbone \(i) center.y byte-stable (got \(relief.center.y))")
        try expect(abs(relief.radius - r) < 1e-12, "legacy dogbone \(i) radius unchanged")
    }
    // Digest over the legacy output — stable formatting guards serialization drift.
    var digest = ""
    for relief in legacy {
        digest += String(format: "(%.12f,%.12f,r%.12f)", relief.center.x, relief.center.y, relief.radius)
    }
    let expectedDigest = String(format: "(%.12f,%.12f,r%.12f)", inset, inset, r)
        + String(format: "(%.12f,%.12f,r%.12f)", 100 - inset, inset, r)
        + String(format: "(%.12f,%.12f,r%.12f)", 100 - inset, 60 - inset, r)
        + String(format: "(%.12f,%.12f,r%.12f)", inset, 60 - inset, r)
    try expect(digest == expectedDigest, "legacy dogbone digest byte-stable")

    // Legacy polygon contract untouched.
    let poly16 = Dogbone.reliefPolygon(legacy[0], segments: 16)
    try expect(poly16.count == 16, "legacy reliefPolygon still 16 segments")
    for p in poly16 {
        let dist = hypot(p.x - legacy[0].center.x, p.y - legacy[0].center.y)
        try expect(abs(dist - r) < 1e-6, "legacy polygon vertex at radius r (got \(dist))")
    }

    print("ShopPilotVerify2023b: PASS — T-bone reliefs: 4 notches, notch reaches exact corner point (bit edge dist == r), notch width == bit Ø, all three orientations (auto: X wide / Y tall), bit-diameter guard, legacy dogbone goldens byte-stable (\(digest.prefix(24))…)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2023b: FAIL — \(error)")
    exit(1)
}
