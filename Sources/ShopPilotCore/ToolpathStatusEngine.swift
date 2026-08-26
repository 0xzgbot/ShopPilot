import Foundation

// MARK: - Toolpath status engine (SPK-1207)

/// Per-operation status shown in the toolpath tree / cut-layers table.
/// Mirrors the conventional "visual toolpath status" pattern — at a glance
/// you see which ops are computed, which need recalculation, and which are
/// blocked by a preflight issue.
public enum ToolpathStatus: String, Sendable, Equatable {
    /// No result and not dirty — a fresh operation that was never computed.
    case pending
    /// Computed result is up to date with the source vectors/params.
    case current
    /// Source vectors/params changed since the last compute — needs recalc.
    case stale
    /// The op carries a blocking issue (e.g. open vectors, missing tool).
    case error
}

/// Derivation rules for the status engine (pure functions — CLT-verifiable).
public enum ToolpathStatusEngine {

    /// Derive a node's status from its state.
    /// - Parameters:
    ///   - isDirty: the node's `isDirty` mark (params/vectors changed since compute).
    ///   - hasResult: whether the node holds a computed G-code result.
    ///   - hasBlockingIssue: whether a preflight/validation gate blocks this op.
    public static func status(
        isDirty: Bool,
        hasResult: Bool,
        hasBlockingIssue: Bool = false
    ) -> ToolpathStatus {
        if hasBlockingIssue { return .error }
        if isDirty { return .stale }
        if hasResult { return .current }
        return .pending
    }

    /// Whether the status needs user attention before save/run.
    public static func needsAttention(_ status: ToolpathStatus) -> Bool {
        status == .stale || status == .error
    }

    /// Aggregated status for a group/sheet: error beats stale beats pending
    /// beats current (a group with any stale op is itself stale).
    public static func aggregate(_ statuses: [ToolpathStatus]) -> ToolpathStatus {
        if statuses.contains(.error) { return .error }
        if statuses.contains(.stale) { return .stale }
        if statuses.contains(.pending) { return .pending }
        return .current
    }
}

/// The blocking-issue source of truth shared by the status engine and the
/// export gate. Keeping the predicate here (Core, testable) instead of
/// scattered through views means the tree's red dot and the save-block alert
/// can never disagree about why an op is blocked.
public enum ToolpathIssuePredicates {

    /// A profile/v-carve op on open vectors is a blocking issue (spindle
    /// would cut off the path). Mirrors the preflight doctor's open-vector
    /// rule for the operation's strategy family.
    public static func isOpenVectorBlock(strategyName: String, isClosed: Bool) -> Bool {
        let needsClosed = strategyName.hasPrefix("Profile")
            || strategyName.hasPrefix("Pocket")
            || strategyName.hasPrefix("V-Carve")
            || strategyName.hasPrefix("Prism")
            || strategyName.hasPrefix("Inlay")
        return needsClosed && !isClosed
    }

    /// A node with no tool assigned is a blocking issue (feeds can't be
    /// derived; most recalc paths skip tool-less ops).
    public static func isMissingToolBlock(toolID: UUID?) -> Bool {
        toolID == nil
    }
}
