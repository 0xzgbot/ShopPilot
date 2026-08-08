import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-ModelOffset verify (CLT machines, no XCTest).
/// Proves `ModelOffsetEngine` (parity row E22 — offset model):
///   1. Dilation: +1.0 on a flat grid with one raised center cell raises the
///      boundary ring (neighbors of the raised cell rise above the floor).
///   2. Erosion: -1.0 lowers the raised cell's edge cells toward the floor.
///   3. offset 0 → identity (changedCellCount 0, heights identical).
///   4. Codable round-trip of params + result (HeightfieldData is Codable).
///   5. Uniform grid (no material boundary) → no-op for both +1 and -1.
///   6. Grid with all cells material (no floor) → no-op (only material cells).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func flatGrid(_ size: Int = 8, cellSize: Double = 1.0, raisedCenter: Double? = nil) -> HeightfieldData {
    let mid = size / 2
    var heights = [Double](repeating: 0, count: size * size)
    if let raised = raisedCenter {
        heights[mid * size + mid] = raised
    }
    return HeightfieldData(width: size, height: size, cellSizeMm: cellSize, minX: 0, minY: 0, heights: heights)
}

func main() throws {
    // ── 1. Dilation (+1.0) ────────────────────────────────────────────────
    let grid = flatGrid(raisedCenter: 5.0)
    let dilated = ModelOffsetEngine.offset(
        heightfield: grid,
        params: .init(offsetMm: 1.0)
    )
    try expect(dilated != nil, "dilation returns a result")
    let d = dilated!
    try expect(d.changedCellCount > 0, "dilation changes cells (got \(d.changedCellCount))")
    // The center stays at (or above) its original height.
    let mid = 4, w = 8
    let centerHeight = d.heightfield.heights[mid * w + mid]
    try expect(centerHeight >= 5.0 - 1e-9, "center retains height (got \(centerHeight))")
    // At least one of the 8 neighbors of the center cell rises above the floor.
    let neighbors = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
    var anyNeighborRaised = false
    for (di, dj) in neighbors {
        let i = mid + di, j = mid + dj
        guard i >= 0, i < w, j >= 0, j < 8 else { continue }
        if d.heightfield.heights[j * w + i] > 0.01 { anyNeighborRaised = true }
    }
    try expect(anyNeighborRaised, "dilation raises a boundary neighbor")
    try expect(d.maxHeightAfter >= 5.0, "max height after dilation >= 5.0 (got \(d.maxHeightAfter))")

    // ── 2. Erosion (-1.0) ─────────────────────────────────────────────────
    let eroded = ModelOffsetEngine.offset(
        heightfield: grid,
        params: .init(offsetMm: -1.0)
    )
    try expect(eroded != nil, "erosion returns a result")
    let e = eroded!
    try expect(e.changedCellCount > 0, "erosion changes cells (got \(e.changedCellCount))")
    // The raised cell itself drops below 5.0 (its own edge is inside the band
    // when the solid is only one cell tall: boundary distance 1.0 ≤ band).
    let erodedCenter = e.heightfield.heights[mid * w + mid]
    try expect(erodedCenter < 5.0 - 1e-9, "erosion lowers the raised cell (got \(erodedCenter))")

    // ── 3. Zero offset → identity ─────────────────────────────────────────
    let identity = ModelOffsetEngine.offset(
        heightfield: grid,
        params: .init(offsetMm: 0)
    )
    try expect(identity != nil, "zero offset returns a result")
    try expect(identity!.changedCellCount == 0, "zero offset changes nothing")
    try expect(identity!.heightfield.heights == grid.heights, "zero offset keeps heights")

    // ── 4. Codable round-trip ─────────────────────────────────────────────
    let params = ModelOffsetEngine.OffsetParams(offsetMm: 2.5, taperDegrees: 5)
    let enc = JSONEncoder()
    let dec = JSONDecoder()
    let paramsData = try enc.encode(params)
    let paramsBack = try dec.decode(ModelOffsetEngine.OffsetParams.self, from: paramsData)
    try expect(paramsBack.offsetMm == 2.5 && paramsBack.taperDegrees == 5, "params round-trip")
    let resultData = try enc.encode(d)
    let resultBack = try dec.decode(ModelOffsetEngine.OffsetResult.self, from: resultData)
    try expect(resultBack.heightfield.width == d.heightfield.width, "result round-trip width")
    try expect(resultBack.changedCellCount == d.changedCellCount, "result round-trip changed count")
    try expect(resultBack.heightfield.heights == d.heightfield.heights, "result round-trip heights")

    // ── 5. Uniform grid (no material) → no-op ─────────────────────────────
    let flat = flatGrid(raisedCenter: nil)
    for sign in [1.0, -1.0] {
        let r = ModelOffsetEngine.offset(heightfield: flat, params: .init(offsetMm: sign))
        try expect(r != nil, "uniform grid +\(sign) returns a result")
        try expect(r!.changedCellCount == 0, "uniform grid +\(sign) changes nothing")
        try expect(r!.heightfield.heights == flat.heights, "uniform grid +\(sign) keeps heights")
    }

    // ── 6. All-material grid → no-op ──────────────────────────────────────
    let allMaterial = HeightfieldData(
        width: 4, height: 4, cellSizeMm: 1.0, minX: 0, minY: 0,
        heights: [Double](repeating: 3.0, count: 16)
    )
    let r = ModelOffsetEngine.offset(heightfield: allMaterial, params: .init(offsetMm: 1.0))
    try expect(r != nil, "all-material grid returns a result")
    try expect(r!.changedCellCount == 0, "all-material grid changes nothing (no floor)")

    print("ShopPilotVerifyModelOffset: PASS — dilation raises boundary ring, erosion insets, zero identity, Codable round-trip, uniform/all-material no-ops")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyModelOffset: FAIL — \(error)")
    exit(1)
}
