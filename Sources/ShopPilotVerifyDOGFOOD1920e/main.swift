import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-1920e verify — material + bit preset fills Cut feed/plunge/rpm and
// Calculate honors them.
//
// AC1: resolvedCutData resolves per-material cut data for an assigned tool.
// AC2: withToolFeeds (via tree recalc) writes those feeds into the generated
//      G-code — the F word in the output matches the preset, not the 1000
//      default, when the node's tool is linked.
// AC3: a tool with NO matching material falls back to geometry defaults.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD1920e: FAIL — \(msg)")
        exit(1)
    }
}

// --- Fixture: one end mill with two material presets ----------------------
var cutData: [ToolCutData] = [
    ToolCutData(material: "hardwood", feedRateMmPerMin: 1800, plungeRateMmPerMin: 450, spindleRpm: 18000, maxDepthOfCutMm: 3.0),
    ToolCutData(material: "aluminum", feedRateMmPerMin: 900, plungeRateMmPerMin: 150, spindleRpm: 12000, maxDepthOfCutMm: 1.0),
]
let mill = Tool(
    id: UUID(),
    name: "6mm spiral upcut",
    type: .endMill,
    diameter: 6.0,
    cuttingLength: 20,
    totalLength: 40,
    shankDiameter: 6.0,
    flutes: 2,
    cutData: cutData
)
expect(!mill.cutData.isEmpty, "fixture tool carries cut-data presets")

let db = ToolDatabase()
db.tools = [mill]

// --- AC1: per-material resolution -----------------------------------------
let hard = mill.resolvedCutData(material: "hardwood", machineName: nil)
expect(hard.feedRateMmPerMin == 1800 && hard.spindleRpm == 18000,
       "hardwood preset resolves F1800/S18000 (got F\(hard.feedRateMmPerMin)/S\(hard.spindleRpm))")
let alu = mill.resolvedCutData(material: "aluminum", machineName: nil)
expect(alu.feedRateMmPerMin == 900 && alu.maxDepthOfCutMm == 1.0,
       "aluminum preset resolves F900/DOC1.0")

// --- AC2: recalc honors the resolved feeds --------------------------------
// Build a rectangle design + Profile op assigned to the mill, mark dirty,
// recalc against hardwood. The G-code's cutting F words must be 1800.
let rect: [VectorPoint] = [
    .init(x: 10, y: 10), .init(x: 60, y: 10), .init(x: 60, y: 40),
    .init(x: 10, y: 40), .init(x: 10, y: 10),
]
let layerID = UUID()
let layer = Layer(id: layerID, name: "L1", vectors: [
    VectorPath(name: "Frame", points: rect, isClosed: true, layerId: layerID)
])
let sheet = Sheet(id: UUID(), name: "S", width: 80, depth: 60, height: 12, layers: [layer])
var job = Job(id: UUID(), name: "preset-job", sheets: [sheet])
job.activeSheetID = sheet.id

let tree = ToolpathTreeManager()
let profileNode = tree.addOperation("Profile 0")
profileNode.markDirty()  // fresh nodes start clean — mark for the recalc gate
profileNode.toolID = mill.id

// SPK-1920e — recalc with the hardwood material: withToolFeeds must resolve
// the mill's hardwood preset into the generated G-code's feed words.
let vecs = GeometryBridge.toCorePaths([
    .rectangle(origin: VectorPoint(x: 10, y: 10), width: 50, height: 30)
])
let hardwood = Material(
    name: "hardwood",
    category: .wood,
    density: 0.7,
    hardnessRating: 25,
    maxFeedRateMmPerMin: 3000,
    maxDepthOfCutMm: 5,
    coolantType: .none
)
let regenerated = tree.recalculateDirtyToolpaths(
    vectors: vecs,
    material: hardwood,
    stockHeightMm: 12,
    tools: db.tools,
    heightfield: nil,
    machineName: nil
)
expect(regenerated.count > 0, "recalc regenerated \(regenerated.count) dirty op(s)")

let gcode = profileNode.toolpathResult ?? ""
expect(gcode.contains("G1"), "profile G-code contains G1 moves")

// Every G1 feed word must be the preset's 1800 (not the 1000 default).
let feedWords = gcode.split(whereSeparator: { $0.isNewline })
    .compactMap { line -> Int? in
        guard let r = line.range(of: "F") else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }
expect(!feedWords.isEmpty, "G-code carries F words")
// Every G1 feed word must come from the preset family: 1800 cutting, 450
// plunge (the plunge word rides the Z-entry G1). No 1000 defaults may leak.
expect(feedWords.allSatisfy { $0 == 1800 || $0 == 450 },
       "all feeds come from the hardwood preset (F1800 cut / F450 plunge; got: \([Int](Set(feedWords)).sorted()))")

// --- AC3: unknown material falls back to geometry defaults -----------------
let fallback = mill.resolvedCutData(material: "unobtainium", machineName: nil)
let geomDefault = ToolDatabase.recommendedFeedRate(diameter: mill.diameter)
expect(fallback.feedRateMmPerMin == geomDefault,
       "unknown material falls back to geometry default F\(geomDefault)")

print("ShopPilotVerifyDOGFOOD1920e: PASS — material preset resolves (F1800 hardwood / F900 aluminum), recalc emits preset feeds, fallback clean.")
exit(0)
