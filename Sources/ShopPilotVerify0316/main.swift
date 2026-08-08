import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0316 verify (CLT machines, no XCTest).
/// Proves the ghost-diff engine (`PathDiffEngine`) that powers the
/// old-vs-new toolpath overlay:
///   1. comparePaths: identical paths → no differences, all unchanged.
///   2. comparePaths: added/removed points detected with tolerance.
///   3. comparePaths: moved points detected (original vs updated pair).
///   4. compareGCode: parses X/Y from G0/G1 lines and diffs them.
///   5. generateGhostData: maps a diff to added points + moved lines.
///   6. DirtyRegionManager regression: mark/clear + needsResimulation flag
///      (the resim trigger SPK-0315 hangs off).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Identical paths ────────────────────────────────────────────────
    let same = PathDiffEngine.comparePaths(
        original: [(0, 0), (10, 0), (10, 10)],
        updated: [(0, 0), (10, 0), (10, 10)]
    )
    try expect(!same.hasDifferences, "identical paths → no differences")
    try expect(same.unchangedPointCount == 3, "identical paths → all unchanged")

    // ── 2. Added / removed points ─────────────────────────────────────────
    let added = PathDiffEngine.comparePaths(
        original: [(0, 0), (10, 0)],
        updated: [(0, 0), (10, 0), (20, 0)]
    )
    try expect(added.hasDifferences, "extra point → differences")
    try expect(added.addedPoints.count == 1, "one added point (got \(added.addedPoints.count))")
    let removed = PathDiffEngine.comparePaths(
        original: [(0, 0), (10, 0), (20, 0)],
        updated: [(0, 0), (10, 0)]
    )
    try expect(removed.removedPoints.count == 1, "one removed point (got \(removed.removedPoints.count))")

    // ── 3. Moved points (within tolerance) ────────────────────────────────
    let moved = PathDiffEngine.comparePaths(
        original: [(0, 0), (10, 0), (10, 10)],
        updated: [(0, 0), (12, 0), (10, 10)]   // (10,0) → (12,0) = 2mm move
    )
    try expect(moved.hasDifferences, "moved point → differences")
    try expect(moved.movedPoints.count >= 1, "moved pair detected (got \(moved.movedPoints.count))")
    try expect(moved.movedPoints.contains(where: { $0.original.0 == 10 && $0.original.1 == 0 }),
               "original side of the move is (10,0)")

    // ── 4. compareGCode parses + diffs ────────────────────────────────────
    let oldGcode = """
    G0 X0 Y0
    G1 X10 Y0 F300
    G1 X10 Y10
    """
    let newGcode = """
    G0 X0 Y0
    G1 X10 Y0 F300
    G1 X10 Y20
    """
    let gcodeDiff = PathDiffEngine.compareGCode(oldGcode, newGcode)
    try expect(gcodeDiff.hasDifferences, "G-code change → differences")
    try expect(gcodeDiff.updatedPointCount == 3, "3 movement points parsed from G-code")
    try expect(gcodeDiff.movedPoints.count >= 1 || gcodeDiff.addedPoints.count >= 1,
               "G-code diff reports moved/added points")

    // ── 5. generateGhostData ──────────────────────────────────────────────
    let ghost = PathDiffEngine.generateGhostData(from: moved)
    try expect(!ghost.addedPoints.isEmpty || !ghost.removedPoints.isEmpty || !ghost.movedLines.isEmpty,
               "ghost data has visible elements")
    try expect(ghost.movedLines.count == moved.movedPoints.count,
               "one ghost line per moved pair")

    // ── 6. DirtyRegionManager (the 0315 resim trigger) ────────────────────
    let manager = DirtyRegionManager()
    try expect(!manager.needsResimulation, "fresh manager does not need resim")
    manager.markVectorModified(UUID())
    try expect(manager.needsResimulation, "vector modified → needs resim")
    try expect(!manager.dirtyRegions.isEmpty, "dirty region recorded")
    manager.clearDirtyRegions()
    try expect(!manager.needsResimulation, "cleared → no resim needed")
    try expect(manager.dirtyRegions.isEmpty, "cleared → no dirty regions")
    manager.markFullTreeDirty()
    try expect(manager.needsResimulation, "full-tree dirty → needs resim")

    print("ShopPilotVerify0316: PASS — identical/add/remove/move detection, G-code parse+diff, ghost data, DirtyRegionManager trigger")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0316: FAIL — \(error)")
    exit(1)
}
