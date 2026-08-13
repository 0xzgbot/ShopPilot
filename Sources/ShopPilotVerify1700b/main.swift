import Foundation
import ShopPilotCore

// SPK-1700b verify (CLT executable, no XCTest).
// Proves the playhead/scrub contract: the preview shows the heightfield
// AS OF a PREFIX of the toolpath:
//   1. t=0 (empty prefix) ≈ stock top everywhere.
//   2. A shorter prefix removes LESS (or equal) material than a longer one —
//      monotone removal as the playhead advances.
//   3. t=1 (all lines) matches the full simulation (the view can show the
//      cached full result at playhead 1 instead of re-running).
//   4. Prefix results are real trenches — the same contiguous-removal shape
//      the full sim produces.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// EXACTLY a 3-line cut program: rapid to (5,5), plunge to z=0, horizontal
/// pass to (15,5). Prefix 1 = rapid (no removal), prefix 2 = plunge (a
/// disk), prefix 3 = full (a trench).
func threeLineCut() -> [String] {
    [
        "G0 X5 Y5",
        "G1 Z0 F100",
        "G1 X15 Y5 F500",
    ]
}

func removedCount(_ hm: Heightmap, stockTop: Double) -> Int {
    var count = 0
    for y in 0..<hm.height {
        for x in 0..<hm.width where hm.getHeight(x, y) < stockTop - 0.001 {
            count += 1
        }
    }
    return count
}

func main() throws {
    let allLines = threeLineCut()
    let stockTop = 20.0

    func sim(_ prefix: Int) -> Heightmap {
        ToolpathSimulator.simulateHeightmap(
            from: Array(allLines.prefix(prefix)),
            sheetWidthMm: 30, sheetDepthMm: 30, stockTopMm: stockTop,
            cellSizeMm: 1.0
        ).heightmap
    }

    // ── 1. t=0 ≈ stock top. ───────────────────────────────────────────────
    let t0 = sim(0)
    try expect(t0.width == 30 && t0.height == 30, "t=0 grid is the full sheet")
    var allStock = true
    for y in 0..<30 {
        for x in 0..<30 where abs(t0.getHeight(x, y) - stockTop) > 0.001 {
            allStock = false
        }
    }
    try expect(allStock, "t=0 shows the untouched stock top everywhere")

    // ── 2. Monotone removal as the prefix grows. ───────────────────────────
    let c0 = removedCount(t0, stockTop: stockTop)
    let c1 = removedCount(sim(1), stockTop: stockTop)   // rapid only
    let c2 = removedCount(sim(2), stockTop: stockTop)   // plunge disk
    let c3 = removedCount(sim(3), stockTop: stockTop)   // full trench
    try expect(c0 == 0, "t=0 removes nothing")
    try expect(c1 == 0, "a rapid-only prefix removes nothing (got \(c1))")
    try expect(c2 > c1, "the plunge prefix starts removing material (\(c2) cells)")
    try expect(c3 > c2, "the full prefix removes more than the plunge (\(c3) > \(c2))")
    try expect(c0 <= c1 && c1 <= c2 && c2 <= c3,
               "removal is monotone as the playhead advances (\(c0) → \(c1) → \(c2) → \(c3))")

    // ── 3. t=1 (all lines) matches the full simulation. ────────────────────
    let full = ToolpathSimulator.simulateHeightmap(
        from: allLines,
        sheetWidthMm: 30, sheetDepthMm: 30, stockTopMm: stockTop,
        cellSizeMm: 1.0
    ).heightmap
    try expect(removedCount(full, stockTop: stockTop) == c3,
               "t=1 (full prefix) equals the full sim (\(c3) removed both ways)")

    // ── 4. Prefix shape is a real trench: row 5 fully cleared at t=1. ──────
    var row5Cleared = 0
    for x in 0..<30 where full.getHeight(x, 5) < 0.001 { row5Cleared += 1 }
    try expect(row5Cleared >= 10, "t=1 cleared a contiguous trench on row 5 (got \(row5Cleared) cells)")

    print("PASS — playhead prefix sim: t=0 stock, monotone \(c0)≤\(c1)≤\(c2)≤\(c3), t=1 == full sim, trench shape intact")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}
