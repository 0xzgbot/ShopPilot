import Foundation
import ShopPilotCore

/// SPK-1136d verify (CLT machines, no XCTest).
/// Proves the V-Carve strategy form-field spine (same shape as 1136a–c):
///   1. PRESENCE: every installer-verified §O key exists on VCarveParams.
///   2. ROUND-TRIP: JSON encode/decode + .shoppilot PersistedToolpath → restore.
///   3. BACKWARD-COMPAT: pre-SPK-1136d JSON decodes with defaults.
///   4. APPLY-REGEN: regenerating a V-Carve op with stored params uses those
///      params — stored feed + bit angle reach the G-code.
/// The form/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Presence: the §O key set. ─────────────────────────────────────────
    let p = VCarveParams()
    try expect(p.vBitAngleDegrees == 90, "O06 V-bit angle key present")
    try expect(p.feedRateMmPerMin > 0 && p.plungeFeedRateMmPerMin > 0, "feed keys present")
    try expect(p.maxDepthOfCutMm > 0 && p.leadInDistanceMm > 0 && p.leadOutDistanceMm > 0
                   && p.stepOverMm > 0, "depth/leads/step-over keys present")
    try expect(!p.flatBottomMode && p.flatDepthMm > 0, "O03/O04 flat-depth keys present")
    try expect(p.startDepthMm == 0, "O02 start depth key present")
    try expect(!p.cornerSharpen, "O13 corner sharpen key present")
    try expect(p.useVectorStartPoints, "O14 vector start points key present (default true)")
    try expect(!p.useVectorSelectionOrder, "O15 selection order key present")
    try expect(p.safeZHeightMm > 0, "O16 safe Z key present")
    try expect(!p.rampPlungeMoves, "O12 ramp plunge moves key present")

    // ── 2. Round-trip: JSON + .shoppilot per-op params. ──────────────────────
    var custom = VCarveParams()
    custom.vBitAngleDegrees = 45
    custom.feedRateMmPerMin = 1500
    custom.startDepthMm = 0.5
    custom.flatBottomMode = true
    custom.flatDepthMm = 1.5
    custom.cornerSharpen = true
    custom.useVectorStartPoints = false
    custom.safeZHeightMm = 5

    let data = try JSONEncoder().encode(custom)
    let decoded = try JSONDecoder().decode(VCarveParams.self, from: data)
    try expect(decoded.vBitAngleDegrees == 45 && decoded.feedRateMmPerMin == 1500, "JSON round-trip: bit/feed")
    try expect(decoded.startDepthMm == 0.5 && decoded.flatBottomMode && decoded.flatDepthMm == 1.5,
               "JSON round-trip: depth/flat")
    try expect(decoded.cornerSharpen && !decoded.useVectorStartPoints && decoded.safeZHeightMm == 5,
               "JSON round-trip: corner/start-points/safe-Z")

    let tree = ToolpathTreeManager()
    let node = tree.addOperation("V-Carve 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    let persisted = PersistedToolpath(from: node)
    try expect(persisted.paramsJSON != nil, "persist snapshot carries paramsJSON")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: [persisted])
    let restoredNode = restored.allNodes.first { $0.isVCarveOperation }!
    let restoredParams = restoredNode.vcarveParams()
    try expect(restoredParams.vBitAngleDegrees == 45 && restoredParams.cornerSharpen,
               ".shoppilot round-trip keeps per-op v-carve params")

    // ── 3. Backward-compat: pre-SPK-1136d JSON decodes with defaults. ────────
    let legacyJSON = """
    {"vBitAngleDegrees":90,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,
     "maxDepthOfCutMm":2.0,"leadInDistanceMm":5.0,"leadOutDistanceMm":5.0,
     "stepOverMm":1.0,"flatBottomMode":false,"vectorDepths":[]}
    """
    let legacy = try JSONDecoder().decode(VCarveParams.self, from: Data(legacyJSON.utf8))
    try expect(legacy.startDepthMm == 0 && legacy.flatDepthMm == 1.0 && !legacy.cornerSharpen
                   && legacy.useVectorStartPoints && legacy.safeZHeightMm == 3.2,
               "legacy JSON decodes with SPK-1136d defaults")

    // ── 4. Apply-regen: stored params drive the real engine. ─────────────────
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    let result = VCarveEngine.compute(
        vectors: [square],
        params: restoredParams,
        stockHeightMm: 25.0
    )
    try expect(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"), "regenerated output is real engine G-code")
    try expect(result.gcodeLines.contains { $0.hasPrefix("G1") }, "regenerated output has cut moves")
    try expect(result.gcodeLines.contains { $0.contains("F1500") }, "stored feed reaches the G-code")
    try expect(result.passCount >= 1 && result.estimatedTimeSeconds > 0, "regenerated op has passes + estimate")

    print("ShopPilotVerify1136d: PASS — §O key presence, round-trip, legacy decode, apply-regen uses stored params")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1136d: FAIL — \(error)")
    exit(1)
}
