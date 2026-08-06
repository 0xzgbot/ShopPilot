import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0214 verify (CLT machine, no XCTest).
/// Proves array + circular copy semantics:
///   1. GRID: 3×2 array of a rect at 20/30 spacing lands each copy at the
///      exact grid offset (Aspire array-copy layout).
///   2. CIRCULAR around a center: 4 copies of a line at distance 10 land at
///      angles 0/90/180/270 around the center; k=0 coincides with the source.
///   3. ROTATE COPIES: each copy spins by its angular position — the 90°
///      copy of a horizontal line becomes vertical.
///   4. RECT conversion: rotating a rectangle yields a closed freehand (the
///      axis-aligned rect form cannot express the rotation).
///   5. PERSIST: copies survive VectorShape Codable round-trip.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

/// Center of a shape's bounding rect.
func center(of shape: VectorShape) -> (x: Double, y: Double) {
    let b = shape.boundingRect
    return ((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2)
}

func main() throws {
    // ── 1. Grid array ──────────────────────────────────────────────────────
    let rect = VectorShape.rectangle(origin: pt(0, 0), width: 10, height: 10)
    let grid = ArrayCopyEngine.createGridArray(
        source: rect, columns: 3, rows: 2, spacingX: 20, spacingY: 30
    )
    try expect(grid.copies.count == 6, "3×2 grid → 6 copies (got \(grid.copies.count))")
    let expectedOrigins: [(Double, Double)] = [
        (0, 0), (20, 0), (40, 0),
        (0, 30), (20, 30), (40, 30),
    ]
    for (i, expected) in expectedOrigins.enumerated() {
        let b = grid.copies[i].boundingRect
        try expect(abs(b.minX - expected.0) < 1e-9 && abs(b.minY - expected.1) < 1e-9,
                   "copy \(i) at (\(expected.0),\(expected.1)) got (\(b.minX),\(b.minY))")
        try expect(abs(b.width - 10) < 1e-9 && abs(b.height - 10) < 1e-9,
                   "copy \(i) keeps 10×10 size")
    }

    // ── 2. Circular around a center ────────────────────────────────────────
    // Horizontal line (0,0)→(2,0); center (0,0) → bbox center at (1,0),
    // distance 1... use a line at (10,0)→(12,0) so distance from origin is 11.
    let line = VectorShape.line(start: pt(10, 0), end: pt(12, 0))
    let circ = ArrayCopyEngine.createCircularArrayAround(
        source: line, center: pt(0, 0), count: 4, rotateCopies: false
    )
    try expect(circ.copies.count == 4, "4 circular copies")
    let expectedCenters: [(Double, Double)] = [(11, 0), (0, 11), (-11, 0), (0, -11)]
    for (i, expected) in expectedCenters.enumerated() {
        let c = center(of: circ.copies[i])
        try expect(abs(c.x - expected.0) < 1e-9 && abs(c.y - expected.1) < 1e-9,
                   "copy \(i) centered at (\(expected.0),\(expected.1)) got (\(c.x),\(c.y))")
    }
    // k=0 coincides with the source position.
    let first = circ.copies[0]
    try expect(first == line, "k=0 copy coincides with the source line")

    // ── 3. Rotate copies ───────────────────────────────────────────────────
    let rot = ArrayCopyEngine.createCircularArrayAround(
        source: line, center: pt(0, 0), count: 4, rotateCopies: true
    )
    guard case .line(let s0, let e0) = rot.copies[1] else {
        throw VerifyError.failed("90° copy stays a line")
    }
    // Original horizontal (10,0)→(12,0) copied to bbox center (0,11), then
    // rotated 90° about that center: vertical at x=0, (0,10)→(0,12).
    try expect(abs(s0.x) < 1e-9 && abs(s0.y - 10.0) < 1e-9,
               "90° copy vertical at (0,10) got \(s0)")
    try expect(abs(e0.x) < 1e-9 && abs(e0.y - 12.0) < 1e-9,
               "90° copy vertical at (0,12) got \(e0)")
    // 180° copy: bbox center at (-11,0), rotated 180° → start/end swap.
    guard case .line(let s2, let e2) = rot.copies[2] else {
        throw VerifyError.failed("180° copy stays a line")
    }
    try expect(abs(s2.x + 10.0) < 1e-9 && abs(s2.y) < 1e-9,
               "180° copy start at (-10,0) got \(s2)")
    try expect(abs(e2.x + 12.0) < 1e-9 && abs(e2.y) < 1e-9,
               "180° copy end at (-12,0) got \(e2)")

    // ── 4. Rectangle + rotate → closed freehand ────────────────────────────
    let rectCirc = ArrayCopyEngine.createCircularArrayAround(
        source: rect, center: pt(0, 0), count: 4, rotateCopies: true
    )
    guard case .freehand(let rp) = rectCirc.copies[1] else {
        throw VerifyError.failed("rotated rect copy converts to freehand")
    }
    try expect(rp.first == rp.last, "converted rect is a closed loop")
    try expect(rp.count >= 5, "converted rect has 4 corners + close (got \(rp.count))")
    // The 90° copy of the 10×10 rect (bbox center (5,5), distance 7.07):
    // rotated 90° about its own center → still a 10×10 square, now vertical-ish
    // orientation — bbox stays 10×10 for a square.
    let b = rectCirc.copies[1].boundingRect
    try expect(abs(b.width - 10) < 1e-9 && abs(b.height - 10) < 1e-9,
               "90° square keeps 10×10 bbox")

    // ── 5. Persist ─────────────────────────────────────────────────────────
    let data = try JSONEncoder().encode(grid.copies)
    let back = try JSONDecoder().decode([VectorShape].self, from: data)
    try expect(back == grid.copies, "grid copies survive Codable round-trip")

    print("ShopPilotVerify0214: PASS - grid layout, circular centers + k=0 identity, rotate-copies geometry, rect→freehand conversion, Codable round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0214: FAIL - \(error)")
    exit(1)
}
