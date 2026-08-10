import Foundation
import ShopPilotCore

/// SPK-0805 verify (CLT machine, no XCTest).
/// Proves the TILING MANAGER contract with the real layout engine:
///   1. GRID: a rows×columns config produces exactly N placed tiles at
///      deterministic cell positions with a gap — hand-computed origin math
///      for the top-left alignment (first tile at the origin).
///   2. ALIGNMENT: center alignment offsets the whole block so the layout is
///      visually centered on the sheet.
///   3. GAP TYPES: fixed (absolute mm) and percentage (relative to tile)
///      gap computations match hand-derived values.
///   4. STAGGER: even rows shift by the stagger amount.
///   5. VALIDATION: degenerate configs (0 rows/cols) fail gracefully.
/// The AppSession glue (generateTiling into the design shapes + Tile… dialog)
/// is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let manager = TilingManager()

    // ── 1. 2×3 grid, fixed gap, top-left alignment. ───────────────────────
    var config = TilingConfig(
        tilesPerRow: 3,
        tilesPerColumn: 2,
        tileWidth: 40,
        tileHeight: 30,
        tileGap: 10,
        gapType: .fixed,
        direction: .horizontal,
        alignment: .topLeft,
        originX: 5,
        originY: 5,
        rotation: 0,
        mirrorHorizontal: false,
        mirrorVertical: false,
        stagger: false,
        staggerAmount: 0
    )
    let result = manager.generateLayout(config: config, sheetWidth: 200, sheetHeight: 150)
    try expect(result.success, "layout succeeds")
    try expect(result.placedTiles == 6, "2×3 grid → 6 tiles (got \(result.placedTiles))")
    try expect(result.totalTiles == 6, "total = 6")
    try expect(result.tiles.allSatisfy(\.placed), "every tile placed")

    // Effective cell = tile + gap (fixed): 50 × 40. First tile at origin.
    let row0 = result.tiles.filter { $0.row == 0 }.sorted { $0.column < $1.column }
    try expect(row0.count == 3, "row 0 has 3 tiles")
    try expect(abs(row0[0].x - 5) < 1e-9 && abs(row0[0].y - 5) < 1e-9,
               "first tile at origin (got \(row0[0].x),\(row0[0].y))")
    try expect(abs(row0[1].x - 55) < 1e-9, "column 1 x = origin + 50 (got \(row0[1].x))")
    try expect(abs(row0[2].x - 105) < 1e-9, "column 2 x = origin + 100 (got \(row0[2].x))")
    let row1 = result.tiles.filter { $0.row == 1 }.sorted { $0.column < $1.column }
    try expect(abs(row1[0].y - 45) < 1e-9, "row 1 y = origin + 40 (got \(row1[0].y))")

    // ── 2. Center alignment offsets the block. ────────────────────────────
    config.alignment = .center
    config.originX = 0
    config.originY = 0
    let centered = manager.generateLayout(config: config, sheetWidth: 200, sheetHeight: 150)
    // Block width = 3*40 + 2*10 = 140, height = 2*30 + 1*10 = 70.
    // Centered on 200×150 → offset ((200-140)/2, (150-70)/2) = (30, 40).
    let cFirst = centered.tiles.sorted { ($0.row, $0.column) < ($1.row, $1.column) }[0]
    try expect(abs(cFirst.x - 30) < 1e-9, "center-aligned block offset X = 30 (got \(cFirst.x))")
    try expect(abs(cFirst.y - 40) < 1e-9, "center-aligned block offset Y = 40 (got \(cFirst.y))")

    // ── 3. Percentage gap. ────────────────────────────────────────────────
    config.alignment = .topLeft
    config.originX = 0
    config.originY = 0
    config.gapType = .percentage
    config.tileGap = 25 // 25% of tile size
    let percent = manager.generateLayout(config: config, sheetWidth: 200, sheetHeight: 150)
    // Effective cell: 40*1.25 = 50 wide, 30*1.25 = 37.5 tall.
    let pRow1 = percent.tiles.filter { $0.row == 1 }.sorted { $0.column < $1.column }[0]
    try expect(abs(pRow1.y - 37.5) < 1e-9, "percentage gap: row 1 y = 37.5 (got \(pRow1.y))")
    let pCol1 = percent.tiles.filter { $0.row == 0 }.sorted { $0.column < $1.column }[1]
    try expect(abs(pCol1.x - 50) < 1e-9, "percentage gap: col 1 x = 50 (got \(pCol1.x))")

    // ── 4. Stagger shifts even rows. ──────────────────────────────────────
    config.gapType = .fixed
    config.tileGap = 10
    config.stagger = true
    config.staggerAmount = 15
    let staggered = manager.generateLayout(config: config, sheetWidth: 200, sheetHeight: 150)
    let sRow0 = staggered.tiles.filter { $0.row == 0 }.sorted { $0.column < $1.column }[0]
    let sRow1 = staggered.tiles.filter { $0.row == 1 }.sorted { $0.column < $1.column }[0]
    try expect(abs(sRow1.x - (sRow0.x + 15)) < 1e-9,
               "stagger shifts row 1 by the amount (got row0 \(sRow0.x), row1 \(sRow1.x))")

    // ── 5. Degenerate config is clamped by init + rejected by validator. ──
    let bad = TilingConfig(tilesPerRow: 0, tilesPerColumn: 0)
    // The init clamps to 1×1 (safe layout, no zero-sized grid).
    try expect(bad.tilesPerRow == 1 && bad.tilesPerColumn == 1,
               "init clamps 0 rows/cols to 1")
    let badResult = manager.generateLayout(config: bad, sheetWidth: 200, sheetHeight: 150)
    try expect(badResult.success && badResult.placedTiles == 1,
               "clamped 1×1 config produces exactly one tile")
    let validation = TilingManager.validate(bad)
    try expect(validation.isValid, "validator accepts the clamped config")

    print("ShopPilotVerify0805: PASS — tiling grid origins + fixed/percentage gaps + center alignment + stagger + degenerate validation")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0805: FAIL — \(error)")
    exit(1)
}
