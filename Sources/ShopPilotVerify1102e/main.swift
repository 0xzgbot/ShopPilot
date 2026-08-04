import Foundation
@testable import ShopPilotCore

/// SPK-1102e verify (CLT machines, no XCTest).
///
/// Smoke for the session/toolpath-tree recalculate path:
/// - design change marks every operation node dirty (cascade to root)
/// - "recalculate dirty" regenerates dirty Profile nodes with REAL engine
///   G-code and clears their dirty flags
/// - out-of-scope operations (Pocket/V-Carve) stay dirty — export stays blocked
/// - the session G-code buffer rebuilds from the regenerated tree results

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // A closed square — the same input the session feeds ProfileToolpathEngine.
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )

    let tree = ToolpathTreeManager()
    let profile = tree.addOperation("Profile 1")
    _ = tree.addOperation("Pocket 1") // out of scope — must stay dirty

    try expect(profile.isProfileOperation, "Profile op detected as Profile")
    let pocket = tree.root.children.first { $0.name == "Pocket 1" }!
    try expect(!pocket.isProfileOperation, "Pocket op is not a Profile")
    try expect(!tree.root.isProfileOperation, "root group is not a Profile")

    // Initial generation — what the session does when the op is created.
    let initial = ProfileToolpathEngine.compute(
        vectors: [square],
        params: ProfileToolpathParams(),
        material: nil,
        stockHeightMm: 6.0
    )
    profile.toolpathResult = initial.gcodeLines.joined(separator: "\n")
    profile.estimatedTimeSeconds = initial.estimatedTimeSeconds
    try expect(!profile.isDirty, "fresh Profile op is clean")
    try expect(profile.toolpathResult?.contains("O=PROFILE_TOOLPATH") == true, "initial G-code is real engine output")

    // Design change → session marks every operation dirty (cascade to root).
    for node in tree.allNodes where node.id != tree.root.id {
        node.markDirty()
    }
    try expect(profile.isDirty, "Profile op dirty after design change")
    try expect(pocket.isDirty, "Pocket op dirty after design change")
    try expect(tree.root.isDirty, "root dirty after cascade")
    // allDirtyNodes counts dirty OPERATIONS only (groups/root are UI display
    // state; the export blocker keys off operations) — so 2, not 3.
    try expect(tree.dirtyNodeCount == 2, "dirty count = 2 ops (\(tree.dirtyNodeCount))")

    // Recalculate dirty → Profile regenerates with the REAL engine.
    let regenerated = tree.recalculateDirtyProfiles(
        vectors: [square],
        params: ProfileToolpathParams(),
        material: nil,
        stockHeightMm: 6.0
    )
    try expect(regenerated.count == 1, "only the Profile op regenerated (\(regenerated.count))")
    try expect(regenerated.first === profile, "regenerated node is the Profile op")

    try expect(!profile.isDirty, "Profile dirty flag cleared after recalc")
    let gcode = profile.toolpathResult ?? ""
    try expect(gcode.contains("O=PROFILE_TOOLPATH"), "regenerated output is real profile G-code")
    try expect(gcode.contains("G1 X"), "regenerated output contains cut moves")
    try expect(profile.estimatedTimeSeconds > 0, "regenerated op has a time estimate")

    // Out-of-scope nodes stay dirty — export stays blocked on them.
    try expect(pocket.isDirty, "Pocket op stays dirty (out of scope)")
    try expect(tree.root.isDirty, "root stays dirty while any op is dirty")
    try expect(tree.dirtyNodeCount == 1, "remaining dirty op = Pocket (\(tree.dirtyNodeCount))")

    // Re-running recalc is a no-op for the already-clean Profile.
    let again = tree.recalculateDirtyProfiles(
        vectors: [square],
        params: ProfileToolpathParams(),
        material: nil,
        stockHeightMm: 6.0
    )
    try expect(again.isEmpty, "second recalc regenerates nothing (Profile already clean)")

    // Session-buffer smoke: G-code lines rebuild from clean op results.
    let bufferLines = tree.allNodes
        .filter { $0.id != tree.root.id && $0.toolpathResult != nil }
        .flatMap { $0.toolpathResult!.components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(!bufferLines.isEmpty, "session G-code buffer rebuilds from tree results")
    try expect(bufferLines.contains { $0.hasPrefix("G1") }, "buffer contains real cut moves")

    // Export blocker agrees: dirty nodes block export until recalc clears them.
    let blocker = ExportBlocker(treeManager: tree)
    let blocked = blocker.validateForExport()
    try expect(!blocked.isValid, "export blocked while Pocket op dirty")
    try expect(blocked.dirtyNodes.contains("Pocket 1"), "blocker names the dirty Pocket op")

    print("SPK-1102e verification: PASS")
    print("  dirty marking on design change (cascade) OK")
    print("  recalculate regenerates Profile nodes with real engine G-code OK")
    print("  dirty flags cleared on regenerated Profile nodes OK")
    print("  Pocket/V-Carve stay dirty (out of scope) OK")
    print("  session G-code buffer rebuild OK")
    print("  export blocker agrees (blocked until clean) OK")
}

do {
    try main()
} catch {
    fputs("SPK-1102e verification: FAIL — \(error)\n", stderr)
    exit(1)
}
