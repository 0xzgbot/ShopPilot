import Foundation
import ShopPilotCore

// MARK: - Snapshot undo (SPK-1403b)

/// The document slice a snapshot-based undo point preserves. Extracted from
/// `AppSession.SessionSnapshot` (SPK-1403b slice 2) so the undo mechanics are
/// CLT-testable and the ~5000-line facade shrinks. Behavior unchanged: the
/// same fields, captured and restored in the same order.
public struct SessionSnapshot: Sendable {
    public let job: ShopPilotCore.Job
    public let shapes: [VectorShape]
    public let shapeLayerIDs: [UUID]
    public let shapeGroups: [[Int]]
    public let gcodeLines: [String]
    public let selectedVectorIDs: Set<UUID>

    public init(job: ShopPilotCore.Job,
                shapes: [VectorShape],
                shapeLayerIDs: [UUID],
                shapeGroups: [[Int]],
                gcodeLines: [String],
                selectedVectorIDs: Set<UUID>) {
        self.job = job
        self.shapes = shapes
        self.shapeLayerIDs = shapeLayerIDs
        self.shapeGroups = shapeGroups
        self.gcodeLines = gcodeLines
        self.selectedVectorIDs = selectedVectorIDs
    }
}

/// The session surface snapshot undo needs. `AppSession` conforms with its
/// real stored properties; a CLI fake can drive capture/restore without the
/// app target.
@preconcurrency
public protocol SnapshotSession: AnyObject {
    var job: ShopPilotCore.Job { get set }
    var shapes: [VectorShape] { get set }
    var shapeLayerIDs: [UUID] { get set }
    var shapeGroups: [[Int]] { get set }
    var gcodeLines: [String] { get set }
    var selectedVectorIDs: Set<UUID> { get set }
}

/// Pure snapshot-undo mechanics (SPK-1403b): capture the current document
/// slice and restore a captured one. The UndoManager glue (registerUndo /
/// forward-snapshot) stays in the app session — Core must not depend on
/// AppKit — but the snapshot data + field transfer are now here, provable
/// without the app target.
public enum SessionUndoStack {

    /// Capture the session's current document slice.
    public static func capture(from session: SnapshotSession) -> SessionSnapshot {
        SessionSnapshot(
            job: session.job,
            shapes: session.shapes,
            shapeLayerIDs: session.shapeLayerIDs,
            shapeGroups: session.shapeGroups,
            gcodeLines: session.gcodeLines,
            selectedVectorIDs: session.selectedVectorIDs
        )
    }

    /// Restore a captured slice into the session (all six fields, in the
    /// same order `AppSession.performUndoRestore` used).
    public static func restore(_ snapshot: SessionSnapshot, into session: SnapshotSession) {
        session.job = snapshot.job
        session.shapes = snapshot.shapes
        session.shapeLayerIDs = snapshot.shapeLayerIDs
        session.shapeGroups = snapshot.shapeGroups
        session.gcodeLines = snapshot.gcodeLines
        session.selectedVectorIDs = snapshot.selectedVectorIDs
    }
}
