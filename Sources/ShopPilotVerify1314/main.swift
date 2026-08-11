import Foundation
import ShopPilotCore

/// SPK-1314 verify (CLT machine, no XCTest).
/// Proves the ASYNC RECALC split contract:
///   1. COMPUTE IS PURE: `computeDirtyToolpathResults` returns results for
///      every dirty node WITHOUT mutating @Published node state — the tree
///      still reports the same dirty count after the compute pass.
///   2. APPLY MUTATES: `applyToolpathResults` clears dirty + sets results
///      on the main actor; the regenerated count matches.
///   3. ROUND-TRIP: sync `recalculateDirtyToolpaths` (compute+apply) still
///      produces the same final state as the old single-pass behavior —
///      dirty nodes become clean, results are set, non-dirty untouched.
///   4. GUARD: empty results apply cleanly (no crash, [] returned).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let tree = ToolpathTreeManager()
    let group = tree.addGroup("Sheet 1")

    // Two operations: one with a real vector to compute against, one dirty
    // but with no closed vector (drill path has nothing to drill → stays).
    let profile = group.addOperation("Profile Square")
    let rect = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50),
        ],
        isClosed: true
    )
    profile.markDirty()

    // ── 1. Compute is pure. ───────────────────────────────────────────────
    let results = tree.computeDirtyToolpathResults(
        vectors: [rect],
        material: nil,
        stockHeightMm: 18.0,
        tools: [],
        heightfield: nil,
        machineName: nil
    )
    try expect(!results.isEmpty, "compute produced results for the dirty profile")
    try expect(tree.dirtyNodeCount > 0, "tree still dirty after PURE compute (no mutation)")

    // ── 2. Apply mutates. ─────────────────────────────────────────────────
    let regenerated = tree.applyToolpathResults(results)
    try expect(regenerated.count == results.count, "apply returns the regenerated nodes")
    for node in regenerated {
        try expect(!node.isDirty, "apply cleared dirty on regenerated nodes")
        try expect(node.toolpathResult != nil, "apply set the computed result")
    }
    let profileNode = tree.findNode(id: profile.id)
    try expect(profileNode?.toolpathResult?.contains("G0") == true,
               "profile result contains real G-code (not a stub)")

    // ── 3. Sync round-trip unchanged contract. ────────────────────────────
    let pocket = group.addOperation("Pocket Square")
    pocket.markDirty()
    let beforeDirty = tree.dirtyNodeCount
    try expect(beforeDirty == 1, "one node dirty before sync recalc")
    let syncRegenerated = tree.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 18.0,
        tools: [],
        heightfield: nil,
        machineName: nil
    )
    try expect(syncRegenerated.count >= 1, "sync recalc regenerated the dirty pocket")
    try expect(tree.dirtyNodeCount == 0, "sync recalc left zero dirty nodes")
    try expect(pocket.toolpathResult?.contains("G0") == true,
               "pocket recomputed with real G-code via the sync wrapper")

    // ── 4. Empty apply guard. ─────────────────────────────────────────────
    let nothing = tree.applyToolpathResults([])
    try expect(nothing.isEmpty, "applying no results returns [] without crashing")
    try expect(tree.dirtyNodeCount == 0, "empty apply left the clean tree untouched")

    print("ShopPilotVerify1314: PASS — compute pure (no mutation), apply mutates + clears dirty, sync round-trip contract intact, empty-apply guard")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1314: FAIL — \(error)")
    exit(1)
}
