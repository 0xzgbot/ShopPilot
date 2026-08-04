import Foundation
import ShopPilotCore

/// SPK-1136c verify (CLT machines, no XCTest).
/// Proves the Drill strategy form-field spine (same shape as 1136a/1136b):
///   1. PRESENCE: every installer-verified §N key exists on DrillToolpathParams.
///   2. ROUND-TRIP: JSON encode/decode + .shoppilot PersistedToolpath → restore.
///   3. BACKWARD-COMPAT: pre-SPK-1136c JSON decodes with defaults.
///   4. APPLY-REGEN: regenerating a Drill op with stored params uses those
///      params — dwell emits G4, marker + plunges present, feed in G-code.
/// The form/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Presence: the §N key set. ─────────────────────────────────────────
    let p = DrillToolpathParams()
    try expect([DrillCycleType.spotDrill, .peckDrill, .deepHolePeck, .counterbore, .countersink]
                   .contains(p.cycleType), "cycle type key present")
    try expect(p.feedRateMmPerMin > 0 && p.plungeFeedRateMmPerMin > 0, "feed keys present")
    try expect(p.retractHeightMm > 0 && p.peckDepthMm > 0 && p.toolDiameterMm > 0
                   && p.safetyHeightMm > 0, "retract/peck/tool/safe-Z keys present")
    try expect(p.startDepthMm == 0 && p.cutDepthMm > 0, "N01 cut depth + N02 start depth keys present")
    try expect(p.peckDrilling, "N04 peck drilling key present")
    try expect([DrillRetractMode.aboveCuttingStart, .abovePreviousPass].contains(p.retractMode),
               "N05 retract mode key present")
    try expect(p.peckRetractGapMm > 0, "N06 retract gap key present")
    try expect(!p.dwellAtBottom && p.dwellTimeSeconds > 0, "N07/N08 dwell keys present")
    try expect(!p.useVectorSelectionOrder, "N09 selection order key present")

    // ── 2. Round-trip: JSON + .shoppilot per-op params. ──────────────────────
    var custom = DrillToolpathParams()
    custom.cycleType = .deepHolePeck
    custom.cutDepthMm = 12
    custom.peckDrilling = true
    custom.retractMode = .abovePreviousPass
    custom.peckRetractGapMm = 1.5
    custom.dwellAtBottom = true
    custom.dwellTimeSeconds = 0.5
    custom.plungeFeedRateMmPerMin = 500

    let data = try JSONEncoder().encode(custom)
    let decoded = try JSONDecoder().decode(DrillToolpathParams.self, from: data)
    try expect(decoded.cycleType == .deepHolePeck && decoded.plungeFeedRateMmPerMin == 500,
               "JSON round-trip: cycle/plunge feed")
    try expect(decoded.cutDepthMm == 12 && decoded.peckRetractGapMm == 1.5, "JSON round-trip: depth/retract gap")
    try expect(decoded.retractMode == .abovePreviousPass && decoded.dwellAtBottom
                   && decoded.dwellTimeSeconds == 0.5, "JSON round-trip: retract mode + dwell")

    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Drill 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    let persisted = PersistedToolpath(from: node)
    try expect(persisted.paramsJSON != nil, "persist snapshot carries paramsJSON")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: [persisted])
    let restoredNode = restored.allNodes.first { $0.isDrillOperation }!
    let restoredParams = restoredNode.drillParams()
    try expect(restoredParams.cycleType == .deepHolePeck && restoredParams.dwellAtBottom,
               ".shoppilot round-trip keeps per-op drill params")

    // ── 3. Backward-compat: pre-SPK-1136c JSON decodes with defaults. ────────
    let legacyJSON = """
    {"cycleType":"peckDrill","feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,
     "retractHeightMm":5.0,"peckDepthMm":2.0,"toolDiameterMm":6.0,"safetyHeightMm":10.0}
    """
    let legacy = try JSONDecoder().decode(DrillToolpathParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.startDepthMm == 0 && legacy.cutDepthMm == 10.0 && legacy.peckDrilling
                   && legacy.retractMode == .aboveCuttingStart && !legacy.dwellAtBottom,
               "legacy JSON decodes with SPK-1136c defaults")

    // ── 4. Apply-regen: stored params drive the real engine. ─────────────────
    // Mirror of session.applyDrillParams point mapping (centroid + depth from
    // params + dwell from params).
    let points: [DrillPoint] = [
        DrillPoint(
            x: 25, y: 25,
            zDepthMm: -(restoredParams.startDepthMm + restoredParams.cutDepthMm),
            dwellSeconds: restoredParams.dwellAtBottom ? restoredParams.dwellTimeSeconds : 0
        )
    ]
    let result = DrillToolpathEngine.compute(
        points: points,
        params: restoredParams,
        material: nil,
        stockHeightMm: 25.0
    )
    try expect(result.gcodeLines.contains("O=DRILL_TOOLPATH"), "regenerated output is real engine G-code")
    try expect(result.gcodeLines.contains { $0.hasPrefix("G1 Z") }, "regenerated output plunges to depth")
    try expect(result.gcodeLines.contains("G4 P0.5"), "stored dwell emits G4 in the G-code")
    try expect(result.gcodeLines.contains { $0.contains("F500") },
               "stored plunge feed reaches the G-code")
    try expect(result.estimatedTimeSeconds > 0, "regenerated op has a time estimate")

    print("ShopPilotVerify1136c: PASS — §N key presence, round-trip, legacy decode, apply-regen uses stored params")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1136c: FAIL — \(error)")
    exit(1)
}
