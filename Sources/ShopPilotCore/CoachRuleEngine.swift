import Foundation

// MARK: - Coach rule engine (SPK-1205)

/// The coach's context snapshot — everything a rule can key on. The app
/// builds one per stage render; the engine is pure (CLT-verifiable).
public struct CoachContext: Sendable {
    public let stage: String            // "setup" | "design" | "model" | "cut" | "preview" | "machine"
    public let hasVectors: Bool
    public let hasSelection: Bool
    public let isDirty: Bool
    public let hasToolpaths: Bool
    public let hasBlockingIssue: Bool
    public let hasSheets: Bool
    public let isConnected: Bool

    public init(stage: String, hasVectors: Bool = false, hasSelection: Bool = false,
                isDirty: Bool = false, hasToolpaths: Bool = false,
                hasBlockingIssue: Bool = false, hasSheets: Bool = false,
                isConnected: Bool = false) {
        self.stage = stage
        self.hasVectors = hasVectors
        self.hasSelection = hasSelection
        self.isDirty = isDirty
        self.hasToolpaths = hasToolpaths
        self.hasBlockingIssue = hasBlockingIssue
        self.hasSheets = hasSheets
        self.isConnected = isConnected
    }
}

public struct CoachRule: Sendable {
    public let priority: Int            // higher wins
    public let id: String
    public let message: String
    /// Optional tip-card action: when `actionID` is non-nil the coach UI shows
    /// a Button labelled `actionTitle`. SPK-1400f — additive: both default to
    /// nil so existing rules (and their construction sites) are unaffected.
    public let actionTitle: String?
    public let actionID: String?
    /// Matches when the context satisfies this rule's conditions.
    public let matches: (CoachContext) -> Bool

    public init(priority: Int, id: String, message: String,
                actionTitle: String? = nil, actionID: String? = nil,
                matches: @escaping (CoachContext) -> Bool) {
        self.priority = priority
        self.id = id
        self.message = message
        self.actionTitle = actionTitle
        self.actionID = actionID
        self.matches = matches
    }
}

/// Rule resolution: the highest-priority matching rule wins; no match → nil
/// (the UI shows the stage intent instead — no dead air).
public enum CoachRuleEngine {

    public static func resolve(rules: [CoachRule], context: CoachContext) -> CoachRule? {
        rules
            .filter { $0.matches(context) }
            .max { $0.priority < $1.priority }
    }

    /// The app's standard rule set — blocking issues > empty states >
    /// suggestions, per stage.
    public static let standardRules: [CoachRule] = [
        // Blocking first.
        CoachRule(priority: 100, id: "blocking", message: "The export gate is blocking — fix the flagged toolpaths before saving.") {
            $0.hasBlockingIssue
        },
        // Per-stage empty states (priority 50). SPK-1400j: the high-value
        // ones carry a tip-card action the UI can run (Try a sample / Cut
        // out / Connect) — same engine, actions are just data.
        CoachRule(priority: 50, id: "setup.empty", message: "Start with your stock: pick a material and set sheet dimensions.") {
            $0.stage == "setup" && !$0.hasSheets
        },
        CoachRule(priority: 50, id: "design.empty",
                  message: "Import an SVG/DXF or draw a shape — toolpaths need vectors.",
                  actionTitle: "Try a sample", actionID: "try_sample") {
            $0.stage == "design" && !$0.hasVectors
        },
        CoachRule(priority: 50, id: "cut.empty",
                  message: "Generate a toolpath from the Cut toolbar — your vectors are ready.",
                  actionTitle: "Cut out", actionID: "cut_out") {
            $0.stage == "cut" && $0.hasVectors && !$0.hasToolpaths
        },
        // SPK-1502 — the remaining empty states: Model and Preview had no
        // guidance at all, and Setup got no next-step once sheets exist.
        CoachRule(priority: 50, id: "model.empty",
                  message: "Model needs a relief to shape — import an STL or image, or emboss text into a surface.") {
            $0.stage == "model" && !$0.hasVectors
        },
        CoachRule(priority: 50, id: "preview.empty",
                  message: "Generate a toolpath first — Preview simulates the cut, and there is nothing to simulate yet.") {
            $0.stage == "preview" && !$0.hasToolpaths
        },
        CoachRule(priority: 40, id: "setup.next",
                  message: "Stock is set — draw your design next, or open a bundled sample to get started.") {
            $0.stage == "setup" && $0.hasSheets
        },
        // Dirty-state suggestions (priority 40).
        CoachRule(priority: 40, id: "cut.dirty", message: "Some toolpaths are stale — Recalc All updates them in one click.") {
            $0.stage == "cut" && $0.isDirty && $0.hasToolpaths
        },
        CoachRule(priority: 40, id: "design.dirty", message: "The design changed — recalculate toolpaths before previewing.") {
            $0.stage == "design" && $0.isDirty && $0.hasVectors
        },
        // Selection hints (priority 30).
        CoachRule(priority: 30, id: "design.selection", message: "Right-click a vector for transform options; drag to move.") {
            $0.stage == "design" && $0.hasSelection
        },
        // Machine-stage guidance (priority 50). SPK-1400j: connect action.
        CoachRule(priority: 50, id: "machine.disconnected",
                  message: "Pick a transport and connect — or use Simulator to dry-run.",
                  actionTitle: "Connect", actionID: "connect_machine") {
            $0.stage == "machine" && !$0.isConnected
        },
        // SPK-1502 — connected machine: the next step is zeroing + homing,
        // not Connect (which the disconnected rule already covers).
        CoachRule(priority: 40, id: "machine.connected",
                  message: "Machine is connected — home it and set work zero before the first cut.") {
            $0.stage == "machine" && $0.isConnected
        },
        // Preview trust (priority 30).
        CoachRule(priority: 30, id: "preview.hint", message: "Hover a cut layer to highlight its path; switch material to preview the finish.") {
            $0.stage == "preview" && $0.hasToolpaths
        },
    ]
}
