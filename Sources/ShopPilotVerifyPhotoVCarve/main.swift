import Foundation
import ShopPilotCore

/// SPK-0901 — Photo V-Carve: real V-bit raster where brightness → depth.
/// Dark pixels carve deep ((1 − luminance)·maxDepth added below the surface
/// offset), bright pixels stay high. Verifies the luminance mapping, the
/// raster structure, marker, persistence + legacy decode, and tree recalc.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 4×4 heightfield, 5mm cells: black (0) at (1,1), white (10) elsewhere.
    var heights = [Double](repeating: 10, count: 16)
    heights[1 * 4 + 1] = 0   // dark pixel → deepest carve
    heights[1 * 4 + 2] = 5   // mid gray
    let hf = HeightfieldData(width: 4, height: 4, cellSizeMm: 5, minX: 0, minY: 0, heights: heights)

    let params = PhotoVCarveToolpathParams(vBitAngleDegrees: 60, maxDepthMm: 3.0, stepOverMm: 5.0)
    let result = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: params)

    // 1. Marker + envelope.
    try expect(result.gcodeLines.contains("O=PHOTO_V_CARVE_TOOLPATH"), "photo v-carve marker")
    try expect(result.gcodeLines.first == "%" && result.gcodeLines.last == "%", "percent envelope")
    try expect(result.gcodeLines.contains("M30"), "M30 end")
    try expect(result.featureCount > 0, "at least one raster pass")

    // 2. Depth mapping: dark → deepest. Row 1 (cy = 7.5) contains the black
    //    pixel at col 1 (cx = 7.5) and mid gray at col 2 (cx = 12.5).
    //    z = −(stockTop − h) − (1 − h/maxH)·maxDepth
    //      black (h=0):   z = −(10−0) − 3.0        = −13.000
    //      mid (h=5):     z = −(10−5) − 1.5        = −6.500
    //      white (h=10):  z = −(10−10) − 0.0       = −0.000
    let rowLines = result.gcodeLines.filter { $0.hasPrefix("G1 X7.500 Y7.500 Z") || $0.hasPrefix("G1 X12.500 Y7.500 Z") }
    let dark = rowLines.first { $0.hasPrefix("G1 X7.500") }
    let mid = rowLines.first { $0.hasPrefix("G1 X12.500") }
    try expect(dark != nil, "dark pixel move present: \(rowLines)")
    try expect(dark?.contains("Z-13.000") == true, "black pixel carved to −13.000 (got \(dark ?? "nil"))")
    try expect(mid?.contains("Z-6.500") == true, "mid gray at −6.500 (got \(mid ?? "nil"))")

    // 3. Monotonicity: white cells stay at the surface (Z ≥ 0 line exists).
    try expect(result.gcodeLines.contains { $0.hasPrefix("G1 X") && $0.contains(" Z-0.000") },
               "white pixels cut at surface (Z −0.000)")

    // 4. Pass count scales with step-over (2 rows at 5mm over 4 cells).
    try expect(result.featureCount == 4, "4 raster passes at 5mm step-over on 4×4 (got \(result.featureCount))")

    // 5. Params round-trip + legacy decode.
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(PhotoVCarveToolpathParams.self, from: data)
    try expect(abs(back.maxDepthMm - 3.0) < 1e-9, "max depth round-trips")
    let legacy = "{\"vBitAngleDegrees\":45}".data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(PhotoVCarveToolpathParams.self, from: legacy)
    try expect(abs(legacyBack.vBitAngleDegrees - 45) < 1e-9 && abs(legacyBack.stepOverMm - 0.5) < 1e-9,
               "legacy decode keeps angle + default step-over")

    // 6. Tree recalc: a dirty Photo V-Carve node regenerates from the relief.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Photo V-Carve 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [], material: nil, stockHeightMm: 25.0, heightfield: hf
    )
    try expect(regenerated.count == 1, "dirty photo v-carve node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=PHOTO_V_CARVE_TOOLPATH") == true,
               "regenerated has photo v-carve marker")
    // Without a relief the node stays dirty (needs the image/STL).
    let tree2 = ToolpathTreeManager()
    let node2 = tree2.addOperation("Photo V-Carve 2")
    node2.markDirty()
    let none = tree2.recalculateDirtyToolpaths(vectors: [], material: nil, stockHeightMm: 25.0)
    try expect(none.isEmpty, "no relief → node stays dirty, nothing regenerated")

    print("ShopPilotVerifyPhotoVCarve: PASS — luminance→depth (black −13.0/mid −6.5/white 0), raster passes, round-trip + legacy decode, tree recalc")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyPhotoVCarve: FAIL — \(error)")
    exit(1)
}
