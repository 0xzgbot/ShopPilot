import Foundation
import ShopPilotCore

// SPK-2010c — flat-area clearing + additive VCarveParams persist.

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── AC1 — closed 80×40 rect, 90° bit, maxDepth 2 (reachable tip half-width
    // 2 mm), flatAreaClearing on → comment + extra G1 at Z≈−2 off the spine.
    func rect(w: Double, h: Double, x: Double = 10, y: Double = 10) -> VectorPath {
        VectorPath(
            name: "board",
            points: [
                VectorPoint(x: x, y: y), VectorPoint(x: x + w, y: y),
                VectorPoint(x: x + w, y: y + h), VectorPoint(x: x, y: y + h),
                VectorPoint(x: x, y: y),
            ],
            isClosed: true
        )
    }

    var on = VCarveParams()
    on.maxDepthOfCutMm = 2
    on.medialAxisCellMm = 1.5
    on.flatAreaClearing = true

    let resOn = VCarveEngine.compute(vectors: [rect(w: 80, h: 40)], params: on)
    try expect(resOn.gcodeLines.contains { $0.contains("(Flat area clearing:") },
               "flag-on output must contain the flat-area clearing comment")

    // Extra sweep G1 at Z=-2 that is NOT on the spine centreline (the spine of
    // the rect runs at y=30; sweeps straddle it laterally).
    struct Cut { let x: Double; let y: Double; let z: Double }
    var sweepCuts: [Cut] = []
    var cx = 0.0, cy = 0.0, cz = 0.0
    for raw in resOn.gcodeLines {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("G1 ") else { continue }
        var sawXY = false
        for tok in line.split(separator: " ").dropFirst() {
            guard tok.count >= 2, let v = Double(tok.dropFirst()) else { continue }
            switch tok.first.map(String.init) {
            case "X": cx = v; sawXY = true
            case "Y": cy = v; sawXY = true
            case "Z": cz = v
            default: break
            }
        }
        if sawXY { sweepCuts.append(Cut(x: cx, y: cy, z: cz)) }
    }
    let deepOffSpine = sweepCuts.filter { $0.z < -1.9 && abs($0.y - 30) > 0.75 }
    try expect(!deepOffSpine.isEmpty,
               "expected lateral sweep cuts at Z≈−2 beside the spine, found none")

    var off = on
    off.flatAreaClearing = false
    let resOff = VCarveEngine.compute(vectors: [rect(w: 80, h: 40)], params: off)
    try expect(!resOff.gcodeLines.contains { $0.contains("(Flat area clearing:") },
               "flag-off output must NOT contain the flat-area comment")
    try expect(resOn.gcodeLines.count > resOff.gcodeLines.count,
               "flag-on must emit strictly more lines than flag-off")

    // Default is OFF.
    try expect(VCarveParams().flatAreaClearing == false, "flatAreaClearing default must be false")
    try expect(abs(VCarveParams().flatAreaThresholdFactor - 1.5) < 1e-12, "threshold default 1.5")
    try expect(abs(VCarveParams().flatAreaStepOverMm - 1.0) < 1e-12, "step-over default 1.0")

    // ── AC2 — additive Codable: {} decodes defaults; legacy pre-2010 JSON too;
    // round-trip keeps all five new fields. ──────────────────────────────────
    let empty = try JSONDecoder().decode(VCarveParams.self, from: Data("{}".utf8))
    try expect(empty.medialAxisPass == true, "{} → medialAxisPass default true")
    try expect(abs(empty.medialAxisCellMm - 1.0) < 1e-12, "{} → medialAxisCellMm default 1.0")
    try expect(empty.flatAreaClearing == false, "{} → flatAreaClearing default false")
    try expect(abs(empty.flatAreaThresholdFactor - 1.5) < 1e-12, "{} → threshold 1.5")
    try expect(abs(empty.flatAreaStepOverMm - 1.0) < 1e-12, "{} → step-over 1.0")

    // Pre-2010 job JSON: only the §O-era keys (no medial/flat keys).
    let legacyJSON = """
    {"vBitAngleDegrees":60,"feedRateMmPerMin":900,"plungeFeedRateMmPerMin":250,
     "maxDepthOfCutMm":3,"leadInDistanceMm":4,"leadOutDistanceMm":4,
     "stepOverMm":1.5,"flatBottomMode":false,"vectorDepths":[],     "startDepthMm":0,"flatDepthMm":1,"cornerSharpen":false,
     "useVectorStartPoints":true,"useVectorSelectionOrder":false,
     "safeZHeightMm":3.2,"rampPlungeMoves":false,
     "clearancePassEnabled":false,"clearanceToolDiameterMm":6,
     "clearanceDepthMm":1,"clearanceStepOverMm":0.4,"spindleRpm":0}
    """
    let legacy = try JSONDecoder().decode(VCarveParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.medialAxisPass == true, "legacy decode → medial on")
    try expect(legacy.flatAreaClearing == false, "legacy decode → flat off")

    // Round-trip all five new fields through a node paramsJSON blob.
    var full = VCarveParams()
    full.medialAxisPass = false
    full.medialAxisCellMm = 2.5
    full.flatAreaClearing = true
    full.flatAreaThresholdFactor = 1.25
    full.flatAreaStepOverMm = 0.8
    let data = try JSONEncoder().encode(full)
    let back = try JSONDecoder().decode(VCarveParams.self, from: data)
    try expect(back.medialAxisPass == false && abs(back.medialAxisCellMm - 2.5) < 1e-12
               && back.flatAreaClearing == true
               && abs(back.flatAreaThresholdFactor - 1.25) < 1e-12
               && abs(back.flatAreaStepOverMm - 0.8) < 1e-12,
               "round-trip must keep all five Valley fields")

    // ── AC3 — recalc with stored paramsJSON: mutating flatAreaClearing and
    // recalculating the dirty node changes the G-code. ───────────────────────
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("V-Carve Detail")
    node.paramsJSON = String(data: try JSONEncoder().encode(off), encoding: .utf8)
    node.markDirty()

    let vectors = [rect(w: 80, h: 40)]
    let beforeResults = tree.computeDirtyToolpathResults(
        vectors: vectors,
        material: nil,
        stockHeightMm: 25.0)
    try expect(beforeResults.count == 1, "recalc computed exactly one node")
    // Mirror the session's apply step (compute/apply split): write the result
    // back and clear dirty, as recalculateDirtyToolpaths does on main.
    node.setResult(beforeResults[0].gcode)
    node.estimatedTimeSeconds = beforeResults[0].estimatedTimeSeconds
    node.clearDirty()
    try expect(node.toolpathResult?.contains("O=V_CARVE_TOOLPATH") == true,
               "regenerated output carries the marker")

    var mutated = off
    mutated.flatAreaClearing = true
    node.paramsJSON = String(data: try JSONEncoder().encode(mutated), encoding: .utf8)
    node.markDirty()
    let afterResults = tree.computeDirtyToolpathResults(
        vectors: vectors,
        material: nil,
        stockHeightMm: 25.0)
    try expect(afterResults.count == 1, "recalc recomputed the mutated node")
    let afterGcode = afterResults[0].gcode
    try expect(afterGcode != beforeResults[0].gcode,
               "mutating flatAreaClearing + recalc must change the G-code")
    try expect(afterGcode.contains("(Flat area clearing:"), "recalculated output honours the stored flag")

    print("ShopPilotVerify2010c: PASS — flat-area sweep (\(deepOffSpine.count) off-spine Z−2 cuts), additive Codable defaults + round-trip, recalc-from-paramsJSON regenerates")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2010c: FAIL — \(error)")
    exit(1)
}
