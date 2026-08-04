import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1101f verify (CLT machines, no XCTest).
/// Proves the transform spine the Ops bar's Nudge X+1 / Flip H / Rotate 90° /
/// Scale 1.1× buttons route to (the session apply* methods):
///   1. Nudge: translated(by:) moves the bounding box by (dx, dy).
///   2. Flip H: flipHorizontal about the selection centroid mirrors geometry
///      while keeping size and centroid fixed.
///   3. Rotate 90°: rotate about the centroid swaps rect w/h and keeps the
///      centroid fixed — the rect case previously rotated the origin and kept
///      w/h, producing geometrically wrong results (SPK-1101f fix).
///   4. Scale 1.1×: scale about the centroid multiplies size, centroid fixed.
///   5. Persist: transformed results survive a `.shoppilot`-style Job
///      round-trip with geometry intact.
/// The button/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 40)

    // ── 1. Nudge (session applyNudgeX → translated(by: 1, 0)). ───────────────
    let nudged = rect.translated(by: 1, 0)
    try expectClose(nudged.boundingRect.minX, 1.0, "nudge +1mm X moves minX")
    try expectClose(nudged.boundingRect.maxX, 101.0, "nudge keeps width")

    // ── 2. Flip H (session applyFlipHorizontal). ─────────────────────────────
    let centroid = selectionCentroid(of: [rect])!  // (50, 20)
    let flipped = ShapeTransformer().flipHorizontal(shapes: [rect], about: centroid)
    guard let flippedRect = flipped.first else { throw VerifyError.failed("flip produced no shape") }
    try expectClose(flippedRect.boundingRect.width, 100.0, "flip keeps width")
    try expectClose(flippedRect.boundingRect.height, 40.0, "flip keeps height")
    let flippedCentroid = selectionCentroid(of: flipped)!
    try expectClose(flippedCentroid.x, centroid.x, "flip keeps centroid x")
    try expectClose(flippedCentroid.y, centroid.y, "flip keeps centroid y")

    // ── 3. Rotate 90° (session applyRotate90). ───────────────────────────────
    let rotated = ShapeTransformer().rotate(shapes: [rect], angle: 90, about: centroid)
    guard let rotatedRect = rotated.first else { throw VerifyError.failed("rotate produced no shape") }
    try expectClose(rotatedRect.boundingRect.width, 40.0, "90° rotation swaps width to height")
    try expectClose(rotatedRect.boundingRect.height, 100.0, "90° rotation swaps height to width")
    try expectClose(rotatedRect.boundingRect.minX, 30.0, "rotated rect origin x (bbox re-derived)")
    try expectClose(rotatedRect.boundingRect.minY, -30.0, "rotated rect origin y (bbox re-derived)")
    let rotatedCentroid = selectionCentroid(of: rotated)!
    try expectClose(rotatedCentroid.x, centroid.x, "90° rotation keeps centroid x")
    try expectClose(rotatedCentroid.y, centroid.y, "90° rotation keeps centroid y")

    // Freehand rotation also lands exactly (vertex math).
    let poly = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0), VectorPoint(x: 100, y: 40),
    ])
    let rotatedPoly = ShapeTransformer().rotate(shapes: [poly], angle: 90, about: centroid)
    guard case .freehand(let rp) = rotatedPoly.first else { throw VerifyError.failed("poly lost freehand") }
    // (0,0) about (50,20) at 90° CCW: (50-(0-20), 20+(0-50)) = (70,-30)
    try expectClose(rp[0].x, 70.0, "poly vertex 0 rotated x")
    try expectClose(rp[0].y, -30.0, "poly vertex 0 rotated y")

    // ── 4. Scale 1.1× (session applyScale110). ───────────────────────────────
    let scaled = ShapeTransformer().scale(shapes: [rect], factor: 1.1, about: centroid)
    guard let scaledRect = scaled.first else { throw VerifyError.failed("scale produced no shape") }
    try expectClose(scaledRect.boundingRect.width, 110.0, "scale 1.1× multiplies width")
    try expectClose(scaledRect.boundingRect.height, 44.0, "scale 1.1× multiplies height")
    let scaledCentroid = selectionCentroid(of: scaled)!
    try expectClose(scaledCentroid.x, centroid.x, "scale keeps centroid x")
    try expectClose(scaledCentroid.y, centroid.y, "scale keeps centroid y")

    // ── 5. Persist: transformed results round-trip. ──────────────────────────
    let layer = Layer(name: "Transforms")
    let paths = GeometryBridge.toCorePaths(
        rotated,  // the 90°-rotated rect
        layerIDs: Array(repeating: layer.id, count: rotated.count)
    )
    var layers = [layer]
    LayerVisibility.distribute(paths, into: &layers)

    var job = Job(name: "Transform round-trip")
    _ = job.ensureSingleSheet()
    job.sheets[0].layers = layers
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)

    let restored = decoded.sheets[0].layers.flatMap(\.vectors)
    try expect(restored.count == 1, "round-trip keeps the transformed path")
    let restoredPoints = restored.first?.points ?? []
    try expect(restoredPoints.count == 5, "rotated rect persists as a 5-point chain")
    if restoredPoints.count == 5 {
        try expectClose(restoredPoints[0].x, 30.0, "persisted rotated rect starts at x=30")
        try expectClose(restoredPoints[0].y, -30.0, "persisted rotated rect starts at y=-30")
        try expectClose(restoredPoints[2].x, 70.0, "persisted rotated rect spans to x=70")
    }

    print("ShopPilotVerify1101f: PASS — nudge/flip/rotate-90/scale semantics + rect rotation fix + round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1101f: FAIL — \(error)")
    exit(1)
}
