import Foundation
import ShopPilotCore

// SPK-2010a — Medial axis + V-carve depth geometry verification.
// Port of the sibling's VCarveMedialAxisTests dumbbell fixture (semantics only).

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

// MARK: - Dumbbell fixture (matches the family reference exactly)

func dumbbell() -> [VectorPoint] {
    var pts: [VectorPoint] = []
    let r = 30.0, neckHalf = 6.0
    let leftC = 40.0, rightC = 160.0, cy = 100.0

    // Lower edge: left bulb bottom, neck bottom, right bulb bottom.
    for i in 0...24 {
        let a = Double.pi + Double(i) / 24.0 * (Double.pi / 2 + Double.pi / 6)
        pts.append(VectorPoint(x: leftC + cos(a) * r, y: cy + sin(a) * r))
    }
    pts.append(VectorPoint(x: leftC + 20, y: cy - neckHalf))
    pts.append(VectorPoint(x: rightC - 20, y: cy - neckHalf))
    for i in 0...24 {
        let a = -Double.pi / 3 + Double(i) / 24.0 * (Double.pi / 3 + Double.pi / 2 + Double.pi / 3)
        pts.append(VectorPoint(x: rightC + cos(a) * r, y: cy + sin(a) * r))
    }
    pts.append(VectorPoint(x: rightC - 20, y: cy + neckHalf))
    pts.append(VectorPoint(x: leftC + 20, y: cy + neckHalf))
    for i in 0...24 {
        let a = 2 * Double.pi / 3 + Double(i) / 24.0 * (Double.pi / 3)
        pts.append(VectorPoint(x: leftC + cos(a) * r, y: cy + sin(a) * r))
    }
    return pts
}

// MARK: - AC checks

func main() throws {
    // AC1 — circle r=40, 72 segments, cell 1.0 → non-empty skeleton,
    // max clearance within 3 mm of 40.
    var circle: [VectorPoint] = []
    for i in 0..<72 {
        let a = Double(i) / 72.0 * 2 * .pi
        circle.append(VectorPoint(x: 100 + cos(a) * 40, y: 100 + sin(a) * 40))
    }
    let circleResult = MedialAxis.compute(outline: circle, cellMm: 1.0)
    try expect(!circleResult.isEmpty, "circle skeleton should be non-empty")
    try expect(abs(circleResult.maxClearanceMm - 40.0) <= 3.0,
               "circle max clearance \(circleResult.maxClearanceMm) should be within 3 mm of 40")

    // The skeleton's deepest ridge point should sit near the centre.
    if let deepest = circleResult.paths.first?.max(by: { $0.clearanceMm < $1.clearanceMm }) {
        try expect(abs(deepest.position.x - 100) < 5 && abs(deepest.position.y - 100) < 5,
                   "deepest circle ridge point near centre, got \(deepest.position)")
    } else {
        throw VerifyError.failed("circle skeleton has no first path")
    }

    // AC2 — 200×20 mm rectangle slot → longest ridge spans X much more than Y.
    let slot = [
        VectorPoint(x: 10, y: 10), VectorPoint(x: 210, y: 10),
        VectorPoint(x: 210, y: 30), VectorPoint(x: 10, y: 30),
    ]
    let slotResult = MedialAxis.compute(outline: slot, cellMm: 1.0)
    try expect(!slotResult.isEmpty, "slot skeleton should be non-empty")
    guard let spine = slotResult.paths.first else {
        throw VerifyError.failed("slot skeleton has no path")
    }
    var sxMin = Double.infinity, sxMax = -Double.infinity
    var syMin = Double.infinity, syMax = -Double.infinity
    for p in spine {
        sxMin = min(sxMin, p.position.x); sxMax = max(sxMax, p.position.x)
        syMin = min(syMin, p.position.y); syMax = max(syMax, p.position.y)
    }
    let w = sxMax - sxMin, h = syMax - syMin
    try expect(w > h * 3.0, "slot spine width \(w) must exceed height*3 (\(h * 3))")
    try expect(abs(slotResult.maxClearanceMm - 10.0) <= 1.5,
               "slot half-width ~10, got \(slotResult.maxClearanceMm)")

    // AC3 — depthForHalfWidth: 90° bit at half-width 10, maxDepth 50 → −10.
    let z90 = VCarveGeometry.depthForHalfWidth(10, angle: 90, maxDepth: 50)
    try expect(abs(z90 - (-10.0)) < 1e-9, "depthForHalfWidth(10, 90°, 50) = \(z90), want −10")

    // Narrower bit (30°) carves DEEPER (more negative) at the same width.
    let z30 = VCarveGeometry.depthForHalfWidth(10, angle: 30, maxDepth: 50)
    try expect(z30 < z90, "30° depth \(z30) must be deeper than 90° depth \(z90)")

    // Huge width clamps to -maxDepth.
    let zClamp = VCarveGeometry.depthForHalfWidth(1000, angle: 90, maxDepth: 12)
    try expect(abs(zClamp - (-12.0)) < 1e-9, "clamp expected -12, got \(zClamp)")

    // Zero/negative width → zero depth.
    try expect(VCarveGeometry.depthForHalfWidth(0, angle: 90, maxDepth: 50) == 0,
               "zero width → zero depth")

    // DistanceToNearestOtherEdge sanity on a 20 mm-wide open slot polyline:
    // a vertex on the top wall is 20 mm from the bottom wall (its own two
    // segments are skipped).
    let openSlot = VectorPath(
        name: "slot",
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 200, y: 0),
            VectorPoint(x: 200, y: 20), VectorPoint(x: 0, y: 20),
        ],
        isClosed: false
    )
    let d = VCarveGeometry.distanceToNearestOtherEdge(
        openSlot, index: 1, allVectors: [openSlot])
    try expect(abs(d - 20.0) < 1e-6, "other-edge distance at corner vertex = \(d), want 20")

    // AC4 — degenerate outline (<3 points) → empty skeleton.
    let degenerate = MedialAxis.compute(
        outline: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0)], cellMm: 1.0)
    try expect(degenerate.isEmpty, "degenerate outline must yield an empty skeleton")
    try expect(degenerate.maxClearanceMm == 0, "degenerate outline clearance must be 0")

    // AC4b — every ridge point of the dumbbell fixture lies inside the polygon.
    let db = dumbbell()
    let dbResult = MedialAxis.compute(outline: db, cellMm: 1.5)
    try expect(!dbResult.isEmpty, "dumbbell skeleton should be non-empty")
    try expect(dbResult.paths.count >= 3,
               "dumbbell should have ≥3 ridge polylines (2 bulbs + neck), got \(dbResult.paths.count)")
    var insideCount = 0
    for path in dbResult.paths {
        for rp in path {
            try expect(MedialAxis.pointInPolygon(rp.position, db),
                       "ridge point \(rp.position) outside dumbbell polygon")
            insideCount += 1
        }
    }
    try expect(insideCount > 20, "expected many dumbbell ridge cells, got \(insideCount)")

    // Port of the reference's Dumbbell_Has_Bulb_And_Neck_Ridges + width
    // comparison: bulb ridge cells must measure WIDER than neck cells
    // (no absolute-radius assert — the coarse polygon bounds it).
    let all = dbResult.paths.flatMap { $0 }
    let bulb = all.filter { $0.position.x < 55 }
    let neck = all.filter { $0.position.x > 75 && $0.position.x < 125 }
    try expect(!bulb.isEmpty, "dumbbell skeleton has no bulb ridge cells")
    try expect(!neck.isEmpty, "dumbbell skeleton has no neck ridge cells")
    try expect(bulb.map(\.clearanceMm).max()! > neck.map(\.clearanceMm).max()!,
               "the bulb is not measured as wider than the neck")

    print("ShopPilotVerify2010a: PASS — medial axis + V-carve depth geometry (\(insideCount) dumbbell ridge cells, \(dbResult.paths.count) spines)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2010a: FAIL — \(error)")
    exit(1)
}
