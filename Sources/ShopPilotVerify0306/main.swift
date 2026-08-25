import Foundation
import ShopPilotCore

/// SPK-0306 verify (CLT machine, no XCTest).
/// Proves the "Recalculate All" product cycle — regenerate EVERY operation
/// node regardless of dirty state:
///   1. A tree with mixed clean/dirty ops of multiple strategies; Recalc All
///      regenerates ALL of them (not just dirty ones) with their real engines.
///   2. Clean ops get fresh G-code (not stale snapshots).
///   3. Unknown-strategy ops are skipped (no engine) — they stay as-is.
///   4. The session G-code buffer rebuilds from the full tree.
///   5. Recalc All on an empty tree is a no-op.
///   6. Stored per-op params are respected (pocket F1500 reaches G-code).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

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
    let pocket = tree.addOperation("Pocket 1")
    let drill = tree.addOperation("Drill 1")
    let vcarve = tree.addOperation("V-Carve 1")

    // Initial generation — all clean.
    let initial = ProfileToolpathEngine.compute(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 6.0
    )
    profile.toolpathResult = initial.gcodeLines.joined(separator: "\n")
    profile.estimatedTimeSeconds = initial.estimatedTimeSeconds

    var pocketParams = PocketToolpathParams()
    pocketParams.feedRateMmPerMin = 1500
    pocket.paramsJSON = String(data: try JSONEncoder().encode(pocketParams), encoding: .utf8)
    drill.paramsJSON = String(data: try JSONEncoder().encode(DrillToolpathParams()), encoding: .utf8)
    vcarve.paramsJSON = String(data: try JSONEncoder().encode(VCarveParams()), encoding: .utf8)

    for op in [pocket, drill, vcarve] {
        op.toolpathResult = "// stale snapshot"
    }

    // Mark only pocket + drill dirty; profile + vcarve stay clean.
    pocket.markDirty()
    drill.markDirty()
    try expect(tree.dirtyNodeCount == 2, "two ops dirty (pocket + drill)")

    // 1. Recalc All regenerates ALL ops, not just dirty ones.
    let regenerated = tree.recalculateAllToolpaths(
        vectors: [square], material: nil, stockHeightMm: 25.0
    )
    try expect(regenerated.count == 4, "all four ops regenerated (not just dirty ones)")

    // 2. Clean ops got fresh G-code.
    try expect((profile.toolpathResult ?? "").contains("O=PROFILE_TOOLPATH"),
               "profile (was clean) regenerated with real engine")
    try expect((vcarve.toolpathResult ?? "").contains("O=V_CARVE_TOOLPATH"),
               "v-carve (was clean) regenerated with real engine")

    // All dirty flags cleared.
    try expect(tree.dirtyNodeCount == 0, "all ops clean after Recalc All")

    // 3. Unknown-strategy op skipped.
    let unknown = tree.addOperation("Fixture 1")
    unknown.toolpathResult = "// stub"
    let regen2 = tree.recalculateAllToolpaths(
        vectors: [square], material: nil, stockHeightMm: 25.0
    )
    try expect(regen2.count == 4, "unknown op not regenerated (still 4 supported)")
    try expect(unknown.toolpathResult == "// stub", "unknown op G-code untouched")

    // 4. Buffer rebuilds from full tree.
    let buffer = allToolpathGCode(from: tree)
    try expect(buffer.contains("O=PROFILE_TOOLPATH"), "buffer carries Profile")
    try expect(buffer.contains("O=POCKET_TOOLPATH"), "buffer carries Pocket")
    try expect(buffer.contains("O=DRILL_TOOLPATH"), "buffer carries Drill")
    try expect(buffer.contains("O=V_CARVE_TOOLPATH"), "buffer carries V-Carve")

    // 5. Empty tree is a no-op.
    let emptyTree = ToolpathTreeManager()
    let regenEmpty = emptyTree.recalculateAllToolpaths(
        vectors: [square], material: nil, stockHeightMm: 25.0
    )
    try expect(regenEmpty.isEmpty, "Recalc All on empty tree is a no-op")

    // 6. Stored pocket params respected.
    try expect((pocket.toolpathResult ?? "").contains("F1500"),
               "stored pocket feed F1500 respected on Recalc All")

    print("ShopPilotVerify0306: PASS — Recalculate All regenerates every op (clean+dirty); unknown skipped; buffer rebuild; stored params respected")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0306: FAIL — \(error)")
    exit(1)
}
