import Foundation

// MARK: - Cut-layers table (SPK-1201)

/// One row in the Cut-Layers table — the LightBurn-style grid that replaces
/// the opaque tree as the primary cut overview. Each row is a flat snapshot
/// of one operation node: what it is, what it cuts with, what it costs, and
/// whether it's up to date. The table is a projection of `ToolpathTreeManager`
/// in tree order, so it can never disagree with the tree.
public struct CutLayerRow: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let strategy: String
    public let toolName: String
    public let feedRate: Double?
    public let cutDepth: Double?
    public let estimatedTime: Double
    public let status: ToolpathStatus
    public let enabled: Bool
    /// Tree order position (for reorder/drag persistence).
    public let order: Int

    public init(
        id: UUID,
        name: String,
        strategy: String,
        toolName: String,
        feedRate: Double?,
        cutDepth: Double?,
        estimatedTime: Double,
        status: ToolpathStatus,
        enabled: Bool,
        order: Int
    ) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.toolName = toolName
        self.feedRate = feedRate
        self.cutDepth = cutDepth
        self.estimatedTime = estimatedTime
        self.status = status
        self.enabled = enabled
        self.order = order
    }
}

/// Builds cut-layer rows from the toolpath tree (pure aggregation — CLT-
/// verifiable). Tool names resolve through a lookup closure so Core stays
/// tool-database-agnostic.
public enum CutLayerTableBuilder {

    /// Build the flat table in tree order (depth-first, groups flattened).
    /// - Parameters:
    ///   - tree: the toolpath tree manager.
    ///   - toolName: resolves a tool UUID to a display name (nil → "—").
    public static func build(
        tree: ToolpathTreeManager,
        toolName: (UUID?) -> String? = { _ in nil }
    ) -> [CutLayerRow] {
        var rows: [CutLayerRow] = []
        var order = 0

        func walk(_ node: ToolpathTreeNode, depth: Int) {
            if case .operation = node.type {
                let status = ToolpathStatusEngine.status(
                    isDirty: node.isDirty,
                    hasResult: node.toolpathResult != nil && !(node.toolpathResult?.isEmpty ?? true)
                )
                rows.append(CutLayerRow(
                    id: node.id,
                    name: node.name,
                    strategy: node.strategyKind.displayName,
                    toolName: toolName(node.toolID) ?? "—",
                    feedRate: node.paramFeedRate,
                    cutDepth: node.paramCutDepth,
                    estimatedTime: node.estimatedTimeSeconds,
                    status: status,
                    enabled: true,
                    order: order
                ))
                order += 1
            }
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(tree.root, depth: 0)
        return rows
    }

    /// Total estimated time across all rows (the table footer's number).
    public static func totalTime(_ rows: [CutLayerRow]) -> Double {
        rows.reduce(0) { $0 + $1.estimatedTime }
    }

    /// Count of rows needing attention (stale or error) — the Recalc-All
    /// affordance's badge.
    public static func attentionCount(_ rows: [CutLayerRow]) -> Int {
        rows.filter { ToolpathStatusEngine.needsAttention($0.status) }.count
    }
}
