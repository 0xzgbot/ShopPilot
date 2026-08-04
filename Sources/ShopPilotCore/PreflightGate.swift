import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - Preflight Checklist Item

/// A single pre-flight checklist item with a stable identifier.
///
/// Identifiers are stable strings (not UUIDs) so per-item acknowledgment
/// state survives SwiftUI view re-renders and can be tested headlessly.
public struct PreflightChecklistItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    /// Mandatory safety item — the checklist is incomplete until acknowledged.
    ///
    /// SPK-0412a: spindle and work-zero are always required; the gate treats
    /// every `required` item as non-negotiable for Run.
    public let required: Bool

    public init(id: String, title: String, detail: String, required: Bool = true) {
        self.id = id
        self.title = title
        self.detail = detail
        self.required = required
    }
}

// MARK: - Preflight Gate

/// Engine-level pre-flight gate: machine Run stays blocked until every
/// checklist item is individually acknowledged.
///
/// Safety semantics (SPK-1104c):
/// - `isRunAllowed` is `false` until ALL items are acknowledged — no auto-ack.
/// - Toggling any item back off re-blocks Run.
/// - `reset()` clears every acknowledgment (fresh connection ⇒ fresh checklist).
public final class PreflightGate: ObservableObject {

    /// The checklist items in display order.
    public let items: [PreflightChecklistItem]

    #if canImport(Combine)
    @Published public private(set) var acknowledgedIDs: Set<String> = []
    #else
    public private(set) var acknowledgedIDs: Set<String> = []
    #endif

    public init(items: [PreflightChecklistItem]) {
        self.items = items
    }

    // MARK: - Queries

    /// Number of items currently acknowledged.
    public var acknowledgedCount: Int { acknowledgedIDs.count }

    /// The ids of every mandatory safety item (SPK-0412a).
    ///
    /// The standard checklist marks spindle and work-zero as required; Run is
    /// never allowed until every required id is acknowledged, and the checklist
    /// is reported incomplete while any required item is unchecked.
    public var requiredIDs: Set<String> {
        Set(items.filter(\.required).map(\.id))
    }

    /// The required items that have not been acknowledged yet.
    public var missingRequiredIDs: Set<String> {
        requiredIDs.subtracting(acknowledgedIDs)
    }

    /// Whether every required item has been acknowledged.
    ///
    /// SPK-0412a: this is the model-level "checklist complete" signal — it is
    /// `false` until spindle + work-zero (and any other required item) are
    /// acknowledged, even if optional items are checked.
    public var isChecklistComplete: Bool {
        !items.isEmpty && missingRequiredIDs.isEmpty
    }

    /// Run is allowed only when every checklist item has been acknowledged.
    ///
    /// Keeps the SPK-1104c semantics (no item may be skipped) and additionally
    /// enforces the SPK-0412a requirement that required items — spindle and
    /// work-zero — can never be bypassed.
    public var isRunAllowed: Bool {
        isChecklistComplete && items.allSatisfy { acknowledgedIDs.contains($0.id) }
    }

    /// Whether a specific item has been acknowledged.
    public func isAcknowledged(_ id: String) -> Bool {
        acknowledgedIDs.contains(id)
    }

    // MARK: - Mutations

    /// Acknowledge a single item (no-op if already acknowledged).
    public func acknowledge(_ id: String) {
        acknowledgedIDs.insert(id)
    }

    /// Flip acknowledgment for a single item.
    public func toggle(_ id: String) {
        if acknowledgedIDs.contains(id) {
            acknowledgedIDs.remove(id)
        } else {
            acknowledgedIDs.insert(id)
        }
    }

    /// Clear all acknowledgments — re-blocks Run.
    public func reset() {
        acknowledgedIDs.removeAll()
    }
}

// MARK: - Standard Checklist

public extension PreflightGate {

    /// The standard 7-item machine pre-flight checklist.
    ///
    /// SPK-0412a: spindle and work-zero are mandatory safety items — the
    /// checklist is incomplete and Run stays gated until both are acknowledged.
    /// SPK-FM-R016: the datum-z0 item is the Z0/datum contract — the operator
    /// confirms Z0 = material surface and the XY datum against the job's
    /// material setup before every start.
    static func standard() -> PreflightGate {
        PreflightGate(items: [
            PreflightChecklistItem(
                id: "spindle",
                title: "Spindle verified",
                detail: "Confirm spindle is off or at safe speed; tool secured in collet"
            ),
            PreflightChecklistItem(
                id: "work-zero",
                title: "Work zero set",
                detail: "Confirm X/Y/Z work coordinates are correct"
            ),
            PreflightChecklistItem(
                id: "datum-z0",
                title: "Z0 = material surface confirmed",
                detail: "Confirm Z0 sits on the material surface and the XY datum matches the job setup (FM-09 → R016)"
            ),
            PreflightChecklistItem(
                id: "tool-loaded",
                title: "Tool loaded",
                detail: "Verify correct tool is in spindle"
            ),
            PreflightChecklistItem(
                id: "material-secured",
                title: "Material secured",
                detail: "Check material is clamped and level"
            ),
            PreflightChecklistItem(
                id: "workspace-clear",
                title: "Clear workspace",
                detail: "Ensure no obstructions near machine"
            ),
            PreflightChecklistItem(
                id: "gcode-verified",
                title: "G-code verified",
                detail: "Preview toolpath before running"
            ),
        ])
    }
}
