import Foundation
import ShopPilotCore

/// SPK-0318 verify (CLT machine, no XCTest).
/// Proves the FOLLOW-SOURCE COACH COPY (already-written 0319 link engine →
/// coach contract in both states):
///   1. LINK OFF (manual): the Cut coach warns that toolpaths do NOT follow
///      art — editing the design leaves existing toolpaths stale until the
///      user recalculates (the honest snapshot semantics 0319 proved).
///   2. LINK ON (autoFollow): the coach explains dirty-on-edit — art edits
///      mark linked toolpaths stale (dirty badge) and export stays blocked
///      until recalculate; toolpaths NEVER recalculate silently (the exact
///      contract ShopPilotVerify0319 proved at the engine level).
///   3. LINK COUNT: the ON copy names how many linked toolpaths go stale.
/// The UI glue (ContentView passes session.linkManager state into
/// CoachPanelView; coach falls back to the static copy when no state is
/// provided) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Link OFF: warn that toolpaths don't follow art. ─────────────────
    let manual = CoachCopy.followSourceCutMessage(mode: .manual, activeLinkCount: 0)
    try expect(manual.contains("don't follow art"), "OFF copy warns toolpaths don't follow art: \(manual)")
    try expect(manual.contains("does NOT update"), "OFF copy states editing does not update existing toolpaths")
    try expect(manual.contains("recalculate"), "OFF copy points at the recalc remedy")

    // ── 2. Link ON: explain dirty-on-edit + no silent recalc. ──────────────
    let on = CoachCopy.followSourceCutMessage(mode: .autoFollow, activeLinkCount: 0)
    try expect(on.contains("Follow Source is ON"), "ON copy announces the mode")
    try expect(on.contains("stale"), "ON copy names the stale state")
    try expect(on.contains("dirty") && on.contains("export"), "ON copy ties stale → dirty → export block")
    try expect(on.contains("never recalculate silently"), "ON copy states recalc is explicit (the 0319 contract)")

    // ── 3. Link count surfaces in the ON copy. ─────────────────────────────
    let withLinks = CoachCopy.followSourceCutMessage(mode: .autoFollow, activeLinkCount: 3)
    try expect(withLinks.contains("3 linked toolpath(s)"), "ON copy names the stale count: \(withLinks)")
    let zero = CoachCopy.followSourceCutMessage(mode: .autoFollow, activeLinkCount: 0)
    try expect(!zero.contains("0 linked"), "zero links falls back to the generic stale copy")

    // ── 4. The copy matches the ENGINE contract it describes (0319): a real
    //    auto-follow link goes stale + dirty on sourcesDidChange, and its
    //    G-code is untouched (no silent recalc). ────────────────────────────
    let manager = ToolpathLinkManager()
    manager.setFollowSourceMode(.autoFollow)
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("V-Carve Detail")
    node.toolpathResult = "O=V_CARVE_TOOLPATH\nG1 X1 Y1"
    node.clearDirty()
    let link = manager.createLink(forToolpathId: node.id.uuidString, sourceVectorIds: [UUID(), UUID()])
    manager.sourcesDidChange(toolpathTree: tree)
    try expect(node.isDirty, "art edit marks the linked op dirty (the ON copy's stale claim)")
    try expect(node.toolpathResult?.contains("G1 X1 Y1") == true,
               "G-code untouched — no silent recalculation (the ON copy's explicit-recalc claim)")
    try expect(manager.activeFollowLinkCount == 1, "link count the coach quotes is real")
    _ = link

    print("ShopPilotVerify0318: PASS — OFF copy warns toolpaths don't follow art, ON copy explains dirty-on-edit + no silent recalc, link count quoted, copy matches the 0319 engine contract")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0318: FAIL — \(error)")
    exit(1)
}
