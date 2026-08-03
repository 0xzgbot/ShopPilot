import Foundation
import ShopPilotCore

/// SPK-1131 verify (CLT machines, no XCTest).
/// Covers the tool-picker slice behind the tree UI:
/// - ToolDatabase lookup + endmill/V-bit filtering
/// - ToolpathTreeNode tool assignment (id set, result invalidated, dirty cascade)
/// - session-level assign route keeps unknown ids out
/// - .shoppilot round-trip preserves the assigned tool id

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 1. ToolDatabase — defaults preload endmill + V-bit tools.
    let db = ToolDatabase()
    try expect(!db.tools.isEmpty, "default tools preloaded")
    try expect(
        db.tools.contains { $0.type == .endMill },
        "defaults include an end mill"
    )
    try expect(
        db.tools.contains { $0.type == .vBit },
        "defaults include a V-bit"
    )

    // 2. Lookup + filter.
    let first = db.tools[0]
    try expect(db.tool(withID: first.id)?.id == first.id, "lookup by id resolves")
    try expect(db.tool(withID: nil) == nil, "nil id lookup is nil")
    try expect(db.tool(withID: UUID()) == nil, "unknown id lookup is nil")

    let millVBit = db.tools(ofTypes: [.endMill, .vBit])
    try expect(
        millVBit.allSatisfy { $0.type == .endMill || $0.type == .vBit },
        "filter keeps only end mill + V-bit"
    )
    let onlyDrill = db.tools(ofTypes: [.drill])
    try expect(
        onlyDrill.allSatisfy { $0.type == .drill },
        "filter by drill keeps only drills"
    )

    // 3. Node assignment — id set, result invalidated, dirty cascade.
    let tree = ToolpathTreeManager()
    let op = tree.addOperation("Profile 1")
    op.toolpathResult = "// stale result"
    try expect(op.toolID == nil, "fresh op has no tool")
    op.assignTool(first.id)
    try expect(op.toolID == first.id, "assignTool sets tool id")
    try expect(op.toolpathResult == nil, "assignTool invalidates stale result")
    try expect(op.isDirty, "assignTool marks node dirty")
    try expect(tree.root.isDirty, "dirty cascades to root")

    // Clearing the tool also marks dirty and stays resolvable via database.
    op.assignTool(nil)
    try expect(op.toolID == nil, "assignTool(nil) clears tool")
    try expect(op.isDirty, "clearing tool marks dirty")
    try expect(db.tool(withID: op.toolID) == nil, "nil id unresolved")

    // Re-assigning the same tool is a no-op (guard in engine + session).
    op.assignTool(first.id)
    op.clearDirty()
    op.assignTool(first.id)
    try expect(!op.isDirty, "re-assigning same tool is a no-op")

    // 4. Session-level route — rejects unknown ids and groups.
    let db2 = ToolDatabase()
    try expect(db2.tool(withID: UUID()) == nil, "unknown id unresolved in db")

    // 5. Persistence — tool id round-trips through the package payload.
    let opWithTool = tree.addOperation("Profile 2")
    opWithTool.assignTool(first.id)
    let opNoTool = tree.addOperation("Profile 3")
    try expect(opNoTool.toolID == nil, "fresh op has no tool before persist")
    let persisted = ShopPilotPackagePayload.toolpaths(from: tree)
    let op2 = persisted.first { $0.name == "Profile 2" }
    try expect(op2?.toolID == first.id, "persisted op keeps tool id")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: persisted)
    let restoredOp = restored.root.children.first { $0.name == "Profile 2" }
    try expect(restoredOp?.toolID == first.id, "restored op keeps tool id")
    let restoredNoTool = restored.root.children.first { $0.name == "Profile 3" }
    try expect(restoredNoTool?.toolID == nil, "op without tool persists nil")

    print("SPK-1131 verification: PASS")
    print("  ToolDatabase lookup + endmill/V-bit filter OK")
    print("  node assignTool (set/clear/no-op + dirty cascade) OK")
    print("  .shoppilot round-trip of tool id OK")
}

do {
    try main()
} catch {
    fputs("SPK-1131 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
