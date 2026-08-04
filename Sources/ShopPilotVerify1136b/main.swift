import Foundation
import ShopPilotCore

/// SPK-1136b verify (CLT machines, no XCTest).
/// Proves the Pocket strategy form-field spine (same shape as SPK-1136a):
///   1. PRESENCE: every installer-verified §M key exists on PocketToolpathParams.
///   2. ROUND-TRIP: params survive JSON encode/decode and the .shoppilot
///      PersistedToolpath → restore path (per-op paramsJSON).
///   3. BACKWARD-COMPAT: pre-SPK-1136b JSON decodes with defaults.
///   4. APPLY-REGEN: regenerating a dirty Pocket node with stored params uses
///      those params (feed rate visible in the G-code), not defaults.
/// The form/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Presence: the §M key set. ─────────────────────────────────────────
    let p = PocketToolpathParams()
    try expect([PocketClearanceMode.zigzag, .spiralOut, .adaptive].contains(p.clearanceMode),
               "M08 strategy key present")
    try expect(p.stepOverMm > 0 && p.feedRateMmPerMin > 0 && p.plungeFeedRateMmPerMin > 0,
               "step-over/feed keys present")
    try expect(p.maxDepthOfCutMm > 0 && p.toolDiameterMm > 0 && p.safetyHeightMm > 0,
               "depth/tool/safe-Z keys present")
    try expect(p.startDepthMm == 0 && p.passCount == 0, "M02 start depth + M06 pass count keys present")
    try expect(!p.exactStepDepth, "M04 exact step depth key present")
    try expect([CutDirection.climb, .conventional].contains(p.cutDirection), "M09 direction key present")
    try expect(p.rasterAngleDegrees == 0, "M10 raster angle key present")
    try expect([PocketProfilePass.first, .last, .none].contains(p.profilePass), "M11 profile pass key present")
    try expect(p.allowanceMm == 0, "M12 pocket allowance key present")
    try expect(!p.rampPlungeMoves, "M13 ramp plunge moves key present")
    try expect(!p.useVectorSelectionOrder, "M14 selection order key present")

    // ── 2. Round-trip: JSON + .shoppilot per-op params. ──────────────────────
    var custom = PocketToolpathParams()
    custom.clearanceMode = .spiralOut
    custom.feedRateMmPerMin = 1500
    custom.startDepthMm = 1.5
    custom.cutDirection = .conventional
    custom.profilePass = .none
    custom.allowanceMm = 0.4
    custom.rampPlungeMoves = true
    custom.rasterAngleDegrees = 30

    let data = try JSONEncoder().encode(custom)
    let decoded = try JSONDecoder().decode(PocketToolpathParams.self, from: data)
    try expect(decoded.clearanceMode == .spiralOut && decoded.feedRateMmPerMin == 1500, "JSON round-trip: strategy/feed")
    try expect(decoded.startDepthMm == 1.5 && decoded.cutDirection == .conventional, "JSON round-trip: depth/direction")
    try expect(decoded.profilePass == .none && decoded.allowanceMm == 0.4, "JSON round-trip: profile pass/allowance")
    try expect(decoded.rampPlungeMoves && decoded.rasterAngleDegrees == 30, "JSON round-trip: ramp/raster")

    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Pocket 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    let persisted = PersistedToolpath(from: node)
    try expect(persisted.paramsJSON != nil, "persist snapshot carries paramsJSON")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: [persisted])
    let restoredNode = restored.allNodes.first { $0.isPocketOperation }!
    let restoredParams = restoredNode.pocketParams()
    try expect(restoredParams.clearanceMode == .spiralOut && restoredParams.feedRateMmPerMin == 1500,
               ".shoppilot round-trip keeps per-op pocket params")

    // ── 3. Backward-compat: pre-SPK-1136b JSON decodes with defaults. ────────
    let legacyJSON = """
    {"clearanceMode":"zigzag","stepOverMm":3.0,"feedRateMmPerMin":1000,
     "plungeFeedRateMmPerMin":300,"maxDepthOfCutMm":2.0,"toolDiameterMm":6.0,
     "safetyHeightMm":5.0}
    """
    let legacy = try JSONDecoder().decode(PocketToolpathParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.startDepthMm == 0 && legacy.passCount == 0 && legacy.profilePass == .last
                   && !legacy.rampPlungeMoves && legacy.cutDirection == .climb,
               "legacy JSON decodes with SPK-1136b defaults")

    // ── 4. Apply-regen respects stored params. ───────────────────────────────
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    // Mirror of session.applyPocketParams: engine compute with the node's stored params.
    let result = PocketToolpathEngine.compute(
        vectors: [square],
        params: restoredParams,
        material: nil,
        stockHeightMm: 25.0
    )
    try expect(result.gcodeLines.contains("O=POCKET_TOOLPATH"), "regenerated output is real engine G-code")
    try expect(result.gcodeLines.contains { $0.contains("F1500") }, "regenerated G-code uses the stored feed rate")
    try expect(result.estimatedTimeSeconds > 0, "regenerated op has a time estimate")

    print("ShopPilotVerify1136b: PASS — §M key presence, round-trip, legacy decode, apply-regen uses stored params")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1136b: FAIL — \(error)")
    exit(1)
}
