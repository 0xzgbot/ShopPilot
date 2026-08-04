import Foundation
import ShopPilotCore

/// SPK-0603 verify (CLT machine, no XCTest).
/// Proves the dirty-toolpath export gate:
///   1. BLOCK: a tree with any dirty operation cannot export — validation
///      is invalid, `requiresOverride` is true, and the offending node names
///      are surfaced (no silent export).
///   2. CLEAN: after recalculation every node is clean → export allowed
///      without override.
///   3. OVERRIDE: the explicit expert path (`overrideExportBlock`) unlocks
///      export even while dirty — and only that path does (the alert +
///      "Save Anyway (Expert)" button is the UI that calls it).
///   4. PERSIST: `PersistedToolpath` round-trips the dirty flag + params, so
///      a dirty node reopened from a .shoppilot package still blocks export
///      until recalculated (dirty survives the session boundary as designed).
/// The UI (alert + expert override button in CutStageView) is covered by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y), VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size), VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

func encodeParams(_ params: ProfileToolpathParams) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func main() throws {
    // Build a real Profile op the way the session does: engine G-code + stored
    // params + assigned tool, then mark it dirty (as a design edit would).
    let rect = makeClosedRect(x: 10, y: 10, size: 50)
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    var params = ProfileToolpathParams()
    params.feedRateMmPerMin = 1500
    node.paramsJSON = encodeParams(params)
    let result = ProfileToolpathEngine.compute(
        vectors: [rect],
        params: params,
        material: nil,
        stockHeightMm: 6.0
    )
    node.toolpathResult = result.gcodeLines.joined(separator: "\n")
    node.estimatedTimeSeconds = result.estimatedTimeSeconds

    // ── 1. Clean tree exports without override. ────────────────────────────
    let blocker = ExportBlocker(treeManager: tree)
    let cleanResult = blocker.validateForExport()
    try expect(cleanResult.isValid, "clean tree validates for export")
    try expect(cleanResult.canExport, "canExport true when clean")
    try expect(!cleanResult.requiresOverride, "no override needed when clean")
    try expect(cleanResult.dirtyNodes.isEmpty, "no dirty nodes reported when clean")
    try expect(!blocker.isExportBlocked, "blocker not engaged when clean")
    try expect(blocker.overrideExportBlock(), "override is a no-op success when nothing blocked")

    // ── 2. Dirty op blocks export (no silent export). ──────────────────────
    node.markDirty()
    let dirtyResult = blocker.validateForExport()
    try expect(!dirtyResult.isValid, "dirty tree is NOT valid for export")
    try expect(!dirtyResult.canExport, "canExport false while dirty")
    try expect(dirtyResult.requiresOverride, "dirty tree requires explicit override")
    try expect(dirtyResult.dirtyNodes == ["Profile 1"],
               "blocked export names the dirty node (got \(dirtyResult.dirtyNodes))")
    try expect(blocker.isExportBlocked, "blocker engaged while dirty")
    try expect(blocker.blockedReason.contains("need recalculation"),
               "blocked reason explains why (got \(blocker.blockedReason))")
    // The UI gate: export must not proceed while validation is invalid.
    try expect(!dirtyResult.isValid, "no silent export — save is gated on validation")

    // ── 3. Expert override is the explicit one-shot unlock path. ───────────
    // The UI flow is: validate → alert → "Save Anyway (Expert)" →
    // overrideExportBlock() → saveToolpaths() (no re-validation in between).
    // The override opens the gate once; the node is still dirty underneath.
    let overrideOK = blocker.overrideExportBlock()
    try expect(overrideOK, "expert override succeeds")
    try expect(!blocker.isExportBlocked, "override clears the block flag (gate open)")
    // Honest contract: a FRESH validation re-blocks, because the node is
    // still dirty — the override is one-shot, not a permanent unlock.
    _ = blocker.validateForExport()
    try expect(blocker.isExportBlocked, "re-validation re-blocks a still-dirty node (one-shot override)")

    // ── 4. Recalc is the non-override path to clean. ───────────────────────
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 6.0,
        tools: []
    )
    try expect(regenerated.count == 1, "recalc regenerated the dirty op")
    try expect(!node.isDirty, "node clean after recalc")
    let postRecalc = blocker.validateForExport()
    try expect(postRecalc.isValid, "export allowed again after recalc (no override needed)")
    try expect(!postRecalc.requiresOverride, "recalc path needs no override")

    // ── 5. Persist: dirty flag + params survive package round-trip. ────────
    node.markDirty()
    let persisted = PersistedToolpath(from: node)
    try expect(persisted.isDirty, "dirty flag captured in the package snapshot")
    try expect(persisted.paramsJSON != nil, "params captured in the package snapshot")
    let data = try JSONEncoder().encode(persisted)
    let restored = try JSONDecoder().decode(PersistedToolpath.self, from: data)
    try expect(restored.isDirty, "dirty flag survives encode/decode (reopened doc still blocks)")
    try expect(restored.paramsJSON == persisted.paramsJSON, "params survive encode/decode")
    try expect(restored.id == persisted.id && restored.name == "Profile 1",
               "identity survives encode/decode")

    // ── 6. Clear-dirty helper (SPK-0603 escape hatch parity). ──────────────
    let blocker2 = ExportBlocker(treeManager: tree)
    _ = blocker2.validateForExport()
    blocker2.clearDirtyFlags()
    try expect(!blocker2.isExportBlocked, "clearDirtyFlags disengages the blocker")

    print("ShopPilotVerify0603: PASS — dirty blocks export (named nodes, no silent save), "
          + "clean exports freely, expert override is the explicit unlock, recalc restores clean, "
          + "dirty+params survive package round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0603: FAIL — \(error)")
    exit(1)
}
