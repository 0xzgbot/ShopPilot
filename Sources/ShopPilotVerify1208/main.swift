import Foundation
import ShopPilotCore

/// SPK-1208 verify (CLT machine, no XCTest).
/// Proves the SHEET DUPLICATION + TOOLPATH TRANSFER contract:
///   1. DUPLICATE: deep copy gets NEW sheet + layer ids, same dims/material/
///      preset, same layer properties (visibility/lock/vectors); name gets a
///      " copy" suffix unless overridden.
///   2. INDEPENDENCE: mutating the copy's layers never touches the original
///      (fresh identity + value semantics).
///   3. MOVE VALIDATION: missing target → rejected; same-sheet move →
///      rejected; valid cross-sheet move → nil reason.
///   4. GROUP NAMING: the "Sheet X Ops" toolpath group convention.
///   5. TREE MOVE: a real tree round-trips the move — the node lands under
///      the target sheet's group, keeps its result, and leaves the old
///      parent (the session moveToolpathToSheet path is compile-checked by
///      the app build).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeSheet() -> Sheet {
    var sheet = Sheet(name: "Front", width: 600, depth: 400, height: 18)
    sheet.layers = [
        Layer(name: "Art", isVisible: true, isLocked: false),
        Layer(name: "Hidden", isVisible: false, isLocked: true),
    ]
    return sheet
}

func main() throws {
    // ── 1. Duplicate: new identities, same content. ───────────────────────
    let original = makeSheet()
    let copy = SheetOperations.duplicate(original)

    try expect(copy.id != original.id, "copy has a fresh sheet id")
    try expect(copy.name == "Front copy", "copy name gets suffix (got \(copy.name))")
    try expect(copy.width == original.width && copy.depth == original.depth
               && copy.height == original.height, "dims preserved")
    try expect(copy.layers.count == original.layers.count, "layer count preserved")
    try expect(copy.layers[0].id != original.layers[0].id, "layer ids are fresh")
    try expect(copy.layers[0].name == "Art" && copy.layers[0].isVisible, "layer props preserved")
    try expect(copy.layers[1].isLocked && !copy.layers[1].isVisible, "hidden+locked layer preserved")
    try expect(copy.stockPresetName == original.stockPresetName, "preset preserved")

    let renamed = SheetOperations.duplicate(original, newName: "Backup")
    try expect(renamed.name == "Backup", "explicit new name wins")

    // ── 2. Independence. ──────────────────────────────────────────────────
    var touched = copy
    touched.layers[0].name = "Changed"
    try expect(original.layers[0].name == "Art", "mutating the copy never touches the original")

    // ── 3. Move validation. ───────────────────────────────────────────────
    let sheetB = Sheet(name: "Back", width: 600, depth: 400, height: 18)
    let sheets = [original, sheetB]
    try expect(SheetOperations.validateToolpathMove(
        targetSheetID: sheetB.id, sheets: sheets, sourceSheetID: original.id) == nil,
        "valid cross-sheet move accepted")
    try expect(SheetOperations.validateToolpathMove(
        targetSheetID: sheetB.id, sheets: sheets, sourceSheetID: sheetB.id) != nil,
        "same-sheet move rejected")
    try expect(SheetOperations.validateToolpathMove(
        targetSheetID: UUID(), sheets: sheets) != nil,
        "missing target sheet rejected")

    // ── 4. Group naming. ──────────────────────────────────────────────────
    try expect(SheetOperations.toolpathGroupName(for: original) == "Front Ops",
               "group name convention (got \(SheetOperations.toolpathGroupName(for: original)))")

    // ── 5. Tree round-trip of the move. ───────────────────────────────────
    let tree = ToolpathTreeManager()
    let sourceGroup = tree.addGroup("Front Ops")
    let op = sourceGroup.addOperation("Profile Outer")
    op.toolpathResult = "G0 X0 Y0"
    let targetGroup = tree.addGroup("Back Ops")

    // Simulate the session move: re-parent under the target group.
    _ = sourceGroup.removeChild(id: op.id)
    targetGroup.addChild(op)
    try expect(tree.parent(of: op.id)?.id == targetGroup.id, "op re-homed under target group")
    try expect(op.toolpathResult == "G0 X0 Y0", "op keeps its computed result across the move")
    try expect(sourceGroup.children.isEmpty, "old parent no longer holds the op")
    try expect(tree.findNode(id: op.id) != nil, "op still findable after the move")

    print("ShopPilotVerify1208: PASS — deep copy (fresh ids, same dims/layers/props/preset), independence, move validation (missing/same-sheet rejected), group naming, tree re-home keeps result")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1208: FAIL — \(error)")
    exit(1)
}
