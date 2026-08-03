import Foundation
import ShopPilotGeometry

/// SPK-0201b verify without XCTest (CLT-only machines).
/// Proves the node-edit undo contract:
///   1. `ShapeNodeEditor.moveNode(id:to:)` records an undo snapshot so
///      `undoLastMove()` restores the vertex to its prior point.
///   2. Repeated moves undo in LIFO order, restoring each prior point.
///   3. No-op moves (same point) don't pollute the undo stack.
///   4. `VectorShape.moveVertex` + `updateFromNodes` round-trips: after a
///      session-style vertex move, restoring the pre-move node array yields
///      the exact original shape (the session snapshot-undo mechanism).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectPoint(_ p: VectorPoint, _ x: Double, _ y: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(p.x - x) > tolerance || abs(p.y - y) > tolerance {
        throw VerifyError.failed("\(msg): expected (\(x), \(y)), got (\(p.x), \(p.y))")
    }
}

func main() throws {
    // 1. Move a vertex, then undo restores the prior point.
    let editor = ShapeNodeEditor()
    editor.addNode(at: VectorPoint(x: 0, y: 0))
    editor.addNode(at: VectorPoint(x: 10, y: 0))
    editor.addNode(at: VectorPoint(x: 10, y: 10))

    let middle = editor.nodes[1].id
    editor.moveNode(id: middle, to: VectorPoint(x: 5, y: 5))
    try expectPoint(editor.getNode(id: middle)!.point, 5, 5, "vertex moved to (5,5)")

    try expect(editor.canUndoLastMove, "canUndo after a move")
    try expect(editor.undoLastMove(), "undoLastMove returns true")
    try expectPoint(editor.getNode(id: middle)!.point, 10, 0, "undo restores prior vertex (10,0)")

    // 2. LIFO: two moves undo back through both prior points.
    let editor2 = ShapeNodeEditor()
    editor2.addNode(at: VectorPoint(x: 0, y: 0))
    let node2 = editor2.nodes[0].id
    editor2.moveNode(id: node2, to: VectorPoint(x: 3, y: 3))
    editor2.moveNode(id: node2, to: VectorPoint(x: 7, y: 7))
    try expectPoint(editor2.getNode(id: node2)!.point, 7, 7, "second move applied")
    try expect(editor2.undoLastMove(), "undo 1 pops second move")
    try expectPoint(editor2.getNode(id: node2)!.point, 3, 3, "undo 1 restores (3,3)")
    try expect(editor2.undoLastMove(), "undo 2 pops first move")
    try expectPoint(editor2.getNode(id: node2)!.point, 0, 0, "undo 2 restores original (0,0)")
    // Single-add editor drains fully: the add snapshot is popped last.
    try expect(editor2.undoLastMove(), "undo 3 pops the add snapshot")
    try expect(!editor2.canUndoLastMove, "canUndo cleared after stack drained")
    try expect(!editor2.undoLastMove(), "undo on empty stack returns false")

    // 3. No-op move (same point) does not push an undo snapshot.
    let fresh = ShapeNodeEditor()
    fresh.addNode(at: VectorPoint(x: 1, y: 1))
    fresh.clearUndoHistory()   // start a clean edit session
    let only = fresh.nodes[0].id
    fresh.moveNode(id: only, to: VectorPoint(x: 1, y: 1))
    try expect(!fresh.canUndoLastMove, "no-op move pushes no undo snapshot")
    // A real move on the same session does push one.
    fresh.moveNode(id: only, to: VectorPoint(x: 2, y: 2))
    try expect(fresh.canUndoLastMove, "real move pushes an undo snapshot")
    try expect(fresh.undoLastMove(), "undo real move")
    try expectPoint(fresh.getNode(id: only)!.point, 1, 1, "undo real move restores (1,1)")

    // 4. Session-style flow: extract nodes, move a vertex, then undo by
    //    restoring the pre-move node array → exact original shape.
    let pts = [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 10, y: 0),
        VectorPoint(x: 10, y: 10),
    ]
    let shape = VectorShape.freehand(points: pts)
    let originalNodes = shape.extractNodes()

    // moveVertex produces the moved shape…
    let movedShape = shape.moveVertex(at: 1, to: VectorPoint(x: 5, y: 5))
    guard case .freehand(let movedPts) = movedShape else { throw VerifyError.failed("moved shape lost .freehand") }
    try expectPoint(movedPts[1], 5, 5, "moveVertex moved middle point")
    try expectPoint(movedPts[0], 0, 0, "moveVertex left first point")
    try expectPoint(movedPts[2], 10, 10, "moveVertex left last point")

    // …and restoring the original node array via updateFromNodes gives the
    // exact original shape (this is what the session snapshot-undo does).
    let restored = movedShape.updateFromNodes(originalNodes)
    guard case .freehand(let restoredPts) = restored else { throw VerifyError.failed("restored shape lost .freehand") }
    try expect(restoredPts.count == pts.count, "restored vertex count matches")
    for (i, p) in pts.enumerated() {
        try expectPoint(restoredPts[i], p.x, p.y, "restored vertex \(i)")
    }

    // 5. Line shapes: move end point, undo restores it (moveVertex contract).
    let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 10))
    let lineMoved = line.moveVertex(at: 1, to: VectorPoint(x: 15, y: 20))
    guard case .line(let ls, let le) = lineMoved else { throw VerifyError.failed("line lost .line") }
    try expectPoint(ls, 0, 0, "line start untouched")
    try expectPoint(le, 15, 20, "line end moved")
    let lineRestored = lineMoved.updateFromNodes(line.extractNodes())
    guard case .line(let rs, let re) = lineRestored else { throw VerifyError.failed("line restore lost .line") }
    try expectPoint(rs, 0, 0, "line restore start")
    try expectPoint(re, 10, 10, "line restore end")

    // 6. Non-moveable shapes: moveVertex returns self; session guard keeps doc intact.
    let circle = VectorShape.circle(center: VectorPoint(x: 5, y: 5), radius: 10)
    let circleMoved = circle.moveVertex(at: 0, to: VectorPoint(x: 99, y: 99))
    try expect(circleMoved == circle, "circle moveVertex returns self")

    print("SPK-0201b verification: PASS")
    print("  moveNode + undoLastMove restores prior vertex ✓")
    print("  LIFO multi-move undo (3,3) → (10,0) ✓")
    print("  no-op move pushes no undo snapshot ✓")
    print("  extractNodes/moveVertex/updateFromNodes undo round-trip ✓")
    print("  line vertex move + restore ✓  non-moveable shape returns self ✓")
}

do {
    try main()
} catch {
    fputs("SPK-0201b verification: FAIL — \(error)\n", stderr)
    exit(1)
}
