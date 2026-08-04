import Foundation
import ShopPilotCore

/// SPK-0319 lite verify (CLT machine, no XCTest).
/// Proves the optional Follow-source link mode:
///   1. DEFAULT OFF: links exist but art edits do NOT mark toolpaths dirty —
///      `sourcesDidChange` touches nothing in manual mode.
///   2. MODE ON: flipping to autoFollow + art edit marks every linked
///      toolpath stale AND its tree node dirty — so the export gate blocks
///      and the recalc badge counts it.
///   3. NEVER SILENT RECALC: after `sourcesDidChange` the node's G-code is
///      untouched (same toolpathResult) and `dirtyNodeCount` reflects the
///      dirty flag — recalculation remains a deliberate user action.
///   4. PER-LINK TOGGLE: autoFollowEnabled on a single link works even in
///      manual global mode; disabling it un-stales.
///   5. PERSIST: the mode round-trips through Job's optional
///      `followSourceModeRaw` (manual | autoFollow; nil = default manual).
/// The session glue (toggle in Cut toolbar, link creation at generation,
/// syncLayerVectors hook, job restore) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Default OFF — art edits do nothing. ─────────────────────────────
    let manager = ToolpathLinkManager()
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    node.toolpathResult = "gcode-before"
    try expect(manager.followSourceMode == .manual, "follow-source defaults OFF (manual)")

    // Link the node as the session does (key = node.id.uuidString).
    manager.createLink(
        forToolpathId: node.id.uuidString,
        sourceVectorIds: [UUID()]
    )
    try expect(manager.isLinked(toToolpathId: node.id.uuidString), "link created")
    try expect(manager.activeFollowLinkCount == 0, "no active follow links in manual mode")

    // Art edit in manual mode: nothing becomes stale, nothing dirty.
    manager.sourcesDidChange(toolpathTree: tree)
    try expect(!manager.hasStaleToolpaths, "manual mode: art edit does not stale anything")
    try expect(!node.isDirty, "manual mode: art edit does not dirty the tree node")

    // ── 2. Mode ON — art edits mark linked toolpaths dirty. ────────────────
    manager.setFollowSourceMode(.autoFollow)
    try expect(manager.followSourceMode == .autoFollow, "mode flips to autoFollow")
    try expect(manager.activeFollowLinkCount == 1, "link now active in autoFollow")
    manager.sourcesDidChange(toolpathTree: tree)
    try expect(manager.hasStaleToolpaths, "autoFollow: art edit marks toolpaths stale")
    try expect(manager.staleToolpathIds == [node.id.uuidString],
               "stale set names the linked toolpath (got \(manager.staleToolpathIds))")
    try expect(node.isDirty, "autoFollow: art edit marks the tree node dirty (export gate blocks)")

    // ── 3. Never silent recalc. ────────────────────────────────────────────
    try expect(node.toolpathResult == "gcode-before",
               "NO silent recalc — G-code untouched after art edit")
    try expect(tree.dirtyNodeCount == 1, "dirty count reflects the flag (recalc badge)")
    // Recalc stays a deliberate action: the app's Recalculate Dirty button.
    manager.markUpToDate(forToolpathId: node.id.uuidString)
    node.clearDirty()
    try expect(!manager.hasStaleToolpaths && !node.isDirty, "explicit recalc clears stale + dirty")

    // ── 4. Per-link toggle works in manual global mode. ────────────────────
    let manager2 = ToolpathLinkManager()
    let tree2 = ToolpathTreeManager()
    let node2 = tree2.addOperation("Pocket 1")
    let node3 = tree2.addOperation("V-Carve 1")
    manager2.createLink(forToolpathId: node2.id.uuidString, sourceVectorIds: [UUID()])
    manager2.createLink(forToolpathId: node3.id.uuidString, sourceVectorIds: [UUID()])
    manager2.setAutoFollow(true, forToolpathId: node2.id.uuidString)
    try expect(manager2.activeFollowLinkCount == 1, "only the per-link toggle is active")
    manager2.sourcesDidChange(toolpathTree: tree2)
    try expect(node2.isDirty, "per-link auto-followed op goes dirty on art edit")
    try expect(!node3.isDirty, "unfollowed op stays clean in manual global mode")
    manager2.setAutoFollow(false, forToolpathId: node2.id.uuidString)
    try expect(!manager2.hasStaleToolpaths, "disabling the per-link toggle un-stales")

    // ── 5. Mode persists via Job (optional raw string). ────────────────────
    var job = Job(name: "Linked Job")
    try expect(job.followSourceModeRaw == nil, "fresh job has no mode → default manual")
    job.followSourceModeRaw = "autoFollow"
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.followSourceModeRaw == "autoFollow", "mode round-trips through Job Codable")
    // Legacy documents (no mode key) decode unchanged — include every
    // non-optional field a pre-0319 Job had.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","sheets":[],"createdAt":0,"updatedAt":0,"documentVariables":[],"drivenDimensions":[],"vcarvePasses":0,"vcarveTimeSeconds":0}"#
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.followSourceModeRaw == nil, "legacy Job without mode decodes as manual")

    print("ShopPilotVerify0319: PASS — default OFF does nothing; ON marks linked toolpaths stale+dirty "
          + "(export gate blocks); NEVER silent recalc (G-code untouched); per-link toggle; mode persists via Job")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0319: FAIL — \(error)")
    exit(1)
}
