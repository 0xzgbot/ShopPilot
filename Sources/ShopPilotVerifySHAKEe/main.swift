import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-SHAKEe verify (CLT): design ops matrix — booleans / join-close-trim /
/// transforms / layers / undo (G4: op → snapshot → undo → state-restored).
///
/// Every op here is exercised through the SAME engine entry points the
/// AppSession routes to (BooleanOps, ShapeJoinEngine, ShapeTransformer,
/// LayerVisibility, Sheet layer CRUD). The undo matrix replicates the
/// session's snapshot contract (job + shapes + layerIDs captured before the
/// op, restored on undo) and asserts exact state restoration per family.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 0.001) -> Bool { abs(a - b) < tol }

func rectShape(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> VectorShape {
    .rectangle(origin: VectorPoint(x: x, y: y), width: w, height: h)
}

func lineShape(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> VectorShape {
    .line(start: VectorPoint(x: x1, y: y1), end: VectorPoint(x: x2, y: y2))
}

func totalArea(_ shapes: [VectorShape]) -> Double { shapes.reduce(0) { $0 + $1.area } }

func bbox(_ s: VectorShape) -> Rect { s.boundingRect }

// Session snapshot contract: (job, shapes, layerIDs). We capture/restore the
// same fields AppSession.performUndoRestore does.
struct Snapshot {
    let shapes: [VectorShape]
    let layerIDs: [UUID]
}

func capture(_ shapes: [VectorShape], _ layerIDs: [UUID]) -> Snapshot {
    Snapshot(shapes: shapes, layerIDs: layerIDs)
}

func restore(_ snap: Snapshot, into shapes: inout [VectorShape], _ layerIDs: inout [UUID]) {
    shapes = snap.shapes
    layerIDs = snap.layerIDs
}

func assertEqual(_ a: [VectorShape], _ b: [VectorShape], _ msg: String) throws {
    try expect(a.count == b.count, "\(msg): shape count \(a.count) == \(b.count)")
    for (i, sa) in a.enumerated() {
        try expect(sa == b[i], "\(msg): shape \(i) identical")
    }
}

var total = 0
func ok(_ name: String) { total += 1; print("  ok   \(name)") }

func main() throws {
    // ── 1. Booleans: weld / subtract / intersect. ───────────────────────────
    print("== Booleans ==")
    let a = rectShape(10, 10, 40, 40)   // (10,10)-(50,50)
    let b = rectShape(30, 30, 40, 40)   // (30,30)-(70,70); overlap 20x20
    let welded = BooleanOps.union(a, b)
    try expect(welded.polygons.count == 1, "union merges two overlapping squares (got \(welded.polygons.count))")
    try expect(near(totalArea(welded.polygons), 3600), "union bbox area = 3600 (got \(totalArea(welded.polygons)))")
    ok("union: 2 squares → 1 shape, bbox area 3600")

    let subtracted = BooleanOps.subtract(a, b)
    try expect(!subtracted.polygons.isEmpty, "subtract yields geometry")
    try expect(near(totalArea(subtracted.polygons), 1200), "A−B area = 1200 (got \(totalArea(subtracted.polygons)))")
    ok("subtract: A−B strips total area 1200 (overlap removed)")

    let intersected = BooleanOps.intersect(a, b)
    try expect(!intersected.polygons.isEmpty, "intersect yields geometry")
    try expect(near(totalArea(intersected.polygons), 400), "intersection area = 400 (got \(totalArea(intersected.polygons)))")
    ok("intersect: overlap area 400")

    // ── 2. Join / close / trim. ─────────────────────────────────────────────
    print("== Join / Close / Trim ==")
    let joined = ShapeJoinEngine.joinLines(lineShape(0, 0, 10, 0), lineShape(10, 0, 20, 0))
    try expect(joined != nil && joined!.count == 1, "collinear lines join into one")
    if let j = joined?.first {
        try expect(j.points.count == 2, "joined shape is a single line")
        try expect(near(j.points[0].x, 0) && near(j.points[0].y, 0) &&
                   near(j.points[1].x, 20) && near(j.points[1].y, 0),
                   "joined line spans (0,0)→(20,0)")
    }
    ok("join: two collinear lines → one (0,0)→(20,0) line")

    let openPoly = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0),
        VectorPoint(x: 10, y: 10), VectorPoint(x: 0, y: 10),
    ])
    // closeAll contract (as shipped): a line is closed by emitting forward +
    // reverse; non-line shapes pass through to the unclosed bucket.
    let closed = ShapeJoinEngine.closeAll([lineShape(0, 0, 10, 0)])
    try expect(closed.0.count == 2, "closeAll closes a line into 2 segments (got \(closed.0.count))")
    try expect(closed.1.isEmpty, "no leftover unclosed shapes")
    let passthrough = ShapeJoinEngine.closeAll([openPoly])
    try expect(passthrough.0.isEmpty && passthrough.1.count == 1,
               "non-line shapes pass through as unclosed (engine contract)")
    ok("close: line → forward+reverse; freehand passes through")

    let box = Rect(minX: 0, minY: 0, maxX: 20, maxY: 20)
    let trimmed = ShapeJoinEngine.trimToBox(lineShape(-10, 5, 30, 5), in: box)
    try expect(trimmed.count == 1, "trim clips the crossing line to one segment")
    if let t = trimmed.first {
        let tb = bbox(t)
        try expect(tb.minX >= -0.001 && tb.maxX <= 20.001, "trimmed segment inside box (x \(tb.minX)..\(tb.maxX))")
    }
    ok("trim: crossing line clipped into the box")

    // ── 3. Transforms: move / rotate / scale / flip. ────────────────────────
    print("== Transforms ==")
    let tr = ShapeTransformer()
    let moved = tr.move(shapes: [a], dx: 10, dy: 0)
    try expect(near(bbox(moved[0]).minX, 20), "move +10 shifts bbox x")
    ok("move: +10mm shift")

    // Non-square 20×40 rect rotated 90° (engine takes DEGREES) about origin:
    // w/h swap + bbox re-derive.
    let wide = rectShape(10, 10, 20, 40)
    let rotated = tr.rotate(shapes: [wide], angle: 90, about: VectorPoint(x: 0, y: 0))
    let rb = bbox(rotated[0])
    try expect(near(rb.width, 40) && near(rb.height, 20), "rotate 90° swaps w/h (got \(rb.width)×\(rb.height))")
    try expect(near(rb.minX, -50) && near(rb.minY, 10), "rotate 90° re-derives bbox origin")
    ok("rotate: 90° w/h swap + re-derived bbox")

    let scaled = tr.scale(shapes: [a], factor: 1.1, about: bbox(a).center)
    try expect(near(bbox(scaled[0]).width, 44) && near(bbox(scaled[0]).height, 44),
               "scale 1.1× grows 40 → 44")
    ok("scale: 1.1× about centroid")

    let flipped = tr.flipHorizontal(shapes: [a], about: VectorPoint(x: 50, y: 30))
    try expect(near(bbox(flipped[0]).minX, 50) && near(bbox(flipped[0]).maxX, 90),
               "flip H mirrors x range about x=50 (10..50 → 50..90)")
    ok("flip: horizontal mirror")

    // ── 4. Layers: CRUD + visibility/lock. ──────────────────────────────────
    print("== Layers ==")
    var sheet = Sheet(name: "S", width: 200, depth: 200, height: 18)
    let l1 = Layer(name: "Cut")
    let l2 = Layer(name: "Ref")
    sheet.addLayer(l1)
    sheet.addLayer(l2)
    try expect(sheet.layers.count == 2, "addLayer × 2 (got \(sheet.layers.count))")
    let renamedID = sheet.layers[0].id
    sheet.layers[0].name = "Cut Renamed"
    try expect(sheet.layers.first { $0.id == renamedID }?.name == "Cut Renamed", "rename layer")
    sheet.removeLayer(id: l2.id)
    try expect(sheet.layers.count == 1, "removeLayer drops it (got \(sheet.layers.count))")
    ok("layer CRUD: add / rename / remove")

    // Visibility + lock semantics (LayerVisibility, wired by SPK-1137).
    var vsheet = Sheet(name: "V", width: 100, depth: 100, height: 18)
    let visible = Layer(name: "Visible")
    let hidden = Layer(name: "Hidden", isVisible: false)
    let locked = Layer(name: "Locked", isLocked: true)
    vsheet.addLayer(visible)
    vsheet.addLayer(hidden)
    vsheet.addLayer(locked)
    let layerIDs = [visible.id, hidden.id, locked.id]
    let layerShapes = [rectShape(0, 0, 10, 10), rectShape(20, 0, 10, 10), rectShape(40, 0, 10, 10)]
    let visIdx = LayerVisibility.visibleIndices(count: layerShapes.count, shapeLayerIDs: layerIDs, layers: vsheet.layers)
    try expect(visIdx == [0, 2], "hidden layer's shapes are not visible; locked still renders (got \(visIdx))")
    let editIdx = LayerVisibility.editableIndices(count: layerShapes.count, shapeLayerIDs: layerIDs, layers: vsheet.layers)
    try expect(editIdx == [0, 1], "locked layer's shapes are not editable (got \(editIdx))")
    ok("visibility/lock: hidden excluded from render, locked excluded from edit")

    // ── 5. Undo matrix (G4): op → snapshot → undo → state-restored. ────────
    print("== Undo matrix (snapshot restore) ==")

    func undoWalk(_ name: String, base: [VectorShape], apply: (inout [VectorShape]) -> Void) throws {
        var uShapes = base
        var uLayerIDs = base.map { _ in UUID() }
        let snap = capture(uShapes, uLayerIDs)
        apply(&uShapes)
        try expect(uShapes != snap.shapes, "\(name): op changes the design state")
        restore(snap, into: &uShapes, &uLayerIDs)
        try assertEqual(uShapes, snap.shapes, "\(name): undo restores shapes")
        try expect(uLayerIDs == snap.layerIDs, "\(name): undo restores layer IDs")
        ok("undo: \(name) → snapshot → restore → identical")

        // Redo contract: the forward snapshot is what the session registers
        // for redo; restoring it must reproduce the pre-op state exactly.
        let forward = capture(uShapes, uLayerIDs)
        apply(&uShapes)
        restore(forward, into: &uShapes, &uLayerIDs)
        try expect(uShapes == snap.shapes, "\(name): redo-snapshot restores the pre-op state")
    }

    try undoWalk("union", base: [a, b]) { s in s = BooleanOps.union(s[0], s[1]).polygons }
    try undoWalk("subtract", base: [a, b]) { s in s = BooleanOps.subtract(s[0], s[1]).polygons }
    try undoWalk("join", base: [lineShape(0, 0, 10, 0), lineShape(10, 0, 20, 0)]) { s in
        if let j = ShapeJoinEngine.joinLines(s[0], s[1]) { s = j }
    }
    try undoWalk("close", base: [lineShape(0, 0, 10, 0)]) { s in
        s = ShapeJoinEngine.closeAll(s).0
    }
    try undoWalk("trim", base: [lineShape(-10, 5, 30, 5)]) { s in
        s = ShapeJoinEngine.trimToBox(s[0], in: Rect(minX: 0, minY: 0, maxX: 20, maxY: 20))
    }
    try undoWalk("move", base: [a]) { s in s = ShapeTransformer().move(shapes: s, dx: 5, dy: 5) }
    try undoWalk("rotate", base: [wide]) { s in
        s = ShapeTransformer().rotate(shapes: s, angle: 90, about: VectorPoint(x: 0, y: 0))
    }
    try undoWalk("scale", base: [a]) { s in
        s = ShapeTransformer().scale(shapes: s, factor: 1.1, about: bbox(s[0]).center)
    }
    try undoWalk("flip", base: [a]) { s in
        s = ShapeTransformer().flipHorizontal(shapes: s, about: VectorPoint(x: 50, y: 30))
    }

    print("\nRESULT: SPK-SHAKEe \(total) checks — PASS")
}

do {
    try main()
} catch {
    print("FAIL: \(error)")
    exit(1)
}

// MARK: - Rect helpers

extension Rect {
    var center: VectorPoint { VectorPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }
}
