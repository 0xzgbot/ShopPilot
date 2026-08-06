import Foundation
import ShopPilotCore

/// SPK-0900 remainder — Texture toolpath: parallel or crosshatch grooves
/// clipped inside closed vectors. Verifies the boundary clipping (runs stay
/// inside), the V-groove depth formula, crosshatch = 2× passes at θ and θ+90,
/// flat mode, marker, persistence + legacy decode, and tree recalc.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // 20×20 square boundary.
    let square = VectorPath(points: [pt(0, 0), pt(20, 0), pt(20, 20), pt(0, 20), pt(0, 0)], isClosed: true)

    // 1. Parallel V-grooves at 5mm spacing: 4 grooves (y = 2.5…17.5),
    //    depth = min(runWidth=20, spacing=5) / (2·tan(45°)) = 2.5mm.
    let parallel = TextureToolpathParams(pattern: .parallel, spacingMm: 5, angleDegrees: 0,
                                         cutStyle: .vGroove, vBitAngleDegrees: 90)
    let r1 = TextureToolpathEngine.compute(paths: [square], params: parallel)
    try expect(r1.gcodeLines.contains("O=TEXTURE_TOOLPATH"), "texture marker")
    try expect(r1.featureCount == 4, "4 parallel grooves at 5mm spacing (got \(r1.featureCount))")
    let zLines = r1.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(zLines.allSatisfy { $0.contains("-2.500") }, "V-groove depth −2.500 (got \(zLines.prefix(3)))")
    // Runs are clipped inside the boundary: first groove starts at x=0, ends x=20.
    try expect(r1.gcodeLines.contains { $0 == "G0 X0.000 Y2.500" }, "first groove at y=2.5, x=0")
    try expect(r1.gcodeLines.contains { $0 == "G1 X20.000 Y2.500 F1500" }, "first groove spans to x=20")

    // 2. Max depth cap respected.
    let capped = TextureToolpathParams(pattern: .parallel, spacingMm: 5, angleDegrees: 0,
                                       cutStyle: .vGroove, vBitAngleDegrees: 90, maxDepthMm: 1.0)
    let r2 = TextureToolpathEngine.compute(paths: [square], params: capped)
    let zLines2 = r2.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(zLines2.allSatisfy { $0.contains("-1.000") }, "max depth caps at −1.000 (got \(zLines2.prefix(2)))")

    // 3. Crosshatch = 2× grooves (θ and θ+90).
    let cross = TextureToolpathParams(pattern: .crosshatch, spacingMm: 5, angleDegrees: 0,
                                      cutStyle: .vGroove, vBitAngleDegrees: 90)
    let r3 = TextureToolpathEngine.compute(paths: [square], params: cross)
    try expect(r3.featureCount == 8, "crosshatch doubles grooves to 8 (got \(r3.featureCount))")

    // 4. Flat mode: constant depth, no angle-derived depth.
    let flat = TextureToolpathParams(pattern: .parallel, spacingMm: 5, angleDegrees: 0,
                                     cutStyle: .flat, flatDepthMm: 1.5)
    let r4 = TextureToolpathEngine.compute(paths: [square], params: flat)
    let zLines4 = r4.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(zLines4.allSatisfy { $0.contains("-1.500") }, "flat depth −1.500 (got \(zLines4.prefix(2)))")

    // 5. 45° angle: grooves still clipped inside; endpoints differ from 0°.
    let angled = TextureToolpathParams(pattern: .parallel, spacingMm: 5, angleDegrees: 45,
                                       cutStyle: .vGroove, vBitAngleDegrees: 90)
    let r5 = TextureToolpathEngine.compute(paths: [square], params: angled)
    try expect(r5.featureCount == 6, "6 grooves at 45° — rotated bbox diagonal 28.28mm / 5mm (got \(r5.featureCount))")
    try expect(!r5.gcodeLines.contains { $0 == "G0 X0.000 Y2.500" },
               "45° run does not start at (0, 2.5)")
    // All groove endpoints must lie within the 20×20 boundary (clip check).
    func coord(_ s: String, _ axis: Character) -> Double {
        guard let r = s.firstIndex(of: axis) else { return -999 }
        let rest = String(s[s.index(after: r)...])
        let num = rest.prefix { $0 != " " && $0 != "F" }
        return Double(num) ?? -999
    }
    for line in r5.gcodeLines where line.hasPrefix("G1 X") || line.hasPrefix("G0 X") {
        let x = coord(line, "X")
        let y = coord(line, "Y")
        try expect(x >= -1e-6 && x <= 20 + 1e-6, "groove x within boundary (got \(x))")
        try expect(y >= -1e-6 && y <= 20 + 1e-6, "groove y within boundary (got \(y))")
    }

    // 6. Degenerate paths (fewer than 3 points) produce no grooves; the
    //    boundary helper rejects them (open paths with ≥3 points auto-close,
    //    matching the Prism engine's shared contract).
    let degenerate = VectorPath(points: [pt(0, 0), pt(10, 0)], isClosed: false)
    let r6 = TextureToolpathEngine.compute(paths: [degenerate], params: parallel)
    try expect(r6.featureCount == 0, "2-point path → 0 grooves (got \(r6.featureCount))")

    // 7. Params round-trip + legacy decode.
    let data = try JSONEncoder().encode(cross)
    let back = try JSONDecoder().decode(TextureToolpathParams.self, from: data)
    try expect(back.pattern == .crosshatch, "crosshatch pattern round-trips")
    let legacy = "{\"pattern\":\"parallel\",\"spacingMm\":8}".data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(TextureToolpathParams.self, from: legacy)
    try expect(legacyBack.pattern == .parallel && abs(legacyBack.spacingMm - 8) < 1e-9,
               "legacy decode keeps pattern + spacing, defaults for rest")

    // 8. Tree recalc: dirty Texture node regenerates.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Texture 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(vectors: [square], material: nil, stockHeightMm: 25.0)
    try expect(regenerated.count == 1, "dirty texture node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=TEXTURE_TOOLPATH") == true,
               "regenerated has texture marker")

    print("ShopPilotVerifyTexture: PASS — parallel 4 grooves @−2.5, cap, crosshatch 8, flat −1.5, 45° clip, open-path skip, round-trip + legacy decode, tree recalc")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyTexture: FAIL — \(error)")
    exit(1)
}
