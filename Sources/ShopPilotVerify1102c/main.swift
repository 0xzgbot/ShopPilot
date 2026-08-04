import Foundation
import ShopPilotCore

/// SPK-1102c verify (CLT machines, no XCTest).
/// Proves the "Recalculate Dirty" product cycle the Cut-stage button drives
/// (session `recalculateDirtyToolpaths` → `ToolpathTreeManager.recalculateDirtyProfiles`):
///   1. A computed Profile op starts clean; export is allowed.
///   2. A design change marks ops dirty (cascade) → export BLOCKED (the badge
///      state the tree UI shows).
///   3. Recalc regenerates the dirty Profile with the REAL engine → clean,
///      dirty count drops, export is allowed again.
///   4. Out-of-scope ops (Pocket) stay dirty → export stays blocked, recalc
///      touches only Profile.
///   5. Recalc with nothing dirty is a no-op.
///   6. The session G-code buffer rebuilds from the clean tree (the
///      `allToolpathGCode` pattern the machine handoff uses).
/// The button/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Mirror of AppSession.allToolpathGCode: tree node results in tree order.
func allToolpathGCode(from tree: ToolpathTreeManager) -> [String] {
    tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

func main() throws {
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )

    let tree = ToolpathTreeManager()
    let profile = tree.addOperation("Profile 1")

    // 1. Initial generation (what Generate Profile Toolpath does).
    let initial = ProfileToolpathEngine.compute(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 6.0
    )
    profile.toolpathResult = initial.gcodeLines.joined(separator: "\n")
    profile.estimatedTimeSeconds = initial.estimatedTimeSeconds
    try expect(!profile.isDirty, "fresh Profile op is clean")
    try expect(tree.dirtyNodeCount == 0, "no dirty ops after generation")

    var blocker = ExportBlocker(treeManager: tree)
    try expect(blocker.validateForExport().isValid, "export allowed while clean")

    // 2. Design change → ops dirty (cascade to root), export blocked.
    profile.markDirty()
    try expect(profile.isDirty, "Profile op dirty after design change")
    try expect(tree.dirtyNodeCount == 1, "dirty count = 1 op")
    blocker = ExportBlocker(treeManager: tree)
    try expect(!blocker.validateForExport().isValid, "export blocked while dirty")

    // 3. Recalc dirty → Profile regenerates with the REAL engine, goes clean.
    let regenerated = tree.recalculateDirtyProfiles(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 6.0
    )
    try expect(regenerated.count == 1, "exactly the dirty Profile regenerated")
    try expect(!profile.isDirty, "Profile dirty flag cleared after recalc")
    try expect(tree.dirtyNodeCount == 0, "dirty count back to 0")
    let gcode = profile.toolpathResult ?? ""
    try expect(gcode.contains("O=PROFILE_TOOLPATH"), "regenerated output is real engine G-code")
    try expect(gcode.contains("G1"), "regenerated output contains cut moves")

    blocker = ExportBlocker(treeManager: tree)
    try expect(blocker.validateForExport().isValid, "export allowed again after recalc")

    // 4. Out-of-scope op stays dirty → export stays blocked.
    let pocket = tree.addOperation("Pocket 1")
    pocket.toolpathResult = "// Pocket stub"
    pocket.markDirty()
    try expect(tree.dirtyNodeCount == 1, "only the Pocket op is dirty")
    let again = tree.recalculateDirtyProfiles(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 6.0
    )
    try expect(again.isEmpty, "recalc leaves the out-of-scope Pocket untouched")
    try expect(pocket.isDirty, "Pocket stays dirty (badge remains)")
    blocker = ExportBlocker(treeManager: tree)
    try expect(!blocker.validateForExport().isValid, "export blocked on the dirty Pocket")

    // 5. No-op when nothing dirty.
    pocket.clearDirty()
    try expect(tree.recalculateDirtyProfiles(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 6.0
    ).isEmpty, "recalc with nothing dirty is a no-op")

    // 6. Session buffer rebuilds from the clean tree.
    let buffer = allToolpathGCode(from: tree)
    try expect(!buffer.isEmpty, "buffer rebuilds from tree results")
    try expect(buffer.contains { $0.hasPrefix("G1") }, "buffer contains real cut moves")

    print("ShopPilotVerify1102c: PASS — dirty→recalc→clean→export-unblocked cycle, out-of-scope stays dirty, buffer rebuild")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1102c: FAIL — \(error)")
    exit(1)
}
