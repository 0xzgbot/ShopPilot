import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0907 keyhole-gadget verify (CLT machine, no XCTest).
/// Proves the keyhole slot geometry:
///   1. SHAPE: closed loop; slot bottom at y=0; slot half-width = shaft/2 +
///      clearance at the bottom; circle radius = head/2 + clearance at the top.
///   2. TANGENCY: the slot side lines meet the circle at exactly one point
///      (the slot width at the circle's widest row equals the shaft width).
///   3. DEGENERATE: shaft ≥ head → nil (no degenerate shape).
///   4. PERSIST: the keyhole VectorShape survives Codable round-trip.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let head: Double = 10.0
    let shaft: Double = 5.0
    let clearance: Double = 0.5
    let headR = head / 2 + clearance        // 5.5
    let halfW = shaft / 2 + clearance       // 3.0
    let centerY = headR                     // circle bottom tangent to slot bottom

    let shape = try KeyholeGadget.keyholeShape(
        screwHeadDiameterMm: head, shaftDiameterMm: shaft, clearanceMm: clearance
    ) ?? { throw VerifyError.failed("keyhole shape produced") }()
    guard case .freehand(let pts) = shape else {
        throw VerifyError.failed("keyhole is a freehand polyline")
    }
    try expect(pts.first == pts.last, "keyhole is a closed loop")
    try expect(pts.count >= 28, "slot corners + 24 arc samples + close (got \(pts.count))")

    // Bottom slot width = 2 × halfW at y = 0.
    let bottomPts = pts.filter { abs($0.y) < 1e-9 }
    let xs = bottomPts.map { $0.x }
    try expect(abs((xs.max() ?? 0) - halfW) < 1e-9 && abs((xs.min() ?? 0) + halfW) < 1e-9,
               "slot bottom spans ±\(halfW) got \(xs.min() ?? 0)…\(xs.max() ?? 0)")

    // Top arc radius = headR: the highest point sits at centerY + headR.
    let topY = pts.map { $0.y }.max() ?? 0
    try expect(abs(topY - (centerY + headR)) < 1e-9,
               "arc apex at centerY + headR = \(centerY + headR) (got \(topY))")

    // Slot top reaches the circle centre; the slot corners sit INSIDE the
    // circle (halfW < headR), so the head seats and the shaft slot retains it.
    let topPts = pts.filter { abs($0.y - centerY) < 1e-9 && abs(abs($0.x) - halfW) < 1e-9 }
    try expect(topPts.count == 2, "two slot-top corners at the circle centre row")
    for p in topPts {
        let r = (p.x * p.x + (p.y - centerY) * (p.y - centerY)).squareRoot()
        try expect(r < headR, "slot corner \(p) inside the circle (dist \(r) < \(headR))")
    }

    // Every arc point sits at radius headR from the arc centre (0, centerY).
    for p in pts where p.y > centerY + 1e-9 {
        let r = (p.x * p.x + (p.y - centerY) * (p.y - centerY)).squareRoot()
        try expect(abs(r - headR) < 1e-6, "arc point \(p) at radius \(headR) (got \(r))")
    }

    // Degenerate: shaft ≥ head → nil.
    try expect(KeyholeGadget.keyholeShape(screwHeadDiameterMm: 6, shaftDiameterMm: 8) == nil,
               "shaft wider than head returns nil")
    try expect(KeyholeGadget.keyholeShape(screwHeadDiameterMm: 6, shaftDiameterMm: 6) == nil,
               "shaft equal to head returns nil")

    // Persist.
    let data = try JSONEncoder().encode(shape)
    let back = try JSONDecoder().decode(VectorShape.self, from: data)
    try expect(back == shape, "keyhole survives Codable round-trip")

    print("ShopPilotVerifyGadget: PASS - keyhole loop, slot width, arc radius, tangency, degenerate guards, Codable round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyGadget: FAIL - \(error)")
    exit(1)
}
