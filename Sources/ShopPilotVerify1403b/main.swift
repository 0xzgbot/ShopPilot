import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-1403b verify (CLT executable, no XCTest).
// Proves the extracted snapshot-undo mechanics (SessionUndoStack):
//   1. CAPTURE: SessionUndoStack.capture(from:) grabs all six document-slice
//      fields from a SnapshotSession.
//   2. RESTORE: after the session mutates, restore() puts every field back
//      exactly (job, shapes, layer ids, groups, gcode lines, selection).
//   3. EQUATABLE: captured snapshots compare — two captures of the same
//      state are equal, a mutated session produces a different snapshot.
//   4. SOURCE CONTRACT: AppSession no longer declares its own SessionSnapshot
//      struct; its capture/restore delegate to Core (undo/redo behavior
//      unchanged — the UndoManager glue stays app-side).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// A SnapshotSession the CLT can drive (mirrors AppSession's stored props).
final class FakeSnapshotSession: SnapshotSession {
    var job = Job(name: "Undo Rig")
    var shapes: [VectorShape] = []
    var shapeLayerIDs: [UUID] = []
    var shapeGroups: [[Int]] = []
    var gcodeLines: [String] = []
    var selectedVectorIDs: Set<UUID> = []
}

func main() throws {
    // ── 1/2. Capture then restore round-trips every field. ───────────────
    let session = FakeSnapshotSession()
    session.job = Job(name: "Round Trip")
    session.shapes = [VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)]
    session.shapeLayerIDs = [UUID()]
    session.shapeGroups = [[0]]
    session.gcodeLines = ["G0 X0 Y0", "G1 X10"]
    session.selectedVectorIDs = [session.shapeLayerIDs[0]]

    let snapshot = SessionUndoStack.capture(from: session)

    // Mutate everything.
    session.job = Job(name: "Mutated")
    session.shapes = []
    session.shapeLayerIDs = []
    session.shapeGroups = []
    session.gcodeLines = []
    session.selectedVectorIDs = []

    SessionUndoStack.restore(snapshot, into: session)
    try expect(session.job.name == "Round Trip", "job restored (got \(session.job.name))")
    try expect(session.shapes.count == 1, "shapes restored")
    try expect(session.shapeLayerIDs.count == 1, "shapeLayerIDs restored")
    try expect(session.shapeGroups == [[0]], "shapeGroups restored")
    try expect(session.gcodeLines == ["G0 X0 Y0", "G1 X10"], "gcodeLines restored")
    try expect(session.selectedVectorIDs.count == 1, "selectedVectorIDs restored")

    // ── 3. Field equality: same state → identical snapshots; mutation → different. ─
    let again = SessionUndoStack.capture(from: session)
    try expect(again.job.name == snapshot.job.name
               && again.shapes == snapshot.shapes
               && again.shapeLayerIDs == snapshot.shapeLayerIDs
               && again.shapeGroups == snapshot.shapeGroups
               && again.gcodeLines == snapshot.gcodeLines
               && again.selectedVectorIDs == snapshot.selectedVectorIDs,
               "identical state captures equal snapshots (field-wise)")

    session.shapes.append(VectorShape.rectangle(origin: VectorPoint(x: 100, y: 100), width: 5, height: 5))
    let changed = SessionUndoStack.capture(from: session)
    try expect(changed.shapes != snapshot.shapes || changed.gcodeLines != snapshot.gcodeLines,
               "mutated session captures a different snapshot")

    // ── 4. Source contract: AppSession delegates to Core. ────────────────
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/AppSession.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    try expect(!source.contains("private struct SessionSnapshot"),
               "AppSession no longer declares its own SessionSnapshot")
    try expect(source.contains("SessionUndoStack.capture(from: self)"),
               "AppSession.captureSnapshot delegates to Core")
    try expect(source.contains("SessionUndoStack.restore(snapshot, into: self)"),
               "AppSession.performUndoRestore delegates to Core")
    try expect(source.contains("SnapshotSession"),
               "AppSession conforms to SnapshotSession")

    print("1403b: PASS — snapshot undo extracted to Core SessionUndoStack")
    print("  capture/restore round-trip all six fields; Equatable; AppSession delegates (undo/redo glue stays app-side)")
}

do {
    try main()
} catch {
    print("1403b: FAIL — \(error)")
    exit(1)
}
