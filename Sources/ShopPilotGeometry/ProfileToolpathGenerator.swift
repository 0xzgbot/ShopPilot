import Foundation
import ShopPilotCore

// MARK: - Profile generation (SPK-1403c)

/// The session surface `ProfileToolpathGenerator` needs. `AppSession`
/// conforms with its real stored properties + methods; a CLI fake can drive
/// generation without the app target.
@preconcurrency
public protocol ProfileGeneratingSession: AnyObject {
    /// Live design vectors as Core paths (AppSession computes these via
    /// GeometryBridge; the engine consumes `[VectorPath]`).
    var vectors: [VectorPath] { get }
    /// Per-shape layer membership, index-aligned with the source shapes —
    /// restored if generation unexpectedly reshuffles it (SPK-UI603a).
    var shapeLayerIDs: [UUID] { get set }
    /// Active sheet height in mm (stock), or a sane default when no sheet.
    var activeSheetHeightMm: Double { get }
    /// How many toolpath nodes exist (used for the generated node's name).
    var toolpathNodeCount: Int { get }
    /// Push a snapshot undo point before mutating the document.
    func registerUndoPoint()
    /// Add a computed toolpath node to the tree (default tool, sources link,
    /// buffer refresh, selection, dirty — the session owns all of it).
    @discardableResult
    func addToolpathNode(named: String, gcode: [String], estimatedTime: Double) -> ToolpathTreeNode
    /// Encode an operation's params to JSON for the node.
    func encodeParams<T: Encodable>(_ params: T) -> String?
    /// Publish the one-line summary (also becomes the status line).
    func setLastToolpathSummary(_ text: String)
}

/// Owns the Cut-out profile generation orchestration (SPK-1403c slice 3 of
/// the AppSession split): guards vectors, snapshots layer membership, pushes
/// an undo point, computes with the REAL `ProfileToolpathEngine` (Core,
/// unchanged), creates the node, encodes params, publishes the summary, and
/// restores layer membership if the op reshuffled it. Extracted verbatim
/// from `AppSession.generateProfileToolpath()` — no behavior change.
/// Deliberately ONLY the profile strategy: Pocket/V-Carve/3D stay in the
/// facade on this card.
public enum ProfileToolpathGenerator {

    /// Generate a Profile op from the session's current vectors.
    /// Returns false (and mutates nothing) when there are no vectors.
    @discardableResult
    public static func generateProfile(on session: ProfileGeneratingSession) -> Bool {
        guard !session.vectors.isEmpty else {
            session.setLastToolpathSummary("No vectors — import SVG or add a demo shape first")
            return false
        }
        // Snapshot layer membership before the op — Profile must not reshuffle
        // shapes across layers (SPK-UI603a).
        let layerIDsBefore = session.shapeLayerIDs
        session.registerUndoPoint()
        // Route through the session's addToolpathNode so the strategy default
        // tool is assigned (was "No tool" when this path called addOperation
        // bare). Stock height comes from the sheet — matches
        // Pocket/Drill/V-Carve.
        let params = ProfileToolpathParams()
        let result = ProfileToolpathEngine.compute(
            vectors: session.vectors,
            params: params,
            material: nil,
            stockHeightMm: session.activeSheetHeightMm
        )
        let node = session.addToolpathNode(
            named: "Profile \(session.toolpathNodeCount)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = session.encodeParams(params)
        // Form "Finish passes" ≠ engine depth/Z passes — label clearly
        // (SPK-UI603c).
        let summary =
            "Profile: \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s, " +
            "\(result.passCount) depth pass(es), \(params.finishPasses) finish pass(es)"
        session.setLastToolpathSummary(summary)
        // Profile must not reshuffle shape→layer membership (SPK-UI603a).
        if session.shapeLayerIDs != layerIDsBefore {
            session.shapeLayerIDs = layerIDsBefore
            session.setLastToolpathSummary("Profile created — restored layer membership after unexpected reshuffle")
        }
        return true
    }
}
