import Foundation
import ShopPilotCore

/// SPK-0802 remainder — V-Carve inlay recipe presets wired to the REAL
/// InlayToolpathEngine. The legacy stub had 4 preset recipes (30/45/60/90°)
/// that never touched an engine; this verifies the new VCarveInlayRecipe
/// presets materialize correct InlayToolpathParams and the pocket/plug
/// engines honor them (angle, depth, feeds).
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // 1. Preset catalog: the four classic angles exist with sensible depths.
    let presets = VCarveInlayRecipe.presets
    try expect(presets.count == 4, "4 preset recipes (got \(presets.count))")
    let angles = presets.map { $0.vBitAngleDegrees }
    try expect(Set(angles) == [30, 45, 60, 90], "angles 30/45/60/90 (got \(angles))")
    try expect(presets.allSatisfy { $0.inlayDepthMm > 0 }, "all presets have a positive depth")
    try expect(presets.allSatisfy { $0.feedRateMmPerMin > 0 && $0.plungeRateMmPerMin > 0 },
               "all presets have positive feeds")

    // 2. Named lookup.
    let fine = VCarveInlayRecipe.preset(named: "Fine 30° Inlay")
    try expect(fine != nil, "named lookup finds the 30° preset")
    try expect(abs((fine?.vBitAngleDegrees ?? 0) - 30) < 1e-9, "lookup returns the 30° recipe")
    try expect(VCarveInlayRecipe.preset(named: "Nope") == nil, "unknown name → nil")

    // 3. Recipe → params: variant preserved, recipe fields applied.
    let medium = VCarveInlayRecipe.preset(named: "Medium 45° Inlay")!
    var pocket = medium.params(variant: .pocket)
    try expect(pocket.variant == .pocket, "params variant = pocket")
    try expect(abs(pocket.vBitAngleDegrees - 45) < 1e-9, "params angle 45° (got \(pocket.vBitAngleDegrees))")
    try expect(abs(pocket.inlayDepthMm - 3.0) < 1e-9, "params depth 3.0 (got \(pocket.inlayDepthMm))")
    try expect(abs(pocket.feedRateMmPerMin - 800) < 1e-9, "params feed 800 (got \(pocket.feedRateMmPerMin))")
    try expect(abs(pocket.toolDiameterMm - 3.175) < 1e-9, "params tool Ø 3.175 (got \(pocket.toolDiameterMm))")

    // 4. Engine honors the recipe: pocket = flat-bottom V-Carve at −depth.
    let square = VectorPath(points: [pt(0, 0), pt(20, 0), pt(20, 20), pt(0, 20), pt(0, 0)], isClosed: true)
    let pocketResult = InlayToolpathEngine.computePocket(paths: [square], params: pocket)
    try expect(pocketResult.gcodeLines.contains("O=V_CARVE_TOOLPATH"),
               "pocket reuses the V-Carve engine (marker)")
    try expect(pocketResult.gcodeLines.contains { $0.hasPrefix("G1 Z") && $0.contains("-3.000") },
               "pocket floor at −3.000 (recipe depth) — got \(pocketResult.gcodeLines.filter { $0.hasPrefix("G1 Z") }.prefix(3))")

    // 5. Plug = Profile on-cut at the recipe depth.
    var plug = medium.params(variant: .plug)
    let plugResult = InlayToolpathEngine.computePlug(paths: [square], params: plug)
    try expect(plugResult.gcodeLines.contains("O=PROFILE_TOOLPATH"),
               "plug reuses the Profile engine (marker)")
    try expect(plugResult.gcodeLines.contains { $0.hasPrefix("G1 Z") && $0.contains("-3.000") },
               "plug depth −3.000 (recipe depth)")

    // 6. apply(to:) preserves variant but overwrites angle/depth/feeds.
    var custom = InlayToolpathParams()
    custom.variant = .plug
    custom.vBitAngleDegrees = 120
    let deep = VCarveInlayRecipe.preset(named: "Deep 90° Inlay")!
    deep.apply(to: &custom)
    try expect(custom.variant == .plug, "apply preserves variant")
    try expect(abs(custom.vBitAngleDegrees - 90) < 1e-9, "apply sets angle 90°")
    try expect(abs(custom.inlayDepthMm - 5.0) < 1e-9, "apply sets depth 5.0")

    // 7. Codable round-trip + legacy decode (defaults for missing keys).
    let data = try JSONEncoder().encode(fine)
    let back = try JSONDecoder().decode(VCarveInlayRecipe.self, from: data)
    let fineName = fine?.name ?? ""
    let fineAngle = fine?.vBitAngleDegrees ?? 0
    try expect(back.name == fineName && abs(back.vBitAngleDegrees - fineAngle) < 1e-9,
               "recipe round-trips")
    let legacy = """
    {"name":"Legacy 60°","vBitAngleDegrees":60,"inlayDepthMm":4.0}
    """.data(using: .utf8)!
    let legacyBack = try JSONDecoder().decode(VCarveInlayRecipe.self, from: legacy)
    try expect(legacyBack.name == "Legacy 60°" && abs(legacyBack.feedRateMmPerMin - 1200) < 1e-9,
               "legacy decode fills default feeds (got \(legacyBack.feedRateMmPerMin))")

    // 8. Tree recalc: an Inlay node with a recipe-derived paramsJSON
    // regenerates through the real engine when marked dirty.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Inlay Pocket 1")
    node.paramsJSON = String(data: try JSONEncoder().encode(pocket), encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [square], material: nil, stockHeightMm: 25.0
    )
    try expect(regenerated.count == 1, "dirty inlay node regenerates")
    try expect(regenerated[0].toolpathResult?.contains("O=V_CARVE_TOOLPATH") == true,
               "regenerated pocket has V-Carve marker")
    try expect(regenerated[0].isDirty == false, "node clears dirty after recalc")

    print("ShopPilotVerifyInlayRecipe: PASS — 4 presets, recipe→params, pocket/plug honor angle+depth, round-trip + legacy decode, tree recalc")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyInlayRecipe: FAIL — \(error)")
    exit(1)
}
