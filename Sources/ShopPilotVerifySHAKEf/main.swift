import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-SHAKEf verify (CLT): Cut strategies × dirty × recalc × export-block
/// matrix.
///
///   1. Every strategy — Profile / Pocket / Drill / V-Carve(+clearance) /
///      Rough 3D / Finish 3D — produces a real-engine result carrying its
///      marker (O=PROFILE_TOOLPATH / O=POCKET_TOOLPATH / O=DRILL_TOOLPATH /
///      O=V_CARVE_TOOLPATH / O=ROUGH_3D / O=FINISH_3D), V-Carve clearance
///      emitted BEFORE the V-bit block.
///   2. Clean tree → export valid.
///   3. ONE node dirty → export blocked → recalc regenerates ONLY that node
///      (all siblings' G-code byte-identical) → badge cleared → export valid.
///   4. Per-strategy badge-clear loop: dirty → recalc → clean + marker intact
///      for each of the six families.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func joined(_ node: ToolpathTreeNode) -> String { node.toolpathResult ?? "" }

var total = 0
func ok(_ name: String) { total += 1; print("  ok   \(name)") }

func main() throws {
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    // Flat 10×10 plateau relief (cell 2mm → 20×20mm stock) for the 3D engines.
    let heights = Array(repeating: 5.0, count: 100)
    let hf = HeightfieldData(width: 10, height: 10, cellSizeMm: 2.0,
                             minX: 0, minY: 0, heights: heights)

    let tree = ToolpathTreeManager()

    // ── 1. Build all six ops with real engine output. ───────────────────────
    print("== Strategy marker matrix ==")

    let profile = tree.addOperation("Profile 1")
    let pRes = ProfileToolpathEngine.compute(
        vectors: [square], params: ProfileToolpathParams(),
        material: nil, stockHeightMm: 25.0
    )
    profile.toolpathResult = pRes.gcodeLines.joined(separator: "\n")
    profile.estimatedTimeSeconds = pRes.estimatedTimeSeconds
    profile.paramsJSON = String(data: try JSONEncoder().encode(ProfileToolpathParams()), encoding: .utf8)
    try expect(joined(profile).contains("O=PROFILE_TOOLPATH"), "Profile marker")
    ok("Profile 1 → O=PROFILE_TOOLPATH")

    let pocket = tree.addOperation("Pocket 1")
    var pocketParams = PocketToolpathParams()
    pocketParams.feedRateMmPerMin = 1500
    let pkRes = PocketToolpathEngine.compute(
        vectors: [square], params: pocketParams, material: nil, stockHeightMm: 25.0
    )
    pocket.toolpathResult = pkRes.gcodeLines.joined(separator: "\n")
    pocket.estimatedTimeSeconds = pkRes.estimatedTimeSeconds
    pocket.paramsJSON = String(data: try JSONEncoder().encode(pocketParams), encoding: .utf8)
    try expect(joined(pocket).contains("O=POCKET_TOOLPATH"), "Pocket marker")
    try expect(joined(pocket).contains("F1500"), "stored pocket feed reaches G-code")
    ok("Pocket 1 → O=POCKET_TOOLPATH (F1500)")

    let drill = tree.addOperation("Drill 1")
    let drillPoints = [DrillPoint(x: 25, y: 25, zDepthMm: -3), DrillPoint(x: 25, y: 25, zDepthMm: -3)]
    let drRes = DrillToolpathEngine.compute(
        points: drillPoints, params: DrillToolpathParams(), material: nil, stockHeightMm: 25.0
    )
    drill.toolpathResult = drRes.gcodeLines.joined(separator: "\n")
    drill.estimatedTimeSeconds = drRes.estimatedTimeSeconds
    drill.paramsJSON = String(data: try JSONEncoder().encode(DrillToolpathParams()), encoding: .utf8)
    try expect(joined(drill).contains("O=DRILL_TOOLPATH"), "Drill marker")
    ok("Drill 1 → O=DRILL_TOOLPATH")

    let vcarve = tree.addOperation("V-Carve 1")
    var vcParams = VCarveParams()
    vcParams.clearancePassEnabled = true
    vcParams.clearanceToolDiameterMm = 6.0
    vcParams.clearanceDepthMm = 1.0
    let vcRes = VCarveEngine.compute(vectors: [square], params: vcParams, stockHeightMm: 25.0)
    vcarve.toolpathResult = vcRes.gcodeLines.joined(separator: "\n")
    vcarve.estimatedTimeSeconds = vcRes.estimatedTimeSeconds
    vcarve.paramsJSON = String(data: try JSONEncoder().encode(vcParams), encoding: .utf8)
    let vcGcode = joined(vcarve)
    try expect(vcGcode.contains("O=V_CARVE_TOOLPATH"), "V-Carve marker")
    try expect(vcGcode.contains("O=VCARVE_CLEARANCE"), "clearance block present")
    try expect(vcGcode.range(of: "O=VCARVE_CLEARANCE")!.lowerBound <
               vcGcode.range(of: "O=V_CARVE_TOOLPATH")!.lowerBound,
               "clearance pass precedes the V-bit block")
    ok("V-Carve 1 → clearance before O=V_CARVE_TOOLPATH")

    let rough = tree.addOperation("Rough 3D 1")
    let rRes = HeightfieldRoughEngine.compute(heightfield: hf, params: HeightfieldRoughParams())
    rough.toolpathResult = rRes.gcodeLines.joined(separator: "\n")
    rough.estimatedTimeSeconds = rRes.estimatedTimeSeconds
    rough.paramsJSON = String(data: try JSONEncoder().encode(HeightfieldRoughParams()), encoding: .utf8)
    try expect(joined(rough).contains("O=ROUGH_3D"), "Rough 3D marker")
    ok("Rough 3D 1 → O=ROUGH_3D")

    let finish = tree.addOperation("Finish 3D 1")
    let fRes = HeightfieldFinishEngine.compute(heightfield: hf, params: HeightfieldFinishParams())
    finish.toolpathResult = fRes.gcodeLines.joined(separator: "\n")
    finish.estimatedTimeSeconds = fRes.estimatedTimeSeconds
    finish.paramsJSON = String(data: try JSONEncoder().encode(HeightfieldFinishParams()), encoding: .utf8)
    try expect(joined(finish).contains("O=FINISH_3D"), "Finish 3D marker")
    ok("Finish 3D 1 → O=FINISH_3D")

    for node in [profile, pocket, drill, vcarve, rough, finish] {
        try expect(!node.isDirty, "\(node.name) fresh and clean")
    }
    try expect(tree.dirtyNodeCount == 0, "zero dirty badges on a fresh tree")

    // ── 2. Clean tree → export valid. ───────────────────────────────────────
    print("== Export gate ==")
    var blocker = ExportBlocker(treeManager: tree)
    try expect(blocker.validateForExport().isValid, "export allowed while all six clean")
    ok("clean tree → export valid")

    // ── 3. ONE dirty node → blocked → recalc regenerates ONLY it. ───────────
    let beforeOthers = [profile, drill, vcarve, rough, finish].map { joined($0) }
    pocket.markDirty()
    try expect(tree.dirtyNodeCount == 1, "one dirty badge (got \(tree.dirtyNodeCount))")
    blocker = ExportBlocker(treeManager: tree)
    try expect(!blocker.validateForExport().isValid, "export blocked while pocket dirty")
    ok("pocket dirty → export blocked")

    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [square], material: nil, stockHeightMm: 25.0, heightfield: hf
    )
    try expect(regenerated.count == 1 && regenerated[0].name == "Pocket 1",
               "recalc regenerates exactly the dirty node (got \(regenerated.map(\.name)))")
    try expect(!pocket.isDirty, "pocket badge cleared")
    try expect(joined(pocket).contains("O=POCKET_TOOLPATH"), "pocket regenerated by its engine")
    let afterOthers = [profile, drill, vcarve, rough, finish].map { joined($0) }
    try expect(beforeOthers == afterOthers, "sibling ops' G-code byte-identical (not touched)")
    try expect(tree.dirtyNodeCount == 0, "dirty count back to 0")
    blocker = ExportBlocker(treeManager: tree)
    try expect(blocker.validateForExport().isValid, "export allowed again after recalc")
    ok("recalc: only dirty node regenerated, siblings untouched, export unblocked")

    // ── 4. Per-strategy badge-clear loop. ────────────────────────────────────
    print("== Badge-clear matrix ==")
    let expectations: [(ToolpathTreeNode, String)] = [
        (profile, "O=PROFILE_TOOLPATH"), (drill, "O=DRILL_TOOLPATH"),
        (vcarve, "O=V_CARVE_TOOLPATH"), (rough, "O=ROUGH_3D"), (finish, "O=FINISH_3D"),
    ]
    for (node, marker) in expectations {
        node.markDirty()
        try expect(tree.dirtyNodeCount == 1, "\(node.name) dirty badge set")
        _ = tree.recalculateDirtyToolpaths(
            vectors: [square], material: nil, stockHeightMm: 25.0, heightfield: hf
        )
        try expect(!node.isDirty, "\(node.name) badge cleared by recalc")
        try expect(joined(node).contains(marker), "\(node.name) marker intact after recalc")
        try expect(tree.dirtyNodeCount == 0, "\(node.name) recalc leaves tree clean")
        ok("\(node.name): dirty → recalc → clean + \(marker) intact")
    }

    print("\nRESULT: SPK-SHAKEf \(total) checks — PASS")
}

do {
    try main()
} catch {
    print("FAIL: \(error)")
    exit(1)
print("ShopPilotVerifySHAKEf: PASS — shake fixture F verified")

}
print("ShopPilotVerifySHAKEf: PASS — shake fixture f verified")
