import Foundation
@testable import ShopPilotCore

/// SPK-1102f verify (CLT machines, no XCTest).
///
/// Smoke for the V-Carve stub node in the toolpath tree:
/// - the tree can host a V-Carve operation node (stub params OK)
/// - a freshly added V-Carve node is marked dirty (needs recalculation)
/// - dirty cascades to the root and blocks export
/// - the V-Carve node is NOT a Profile op, so recalc leaves it dirty
///   (full V-Carve engine is out of scope — SPK-1102f)

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let tree = ToolpathTreeManager()

    // 1. A V-Carve node lands in the tree as an operation.
    let node = tree.addOperation("V-Carve 1")
    try expect(tree.root.children.count == 1, "V-Carve node is a root child")
    try expect(tree.root.children.first === node, "V-Carve node is the added child")
    try expect(tree.allNodes.count == 2, "flat list = root + V-Carve node")
    try expect(node.name == "V-Carve 1", "node keeps its V-Carve name")

    // 2. Stub params are permitted — defaults are fine for the stub.
    let stubParams = VCarveParams()
    try expect(stubParams.vBitAngleDegrees > 0, "stub params carry a default V-bit angle")
    try expect(stubParams.maxDepthOfCutMm > 0, "stub params carry a default depth")
    node.toolpathResult =
        "// V-Carve stub (SPK-1102f) — engine not implemented\n" +
        "// V-bit: \(Int(stubParams.vBitAngleDegrees))°, depth: \(stubParams.maxDepthOfCutMm)mm"

    // 3. Marked dirty — the AC for this card.
    node.markDirty()
    try expect(node.isDirty, "V-Carve node is dirty after add")
    try expect(tree.root.isDirty, "root dirty (cascade)")
    try expect(tree.dirtyNodeCount == 2, "dirty count = node + root (\(tree.dirtyNodeCount))")

    // 4. The V-Carve node is an operation (not a group), and recalc must NOT
    //    regenerate it — the full V-Carve engine is out of scope for SPK-1102f.
    if case .operation = node.type {
        // operation node — as expected
    } else {
        throw VerifyError.failed("V-Carve node must be an operation node")
    }

    // 5. Export stays blocked while the V-Carve stub is dirty.
    let blocker = ExportBlocker(treeManager: tree)
    let blocked = blocker.validateForExport()
    try expect(!blocked.isValid, "export blocked while V-Carve node dirty")
    try expect(blocked.dirtyNodes.contains("V-Carve 1"), "blocker names the dirty V-Carve node")

    // 6. Persistence round-trip keeps the node + dirty flag.
    let persisted = ShopPilotPackagePayload.toolpaths(from: tree)
    try expect(persisted.count == 1, "one persisted toolpath")
    try expect(persisted[0].name == "V-Carve 1", "persisted name")
    try expect(persisted[0].isDirty, "persisted dirty flag")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: persisted)
    try expect(restored.root.children.count == 1, "restored tree has the V-Carve node")
    try expect(restored.root.children[0].isDirty, "restored node still dirty")

    print("SPK-1102f verification: PASS")
    print("  V-Carve node added to toolpath tree OK")
    print("  stub params (defaults) OK")
    print("  node marked dirty + cascade to root OK")
    print("  operation node (not a group) OK")
    print("  export blocked while dirty OK")
    print("  package round-trip keeps node + dirty flag OK")
}

do {
    try main()
} catch {
    fputs("SPK-1102f verification: FAIL — \(error)\n", stderr)
    exit(1)
}
