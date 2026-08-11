import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1203 verify (CLT machine, no XCTest).
/// Proves the SMART PART SELECTION + DIMENSION HANDLE contract:
///   1. PART DETECTION: touching rectangles (shared edge within tolerance)
///      form ONE part; separated rectangles are separate parts.
///   2. TRANSITIVE: A touches B, B touches C → A+B+C one part (union-find).
///   3. TOLERANCE: a hairline gap (< 0.5mm) still joins; a real gap doesn't.
///   4. PART LOOKUP: part(containing:) finds the right part by index.
///   5. DIMENSION HANDLE: rect handles report width/height; dragging the
///      horizontal handle edits the value and moves the caption; the value
///      never goes negative; the perpendicular drag moves the offset only.
/// The session wiring (smartSelectPart → selectedShapeIndices) and canvas
/// gesture plumbing are compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> VectorShape {
    .rectangle(origin: VectorPoint(x: x, y: y), width: w, height: h)
}

func main() throws {
    // ── 1. Touching rectangles = one part. ────────────────────────────────
    // Two 10×10 squares sharing the edge at x=10 (second starts at x=10).
    let touching = [rect(0, 0, 10, 10), rect(10, 0, 10, 10)]
    let parts = PartDetector.detectParts(of: touching, tolerance: 0.5)
    try expect(parts.count == 1, "touching squares = one part (got \(parts.count))")
    try expect(parts[0].shapeIndices.count == 2, "part has both shapes")

    // ── 2. Transitive join. ───────────────────────────────────────────────
    let chain = [rect(0, 0, 10, 10), rect(10, 0, 10, 10), rect(20, 0, 10, 10)]
    let chainParts = PartDetector.detectParts(of: chain, tolerance: 0.5)
    try expect(chainParts.count == 1 && chainParts[0].shapeIndices.count == 3,
               "A-B-C chain joins into one part (transitive)")

    // ── 3. Tolerance: hairline gap joins, real gap doesn't. ───────────────
    let hairline = [rect(0, 0, 10, 10), rect(10.3, 0, 10, 10)] // 0.3mm gap
    let hairlineParts = PartDetector.detectParts(of: hairline, tolerance: 0.5)
    try expect(hairlineParts.count == 1, "0.3mm gap still joins (design tolerance)")

    let separated = [rect(0, 0, 10, 10), rect(20, 0, 10, 10)] // 10mm gap
    let separatedParts = PartDetector.detectParts(of: separated, tolerance: 0.5)
    try expect(separatedParts.count == 2, "10mm gap = two parts (got \(separatedParts.count))")

    // ── 4. Part lookup. ───────────────────────────────────────────────────
    let mixed = [rect(0, 0, 10, 10), rect(10, 0, 10, 10), rect(50, 50, 5, 5)]
    let mixedParts = PartDetector.detectParts(of: mixed, tolerance: 0.5)
    try expect(mixedParts.count == 2, "one assembly + one lone shape = 2 parts")
    let p0 = PartDetector.part(containing: 1, in: mixedParts)
    try expect(p0?.shapeIndices.contains(0) == true, "part lookup joins index 0+1")
    let lone = PartDetector.part(containing: 2, in: mixedParts)
    try expect(lone?.shapeIndices == [2], "lone shape is its own part")

    // ── 5. Dimension handles. ─────────────────────────────────────────────
    let handles = DimensionHandle.handles(forRect: 0, minY: 0, maxX: 40, maxY: 20)
    try expect(handles.count == 2, "rect yields width + height handles")
    let widthHandle = handles[0]
    let heightHandle = handles[1]
    try expect(widthHandle.isHorizontal && widthHandle.value == 40, "width handle = 40")
    try expect(!heightHandle.isHorizontal && heightHandle.value == 20, "height handle = 20")

    var w = widthHandle
    w.applyDrag(deltaX: 5, deltaY: 0)      // drag right → widen
    try expect(w.value == 45, "horizontal drag edits the value (got \(w.value))")
    try expect(w.offset.y == -12, "perpendicular drag keeps caption Y")
    w.applyDrag(deltaX: -100, deltaY: 0)   // drag far left
    try expect(w.value == 0, "value clamps at 0 (no negative widths)")
    w.applyDrag(deltaX: 0, deltaY: 8)      // vertical drag moves caption only
    try expect(w.value == 0 && w.offset.y == -4, "vertical drag moves offset, not value")

    var h = heightHandle
    h.applyDrag(deltaX: 0, deltaY: 3)      // drag up → taller
    try expect(h.value == 23, "vertical drag edits height (got \(h.value))")
    try expect(h.offset.x == -12, "perpendicular drag keeps caption X")

    print("ShopPilotVerify1203: PASS — touching/transitive/tolerance part detection + lookup, dimension handle width/height, drag math + clamping + caption offset")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1203: FAIL — \(error)")
    exit(1)
}
