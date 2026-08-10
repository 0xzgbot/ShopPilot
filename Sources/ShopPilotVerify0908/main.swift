import Foundation
import ShopPilotCore

/// SPK-0908 verify (CLT machine, no XCTest).
/// Proves the LEVEL MIRROR MODES contract with the real grid engine:
///   1. HORIZONTAL (X): cell (x, y) reads source (w−1−x, y) — a peak on the
///      left moves to the right; world origin + dims stay fixed.
///   2. VERTICAL (Y): cell (x, y) reads source (x, h−1−y) — top ↔ bottom.
///   3. BOTH: flips both axes (180° rotation of the grid content).
///   4. DOUBLE-MIRROR IDENTITY: mirroring X twice restores the original grid
///      (the transform is its own inverse).
///   5. LEVEL METADATA: `Level.mirrorMode` records the applied axis and
///      round-trips through Codable; legacy levels decode nil (unmirrored).
/// The AppSession glue (mirrorActiveRelief / mirrorLevel + Model-stage Mirror
/// menu) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// 3×2 grid: row 0 = [1, 2, 3], row 1 = [4, 5, 6].
func makeGrid() -> HeightfieldData {
    HeightfieldData(width: 3, height: 2, cellSizeMm: 1.0, minX: 0, minY: 0,
                    heights: [1, 2, 3, 4, 5, 6])
}

func main() throws {
    let grid = makeGrid()

    // ── 1. Horizontal (X) mirror: row 0 becomes [3, 2, 1]. ────────────────
    let h = LevelMirrorEngine.mirror(grid, axis: .horizontal)
    try expect(h.width == 3 && h.height == 2, "dims preserved")
    try expect(h.minX == 0 && h.minY == 0, "world origin preserved")
    try expect(h.heights[0] == 3 && h.heights[1] == 2 && h.heights[2] == 1,
               "row 0 flipped to [3,2,1] (got \(h.heights[0..<3]))")
    try expect(h.heights[3] == 6 && h.heights[5] == 4,
               "row 1 flipped to [6,5,4]")

    // ── 2. Vertical (Y) mirror: rows swap. ────────────────────────────────
    let v = LevelMirrorEngine.mirror(grid, axis: .vertical)
    try expect(v.heights[0] == 4 && v.heights[2] == 6, "top row now [4,5,6]")
    try expect(v.heights[3] == 1 && v.heights[5] == 3, "bottom row now [1,2,3]")

    // ── 3. Both: 180° content rotation. ───────────────────────────────────
    let b = LevelMirrorEngine.mirror(grid, axis: .both)
    try expect(b.heights[0] == 6 && b.heights[2] == 4, "both → [6,5,4] top")
    try expect(b.heights[3] == 3 && b.heights[5] == 1, "both → [3,2,1] bottom")

    // ── 4. Double-mirror identity. ────────────────────────────────────────
    let twice = LevelMirrorEngine.mirror(LevelMirrorEngine.mirror(grid, axis: .horizontal), axis: .horizontal)
    try expect(twice.heights == grid.heights, "mirror X twice restores the original")
    let twiceV = LevelMirrorEngine.mirror(LevelMirrorEngine.mirror(grid, axis: .vertical), axis: .vertical)
    try expect(twiceV.heights == grid.heights, "mirror Y twice restores the original")

    // ── 5. Level metadata: mirrorMode records + round-trips. ──────────────
    var level = Level(name: "Detail", components: [UUID()])
    try expect(level.mirrorMode == nil, "fresh level is unmirrored")
    level.mirrorMode = .horizontal
    let data = try JSONEncoder().encode(level)
    let back = try JSONDecoder().decode(Level.self, from: data)
    try expect(back.mirrorMode == .horizontal, "mirrorMode round-trips")
    try expect(back.components.count == 1, "components preserved")

    // Legacy Level JSON without mirrorMode decodes nil.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","components":[],"visible":true,"locked":false,"opacity":1.0,"blendMode":"normal"}"#
    let legacy = try JSONDecoder().decode(Level.self, from: Data(legacyJSON.utf8))
    try expect(legacy.mirrorMode == nil, "legacy level decodes unmirrored")

    print("ShopPilotVerify0908: PASS — grid mirror X/Y/both with world origin fixed, double-mirror identity, level mirrorMode persist + legacy nil")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0908: FAIL — \(error)")
    exit(1)
}
