import Foundation
import ShopPilotCore

/// SPK-1133b verify (CLT machine, no XCTest).
/// Proves the 3-part cut-data linkage (geometry / cut-data / machine-cut-data):
///   1. MODEL: per-material `ToolCutData` + per-machine `MachineCutData`
///      Codable round-trip; `Tool` with both arrays round-trips; pre-1133b
///      persisted tools (JSON without the new keys) still decode ([] defaults).
///   2. RESOLUTION: `resolvedCutData(material:machineName:)` precedence —
///      machine override > per-material cut data > geometry-derived defaults.
///   3. PER-MACHINE DIFFERS: two machines with different cut data resolve to
///      different feeds for the same tool+material (switching machines swaps
///      speeds without touching geometry).
///   4. RECALC LINKAGE: a dirty Profile op with an assigned tool and
///      placeholder feed (1000) regenerates with the LINKED feed, plunge,
///      spindle RPM (M3 S…) and pass depth — not the hardcoded defaults.
///   5. USER FEEDS WIN: explicit stored feed (1500) is preserved through recalc.
///   6. SEEDS: seeded tools carry per-material (hardwood) cut data; strategy
///      default mapping still intact.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
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

func encodeParams<T: Encodable>(_ params: T) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func main() throws {
    // ── 1. Model + Codable round-trip + legacy decode. ─────────────────────
    let materialData = ToolCutData(
        material: "hardwood",
        feedRateMmPerMin: 850,
        plungeRateMmPerMin: 340,
        spindleRpm: 12000,
        maxDepthOfCutMm: 1.5
    )
    let machineData = MachineCutData(
        machineName: "GRBL 3018",
        feedRateMmPerMin: 600,
        plungeRateMmPerMin: 240,
        spindleRpm: 9000,
        maxDepthOfCutMm: 1.0
    )

    let tool = Tool(
        name: "Test End Mill 1/4\"",
        type: .endMill,
        diameter: 6.35,
        cuttingLength: 20,
        totalLength: 40,
        shankDiameter: 6.35,
        cutData: [materialData],
        machineCutData: [machineData]
    )
    let encoded = try JSONEncoder().encode(tool)
    let decoded = try JSONDecoder().decode(Tool.self, from: encoded)
    try expect(decoded.id == tool.id && decoded.name == tool.name, "Tool identity round-trips")
    try expect(decoded.cutData == [materialData], "per-material cut data round-trips")
    try expect(decoded.machineCutData == [machineData], "per-machine cut data round-trips")

    // Legacy pre-1133b JSON (no cutData/machineCutData keys) must decode.
    let legacyJSON = """
    {"id":"\(tool.id.uuidString)","name":"Old Tool","type":"endMill","diameter":6.35,
     "cuttingLength":20,"totalLength":40,"shankDiameter":6.35,"flutes":2,
     "material":"carbide","createdAt":\(tool.createdAt.timeIntervalSinceReferenceDate),
     "updatedAt":\(tool.updatedAt.timeIntervalSinceReferenceDate)}
    """
    let legacy = try JSONDecoder().decode(Tool.self, from: Data(legacyJSON.utf8))
    try expect(legacy.name == "Old Tool", "legacy tool decodes")
    try expect(legacy.cutData.isEmpty && legacy.machineCutData.isEmpty,
               "legacy tool defaults linked cut data to []")

    // ToolCutData / MachineCutData standalone round-trip.
    let mdJSON = try JSONEncoder().encode(materialData)
    let mdBack = try JSONDecoder().decode(ToolCutData.self, from: mdJSON)
    try expect(mdBack == materialData, "ToolCutData round-trips")
    let mcJSON = try JSONEncoder().encode(machineData)
    let mcBack = try JSONDecoder().decode(MachineCutData.self, from: mcJSON)
    try expect(mcBack == machineData, "MachineCutData round-trips")

    // ── 2. Resolution precedence. ──────────────────────────────────────────
    // Derived defaults (no material, no machine).
    let derived = tool.resolvedCutData(material: nil, machineName: nil)
    let derivedFeed = ToolDatabase.recommendedFeedRate(diameter: 6.35)
    let derivedPlunge = ToolDatabase.recommendedPlungeRate(diameter: 6.35)
    try expectClose(derived.feedRateMmPerMin, derivedFeed, "derived feed from geometry")
    try expectClose(derived.plungeRateMmPerMin, derivedPlunge, "derived plunge from geometry")
    try expect(derived.spindleRpm > 0, "derived spindle rpm is sane")
    try expect(derived.maxDepthOfCutMm > 0, "derived pass depth is sane")

    // Material cut-data applies when the material matches.
    let hardwood = tool.resolvedCutData(material: "hardwood", machineName: nil)
    try expectClose(hardwood.feedRateMmPerMin, 850, "material cut-data feed applies")
    try expectClose(hardwood.plungeRateMmPerMin, 340, "material cut-data plunge applies")
    try expectClose(hardwood.spindleRpm, 12000, "material cut-data rpm applies")
    try expectClose(hardwood.maxDepthOfCutMm, 1.5, "material cut-data depth applies")

    // Unknown material falls back to derived.
    let unknownMat = tool.resolvedCutData(material: "plywood", machineName: nil)
    try expectClose(unknownMat.feedRateMmPerMin, derivedFeed, "unknown material → derived feed")

    // ── 3. Per-machine cut data can differ; machine wins over material. ────
    let onMachine = tool.resolvedCutData(material: "hardwood", machineName: "GRBL 3018")
    try expectClose(onMachine.feedRateMmPerMin, 600, "machine cut-data feed wins over material")
    try expectClose(onMachine.spindleRpm, 9000, "machine cut-data rpm wins over material")
    try expectClose(onMachine.maxDepthOfCutMm, 1.0, "machine cut-data depth wins over material")
    try expect(onMachine.feedRateMmPerMin != hardwood.feedRateMmPerMin,
               "per-machine cut-data differs from material cut-data")

    // Second machine with its own values → still resolves per-machine.
    let tool2Machines = Tool(
        name: "Two-Machine Tool",
        type: .endMill,
        diameter: 6.35,
        cuttingLength: 20,
        totalLength: 40,
        shankDiameter: 6.35,
        cutData: [materialData],
        machineCutData: [
            machineData,
            MachineCutData(machineName: "Heavy Router", feedRateMmPerMin: 1100,
                           plungeRateMmPerMin: 440, spindleRpm: 18000, maxDepthOfCutMm: 2.5)
        ]
    )
    let light = tool2Machines.resolvedCutData(material: "hardwood", machineName: "GRBL 3018")
    let heavy = tool2Machines.resolvedCutData(material: "hardwood", machineName: "Heavy Router")
    try expectClose(light.feedRateMmPerMin, 600, "GRBL 3018 feed")
    try expectClose(heavy.feedRateMmPerMin, 1100, "Heavy Router feed")
    try expect(light.feedRateMmPerMin != heavy.feedRateMmPerMin,
               "two machines resolve to different cut data for the same tool+material")

    // Unknown machine falls back to material cut-data.
    let unknownMachine = tool2Machines.resolvedCutData(material: "hardwood", machineName: "No Such Machine")
    try expectClose(unknownMachine.feedRateMmPerMin, 850, "unknown machine → material cut-data")

    // ── 4. Recalc uses linked cut data (feed/plunge/rpm/depth). ────────────
    UserDefaults.standard.removeObject(forKey: "shopPilotTools")
    let db = ToolDatabase()

    let rect = makeClosedRect(x: 10, y: 10, size: 50)
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    node.toolID = tool.id
    node.paramsJSON = encodeParams(ProfileToolpathParams()) // placeholder feed 1000
    node.markDirty()

    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 6.0,
        tools: [tool],
        machineName: "GRBL 3018"
    )
    try expect(regenerated.count == 1, "recalc regenerated the dirty Profile node")
    guard let gcode = node.toolpathResult else { throw VerifyError.failed("node has a result") }
    try expect(gcode.contains("O=PROFILE_TOOLPATH"), "regenerated output is real engine G-code")
    try expect(gcode.contains("F600"), "linked machine feed F600 reaches the G-code (not F1000)")
    try expect(gcode.contains("F240"), "linked machine plunge F240 reaches the G-code")
    try expect(gcode.contains("M3 S9000"), "linked machine spindle M3 S9000 reaches the G-code")
    try expect(!gcode.contains("F1000"), "placeholder feed is gone from the regenerated G-code")
    // Linked depth 1.0 over 6.0mm stock → 6 passes (default 2.0 would be 3).
    try expect(gcode.contains("(Pass 6/6"), "linked pass depth drives the pass count (6 passes)")

    // Without the machine override the same op resolves to material cut-data.
    let tree2 = ToolpathTreeManager()
    let node2 = tree2.addOperation("Profile 2")
    node2.toolID = tool.id
    node2.paramsJSON = encodeParams(ProfileToolpathParams())
    node2.markDirty()
    _ = tree2.recalculateDirtyToolpaths(
        vectors: [rect],
        material: nil,
        stockHeightMm: 6.0,
        tools: [tool],
        machineName: nil
    )
    guard let gcode2 = node2.toolpathResult else { throw VerifyError.failed("node2 has a result") }
    // No material, no machine → derived feed (not the material's 850).
    let derivedF = Int(ToolDatabase.recommendedFeedRate(diameter: 6.35))
    try expect(gcode2.contains("F\(derivedF)"), "no override → derived feed F\(derivedF)")
    try expect(!gcode2.contains("F850"), "material cut-data NOT applied without a matching material")

    // Material-aware recalc: pass a real Material whose name matches the tool's
    // cut-data entry → material values apply.
    let mat = Material(
        id: UUID(),
        name: "hardwood",
        category: .wood,
        density: 0.7,
        hardnessRating: 30,
        maxFeedRateMmPerMin: 3000,
        maxDepthOfCutMm: 3.0,
        coolantType: .none
    )
    let tree3 = ToolpathTreeManager()
    let node3 = tree3.addOperation("Profile 3")
    node3.toolID = tool.id
    node3.paramsJSON = encodeParams(ProfileToolpathParams())
    node3.markDirty()
    _ = tree3.recalculateDirtyToolpaths(
        vectors: [rect],
        material: mat,
        stockHeightMm: 6.0,
        tools: [tool],
        machineName: nil
    )
    guard let gcode3 = node3.toolpathResult else { throw VerifyError.failed("node3 has a result") }
    try expect(gcode3.contains("F850"), "material name match → linked material feed F850")
    try expect(gcode3.contains("M3 S12000"), "linked material spindle M3 S12000")

    // ── 5. User feeds win. ─────────────────────────────────────────────────
    var custom = ProfileToolpathParams()
    custom.feedRateMmPerMin = 1500
    let tree4 = ToolpathTreeManager()
    let node4 = tree4.addOperation("Profile 4")
    node4.toolID = tool.id
    node4.paramsJSON = encodeParams(custom)
    node4.markDirty()
    _ = tree4.recalculateDirtyToolpaths(
        vectors: [rect],
        material: mat,
        stockHeightMm: 6.0,
        tools: [tool],
        machineName: "GRBL 3018"
    )
    guard let gcode4 = node4.toolpathResult else { throw VerifyError.failed("node4 has a result") }
    try expect(gcode4.contains("F1500"), "explicit user feed 1500 preserved through recalc")
    try expect(!gcode4.contains("F600") && !gcode4.contains("F850"),
               "linked machine/material feeds do NOT override an explicit feed")

    // ── 6. Seeds carry linked cut data; strategy mapping intact. ───────────
    try expect(db.tools.count == 10, "first-run seed yields 10 distinct tools (got \(db.tools.count))")
    guard let endMill = db.defaultTool(forStrategy: "Profile") else {
        throw VerifyError.failed("Profile default tool must exist")
    }
    try expect(endMill.cutData.contains { $0.material == "hardwood" },
               "seeded Profile tool carries hardwood cut data")
    let seededResolved = endMill.resolvedCutData(material: "hardwood", machineName: nil)
    try expectClose(seededResolved.feedRateMmPerMin,
                    ToolDatabase.recommendedFeedRate(diameter: endMill.diameter),
                    "seeded hardwood cut data matches the derived feed (no behavior change)")
    try expect(endMill.machineCutData.isEmpty, "seeds carry no machine overrides")

    print("ShopPilotVerify1133b: PASS — 3-part cut-data linkage (geometry/cut-data/machine-cut-data), "
          + "per-machine differs, recalc links feed/plunge/rpm/depth, user feeds win, legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1133b: FAIL — \(error)")
    exit(1)
}
