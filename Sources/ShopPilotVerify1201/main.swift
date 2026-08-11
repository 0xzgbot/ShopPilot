import Foundation
import ShopPilotCore

/// SPK-1201 verify (CLT machine, no XCTest).
/// Proves the CUT-LAYERS TABLE contract (the LightBurn-style grid):
///   1. AGGREGATION: rows are a flat projection of the tree in TREE ORDER —
///      groups flattened, operations only, each row carries id/name/strategy/
///      tool/feed/depth/time/status.
///   2. TOOL NAMES: the toolName lookup closure resolves tool UUIDs to names
///      ("—" when nil/missing).
///   3. STATUS: rows reflect the node's dirty/result state via the SPK-1207
///      engine — computed op = .current, marked dirty = .stale.
///   4. SUMMARIES: totalTime sums rows; attentionCount counts stale/error
///      (the Recalc-All badge).
///   5. STRATEGY NAMES: `StrategyKind.displayName` covers every case (the
///      table's strategy column — exhaustive switch, compile-enforced).
/// The table UI (sortable grid, inline feed edit via
/// session.setToolpathFeedRate, toggle vs tree) is compile-checked by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let tree = ToolpathTreeManager()
    let group = tree.addGroup("Sheet 1")
    let profile = group.addOperation("Profile Outer")
    profile.toolpathResult = "G0 X0 Y0"
    profile.estimatedTimeSeconds = 42
    profile.toolID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    let pocket = group.addOperation("Pocket Inner")
    pocket.toolpathResult = "G1 X1 Y1"
    pocket.estimatedTimeSeconds = 17
    pocket.markDirty() // → stale

    // ── 1 + 2 + 3. Aggregation, tool names, status. ───────────────────────
    let rows = CutLayerTableBuilder.build(tree: tree) { id in
        id == profile.toolID ? "End Mill 6mm" : nil
    }
    try expect(rows.count == 2, "two operations flattened (got \(rows.count))")
    try expect(rows[0].id == profile.id && rows[0].order == 0, "tree order: profile first")
    try expect(rows[1].id == pocket.id && rows[1].order == 1, "tree order: pocket second")
    try expect(rows[0].name == "Profile Outer", "row name carried")
    try expect(rows[0].strategy == "Profile", "strategy column = displayName (got \(rows[0].strategy))")
    try expect(rows[1].strategy == "Pocket", "pocket strategy named")
    try expect(rows[0].toolName == "End Mill 6mm", "tool name resolved via closure")
    try expect(rows[1].toolName == "—", "nil tool → em dash")
    try expect(rows[0].status == .current, "computed op is .current")
    try expect(rows[1].status == .stale, "dirty op is .stale")
    try expect(abs((rows[0].estimatedTime) - 42) < 1e-9, "estimated time carried")
    try expect(rows[0].feedRate != nil, "feed rate from params carried (profile default)")

    // ── 4. Summaries. ─────────────────────────────────────────────────────
    try expect(abs(CutLayerTableBuilder.totalTime(rows) - 59) < 1e-9,
               "totalTime sums rows (42+17=59)")
    try expect(CutLayerTableBuilder.attentionCount(rows) == 1,
               "attentionCount = stale+error (1 stale)")

    // Empty tree → empty table.
    let emptyRows = CutLayerTableBuilder.build(tree: ToolpathTreeManager())
    try expect(emptyRows.isEmpty, "empty tree → empty table")
    try expect(CutLayerTableBuilder.totalTime(emptyRows) == 0, "empty total is 0")

    // ── 5. Strategy displayName coverage (exhaustive). ────────────────────
    let all: [ToolpathTreeNode.StrategyKind] = [.profile, .pocket, .drill, .drillBank,
        .vcarve, .rough3D, .finish3D, .prism, .fluting, .chamfer, .inlay,
        .quickEngrave, .photoVCarve, .dragKnife, .texture, .sketchCarve,
        .rotaryWrap, .threadMill, .unknown]
    for kind in all {
        try expect(!kind.displayName.isEmpty, "displayName non-empty for \(kind)")
    }

    print("ShopPilotVerify1201: PASS — tree-order aggregation (2 ops), tool-name resolution, status column via 1207, totals + attention, exhaustive strategy naming")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1201: FAIL — \(error)")
    exit(1)
}
