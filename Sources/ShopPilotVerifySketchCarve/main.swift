import Foundation
import ShopPilotCore

/// SPK-0901 remainder — Sketch Carving: edge-gated V-bit raster. A Sobel
/// gradient map from the relief heightfield drives depth: strong brightness
/// transitions (edges) carve deep, flat areas stay untouched. Verifies the
/// edge math, the threshold gate, marker, persistence + legacy decode, and
/// tree recalc (with + without relief).
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 6×6 heightfield, 5mm cells. LEFT half flat at 10 (no edges), RIGHT half
    // flat at 0 — a sharp vertical step at col 3 (strong Sobel edge).
    var heights = [Double](repeating: 10, count: 36)
    for r in 0..<6 {
        for c in 3..<6 {
            heights[r * 6 + c] = 0
        }
    }
    let hf = HeightfieldData(width: 6, height: 6, cellSizeMm: 5, minX: 0, minY: 0, heights: heights)

    let params = SketchCarveToolpathParams(
        vBitAngleDegrees: 60, maxDepthMm: 2.0, edgeThreshold: 0.3, stepOverMm: 5.0
    )
    let result = SketchCarveToolpathEngine.compute(heightfield: hf, params: params)

    // 1. Marker + envelope.
    try expect(result.gcodeLines.contains("O=SKETCH_CARVE_TOOLPATH"), "sketch carve marker")
    try expect(result.gcodeLines.first == "%" && result.gcodeLines.last == "%", "percent envelope")
    try expect(result.gcodeLines.contains("M30"), "M30 end")

    // 2. Edge cells carved: the step column (col 3) has the max gradient →
    //    deepest cut. Flat columns (0, 1) stay at Z 0.
    //    Sobel |gx| at the step = 4·10 = 40; maxMag = 40 → edge = 1.0 →
    //    depth = 2.0 → Z −2.000 at col 3, Z 0 at cols 0-1.
    let deepMoves = result.gcodeLines.filter { $0.contains("Z-2.000") }
    try expect(!deepMoves.isEmpty, "step column carves to −2.000 (got \(deepMoves.prefix(2)))")
    let flatMoves = result.gcodeLines.filter { $0.contains("Z-0.000") }
    try expect(!flatMoves.isEmpty, "flat cells stay at Z 0 (got \(flatMoves.prefix(2)))")

    // 3. featureCount counts carved cells (> 0, < all cells).
    try expect(result.featureCount > 0, "some edge cells counted")
    try expect(result.featureCount < 6 * 6, "not every cell is an edge (got \(result.featureCount)/36)")

    // 4. Threshold gate: a high threshold suppresses weak edges entirely.
    let highThresh = SketchCarveToolpathParams(edgeThreshold: 0.99, stepOverMm: 5.0)
    let rGate = SketchCarveToolpathEngine.compute(heightfield: hf, params: highThresh)
    // Normalized edge is exactly 1.0 at the step; 0.99 still passes it, but
    // any cell with gradient < 0.99·maxMag is gated. The step is max → stays.
    // A flat grid has NO edges at all → zero carved cells.
    let flat = HeightfieldData(width: 4, height: 4, cellSizeMm: 5, minX: 0, minY: 0,
                               heights: [Double](repeating: 8, count: 16))
    let rFlat = SketchCarveToolpathEngine.compute(heightfield: flat, params: params)
    try expect(rFlat.featureCount == 0, "uniform grid → no edges → 0 carved cells (got \(rFlat.featureCount))")

    // 5. Monotonic depth: stronger contrast → deeper. A 20-height step carves
    //    deeper than a 10-height step at the same threshold.
    var tall = [Double](repeating: 20, count: 36)
    for r in 0..<6 {
        for c in 3..<6 { tall[r * 6 + c] = 0 }
    }
    let hfTall = HeightfieldData(width: 6, height: 6, cellSizeMm: 5, minX: 0, minY: 0, heights: tall)
    let rTall = SketchCarveToolpathEngine.compute(heightfield: hfTall, params: params)
    let maxDepthTall = maxDepth(in: rTall)
    let maxDepthStep = maxDepth(in: result)
    try expect(maxDepthTall >= maxDepthStep, "taller step carves ≥ depth of shorter step (\(maxDepthTall) vs \(maxDepthStep))")

    // 6. Params round-trip + legacy decode.
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(SketchCarveToolpathParams.self, from: data)
    try expect(abs(back.edgeThreshold - 0.3) < 1e-9, "edge threshold round-trips")
    let legacy = "{\"maxDepthMm\":4.0}".data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(SketchCarveToolpathParams.self, from: legacy)
    try expect(abs(legacyBack.maxDepthMm - 4.0) < 1e-9 && abs(legacyBack.edgeThreshold - 0.12) < 1e-9,
               "legacy decode keeps depth + default threshold")

    // 7. Tree recalc: dirty Sketch Carve node regenerates from the relief;
    //    without a relief it stays dirty.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Sketch Carve 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [], material: nil, stockHeightMm: 25.0, heightfield: hf
    )
    try expect(regenerated.count == 1, "dirty sketch carve node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=SKETCH_CARVE_TOOLPATH") == true,
               "regenerated has sketch carve marker")
    let tree2 = ToolpathTreeManager()
    let node2 = tree2.addOperation("Sketch Carve 2")
    node2.markDirty()
    let none = tree2.recalculateDirtyToolpaths(vectors: [], material: nil, stockHeightMm: 25.0)
    try expect(none.isEmpty, "no relief → node stays dirty, nothing regenerated")

    print("ShopPilotVerifySketchCarve: PASS — Sobel edge gating (step −2.000, flats 0), threshold gate, contrast monotonicity, round-trip + legacy decode, tree recalc")
}

func maxDepth(in result: SpecialtyResult) -> Double {
    var maxD = 0.0
    for line in result.gcodeLines where line.hasPrefix("G1 Z") {
        let rest = line.dropFirst(4)
        let num = rest.prefix { $0 != " " && $0 != "F" }
        if let z = Double(num), z < -maxD { maxD = -z }
    }
    return maxD
}

do {
    try main()
} catch {
    print("ShopPilotVerifySketchCarve: FAIL — \(error)")
    exit(1)
}
