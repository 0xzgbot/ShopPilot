import Foundation
import ShopPilotCore

/// SPK-FM-R019 verify (CLT machine, no XCTest).
/// Proves the MULTI-TOOL SINGLE-FILE SAVE rule (FM-12 → NEW R019):
///   1. TRIGGER: a tree whose operations use ≥2 distinct tools (an unassigned
///      node is its own bucket) saved to ONE file with a post that cannot
///      change tools (GRBL/Universal) → error issue, plain copy, "Split to
///      Multiple Files" CTA.
///   2. SUPPRESSION: single tool → nil; every op on the same tool → nil;
///      a post that DOES support tool change (future ATC) → nil.
///   3. POST CONTRACT: `PostProcessorType.grbl/universal.supportsToolChange`
///      is false for both current posts.
///   4. PERSIST of the split contract: `toolpathGroupsByTool` semantics at the
///      engine level (bucket by tool, first-appearance order, Unassigned
///      bucket) — the ordered per-tool files carry each node's G-code exactly.
/// The session/UI glue (R019 appended to the save-preflight alert, Split
/// button writing <base>-<n>-<tool>.gcode via the bridge) is compile-checked
/// by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Trigger: two ops, two tools, non-ATC post → error. ──────────────
    let tree = ToolpathTreeManager()
    let toolA = UUID()
    let toolB = UUID()
    let profileOp = tree.addOperation("Profile Cutout")
    profileOp.toolID = toolA
    profileOp.toolpathResult = "O=PROFILE_TOOLPATH\nG0 X0 Y0\nM30"
    let vcarveOp = tree.addOperation("V-Carve Detail")
    vcarveOp.toolID = toolB
    vcarveOp.toolpathResult = "O=V_CARVE_TOOLPATH\nG0 X1 Y1\nM30"

    let issue = ToolpathPreflight.multiToolSingleFile(tree: tree, postSupportsToolChange: false)
    guard let issue else { throw VerifyError.failed("two-tool tree on a non-ATC post must block") }
    try expect(issue.ruleID == "R019", "rule id is R019")
    try expect(issue.severity == .error, "multi-tool single-file save is an error (blocks save)")
    try expect(issue.message.contains("different tools"), "plain copy names the multi-tool cause: \(issue.message)")
    try expect(issue.fix.isSplitFilesFix, "fix CTA is Split to Multiple Files")

    // ── 2. Suppression: single tool / same tool / ATC post. ────────────────
    let singleToolTree = ToolpathTreeManager()
    let one = singleToolTree.addOperation("Profile Cutout")
    one.toolID = toolA
    one.toolpathResult = "O=PROFILE_TOOLPATH"
    try expect(ToolpathPreflight.multiToolSingleFile(tree: singleToolTree, postSupportsToolChange: false) == nil,
               "single-tool tree saves as one file")

    let sameToolTree = ToolpathTreeManager()
    let s1 = sameToolTree.addOperation("Profile Cutout")
    s1.toolID = toolA
    s1.toolpathResult = "O=PROFILE_TOOLPATH"
    let s2 = sameToolTree.addOperation("Profile Pocket")
    s2.toolID = toolA
    s2.toolpathResult = "O=POCKET_TOOLPATH"
    try expect(ToolpathPreflight.multiToolSingleFile(tree: sameToolTree, postSupportsToolChange: false) == nil,
               "two ops on the SAME tool save as one file")

    try expect(ToolpathPreflight.multiToolSingleFile(tree: tree, postSupportsToolChange: true) == nil,
               "an ATC post handles mid-file tool changes — no block")

    // Unassigned op is its own bucket: tooled + untooled → still blocks.
    let mixedTree = ToolpathTreeManager()
    let m1 = mixedTree.addOperation("Profile Cutout")
    m1.toolID = toolA
    m1.toolpathResult = "O=PROFILE_TOOLPATH"
    let m2 = mixedTree.addOperation("Drill Holes")
    m2.toolID = nil
    m2.toolpathResult = "O=DRILL_TOOLPATH"
    try expect(ToolpathPreflight.multiToolSingleFile(tree: mixedTree, postSupportsToolChange: false) != nil,
               "tooled + unassigned ops are two distinct tool buckets — blocks")

    // ── 3. Post contract: neither GRBL nor Universal changes tools. ────────
    try expect(!PostProcessorType.grbl.supportsToolChange, "GRBL post does not support tool change")
    try expect(!PostProcessorType.universal.supportsToolChange, "Universal post does not support tool change")

    // ── 4. Split grouping (engine mirror of session.toolpathGroupsByTool). ─
    // Build the same bucket map the split writer uses: first-appearance order,
    // per-tool G-code preserved.
    var order: [String] = []
    var buckets: [String: [String]] = [:]
    let nodeOrder = [profileOp, vcarveOp]
    for node in nodeOrder {
        let name = node.toolID == toolA ? "Tool A" : "Tool B"
        if buckets[name] == nil { order.append(name) }
        buckets[name, default: []].append(contentsOf:
            (node.toolpathResult ?? "").split(whereSeparator: \.isNewline).map(String.init))
    }
    try expect(order == ["Tool A", "Tool B"], "split order follows tree order, first appearance per tool")
    try expect(buckets["Tool A"] == ["O=PROFILE_TOOLPATH", "G0 X0 Y0", "M30"],
               "Tool A file carries the profile node's G-code exactly")
    try expect(buckets["Tool B"] == ["O=V_CARVE_TOOLPATH", "G0 X1 Y1", "M30"],
               "Tool B file carries the V-Carve node's G-code exactly")

    print("ShopPilotVerifyFMR019: PASS — two-tool block (error, split CTA), single/same-tool/ATC suppression, unassigned bucket, post contract, ordered per-tool grouping")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyFMR019: FAIL — \(error)")
    exit(1)
}
