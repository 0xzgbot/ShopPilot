import Foundation
import ShopPilotCore

/// SPK-1133 verify (CLT machine, no XCTest).
/// Proves the tool database seed + feed wiring:
///   1. CLASSES: the installer-verified 13-class taxonomy is present with
///      display names (end mill … form; slotCutter retained for legacy decode).
///   2. CATALOG: 17 default tool assignments keyed by strategy; seeding a
///      fresh database yields the distinct physical tools.
///   3. MAPPING: `defaultTool(forStrategy:)` yields the expected default per
///      strategy (Profile→End Mill 1/4", V-Carve→V-Bit 90° 1¼",
///      QuickEngrave→Diamond Drag, Drilling→Drill 118° 1/4").
///   4. FEEDS: recalc with an assigned tool replaces the placeholder 1000
///      feed with the tool's recommended feed/plunge in the regenerated
///      G-code — Cut no longer relies on hardcoded F.
///   5. USER FEEDS WIN: stored params with an explicit feed (1500) keep it
///      even when a tool is assigned.
///   6. PERSIST: Tool round-trips Codable; the new ToolType cases decode.
/// The UI glue (picker, form) is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y), VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size), VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

func encodeParams(_ params: ProfileToolpathParams) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func main() throws {
    // ── 1. 13-class taxonomy. ───────────────────────────────────────────────
    let classes: [ToolType] = [
        .endMill, .radiusedEndMill, .ballNose, .vBit, .engraving,
        .radiusedEngraving, .drill, .diamondDrag, .laser, .threadMill,
        .multiThreadMill, .plasma, .form,
    ]
    try expect(classes.count == 13, "13 tool classes defined")
    for c in classes {
        try expect(!c.displayName.isEmpty, "\(c.rawValue) has a display name")
        try expect(ToolType(rawValue: c.rawValue) == c, "\(c.rawValue) round-trips its raw value")
    }

    // ── 2+3. Catalog + seeding + strategy mapping. ──────────────────────────
    try expect(ToolDatabase.defaultToolCatalog.count == 17,
               "17 default tool assignments in the catalog (got \(ToolDatabase.defaultToolCatalog.count))")
    let distinctTools = Set(ToolDatabase.defaultToolCatalog.map { "\($0.name)|\($0.type.rawValue)" })
    try expect(distinctTools.count == 10, "10 distinct physical tools seed the database (got \(distinctTools.count))")

    // Fresh database (clear any persisted tools from other runs).
    UserDefaults.standard.removeObject(forKey: "shopPilotTools")
    let db = ToolDatabase()
    try expect(db.tools.count == 10, "first-run seed yields the 10 distinct tools (got \(db.tools.count))")

    func defaultName(_ strategy: String) -> String? {
        db.defaultTool(forStrategy: strategy)?.name
    }
    try expect(defaultName("Profile") == "End Mill 1/4\"", "Profile → End Mill 1/4\"")
    try expect(defaultName("Pocket") == "End Mill 1/8\"", "Pocket → End Mill 1/8\"")
    try expect(defaultName("V-Carve") == "V-Bit 90° 1¼\"", "V-Carve → V-Bit 90° 1¼\"")
    try expect(defaultName("QuickEngrave") == "Diamond Drag 90° 1/8\" 0.002\"", "QuickEngrave → Diamond Drag")
    try expect(defaultName("Drilling")?.hasPrefix("Drill 118°") == true, "Drilling → Drill 118° 1/4\"")
    try expect(defaultName("NoSuchStrategy") == nil, "unknown strategy → nil default")

    // ── 4. Recalc uses the assigned tool's feeds (not hardcoded F1000). ─────
    guard let endMill = db.defaultTool(forStrategy: "Profile") else {
        throw VerifyError.failed("Profile default tool must exist")
    }
    try expect(endMill.type == .endMill && abs(endMill.diameter - 6.35) < 1e-9,
               "Profile default is the 1/4\" (6.35mm) end mill")

    let expectedFeed = ToolDatabase.recommendedFeedRate(diameter: endMill.diameter)
    let expectedPlunge = ToolDatabase.recommendedPlungeRate(diameter: endMill.diameter)
    try expect(abs(expectedFeed - 1000) > 1.0, "tool-derived feed differs from the placeholder (got \(expectedFeed))")

    let rect = makeClosedRect(x: 10, y: 10, size: 50)
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    node.toolID = endMill.id
    node.paramsJSON = encodeParams(ProfileToolpathParams()) // placeholder feed 1000
    let result = ProfileToolpathEngine.compute(
        vectors: [rect],
        params: ProfileToolpathParams(),
        material: nil,
        stockHeightMm: 6.0
    )
    node.toolpathResult = result.gcodeLines.joined(separator: "\n")
    node.markDirty()

    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 6.0,
        tools: db.tools
    )
    try expect(regenerated.count == 1, "recalc regenerated the dirty node")
    guard let gcode = node.toolpathResult else { throw VerifyError.failed("node has a result") }
    try expect(gcode.contains("F\(Int(expectedFeed))"),
               "regenerated G-code carries the tool feed F\(Int(expectedFeed)) (not F1000)")
    try expect(gcode.contains("F\(Int(expectedPlunge))"),
               "regenerated G-code carries the tool plunge F\(Int(expectedPlunge))")
    try expect(!gcode.contains("F1000"), "placeholder feed is gone from the regenerated G-code")

    // ── 5. Explicit user feed wins over the tool default. ───────────────────
    var customParams = ProfileToolpathParams()
    customParams.feedRateMmPerMin = 1500
    let node2 = tree.addOperation("Profile 2")
    node2.toolID = endMill.id
    node2.paramsJSON = encodeParams(customParams)
    let result2 = ProfileToolpathEngine.compute(
        vectors: [rect],
        params: customParams,
        material: nil,
        stockHeightMm: 6.0
    )
    node2.toolpathResult = result2.gcodeLines.joined(separator: "\n")
    node2.markDirty()
    _ = tree.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 6.0,
        tools: db.tools
    )
    try expect((node2.toolpathResult ?? "").contains("F1500"),
               "explicit stored feed F1500 is preserved through recalc with a tool assigned")
    try expect(!(node2.toolpathResult ?? "").contains("F\(Int(expectedFeed))"),
               "tool feed does not override an explicit user feed")

    // ── 6. Persist: Tool round-trip + new ToolType decode. ──────────────────
    let data = try JSONEncoder().encode(endMill)
    let decoded = try JSONDecoder().decode(Tool.self, from: data)
    try expect(decoded.id == endMill.id && decoded.name == endMill.name && decoded.type == .endMill,
               "Tool Codable round-trip")
    let diamond = try JSONDecoder().decode(ToolType.self, from: Data("\"diamondDrag\"".utf8))
    try expect(diamond == .diamondDrag, "new ToolType case decodes from its raw value")

    print("ShopPilotVerify1133: PASS — 13 classes, 17 catalog entries / 10 seeded tools, strategy defaults, tool feeds in recalc, user feeds win, persist")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1133: FAIL — \(error)")
    exit(1)
}
