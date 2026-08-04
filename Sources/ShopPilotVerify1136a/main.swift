import Foundation
import ShopPilotCore

/// SPK-1136a verify (CLT machines, no XCTest).
/// Proves the Profile strategy form-field spine:
///   1. PRESENCE: every installer-verified §R2 key (tabs / ramping / leads /
///      corners / direction) exists on ProfileToolpathParams with sane
///      defaults — the "every key present in the model" AC.
///   2. ROUND-TRIP: params survive JSON encode/decode, and survive the
///      .shoppilot PersistedToolpath → restoreToolpathTree path (per-op
///      paramsJSON), so save/open keeps the form's configuration.
///   3. BACKWARD-COMPAT: JSON written before SPK-1136a (no new keys) decodes
///      with defaults — old documents still load.
///   4. RECALC RESPECTS STORED PARAMS: a node with custom params regenerates
///      with those params (feed rate + cut mode visible in the G-code), not
///      the session defaults.
/// The form/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    // ── 1. Presence: the §R2 key set exists on the model. ────────────────────
    let p = ProfileToolpathParams()
    // Cut / feeds / depth (original core).
    try expect([ProfileCutMode.outCut, .inCut, .onCut].contains(p.cutMode), "cut mode key present")
    try expect(p.feedRateMmPerMin > 0 && p.plungeFeedRateMmPerMin > 0, "feed keys present")
    try expect(p.maxDepthOfCutMm > 0 && p.toolDiameterMm > 0, "depth/tool keys present")
    try expect(p.finishPasses >= 1, "finish passes key present")
    // Tabs page (L13/L14/L15/L16).
    try expect(!p.addTabs && p.tabLengthMm > 0 && p.tabThicknessMm > 0 && p.tabSpacingMm > 0
                   && !p.use3DTabs, "tabs key set present (add/length/thickness/spacing/3D)")
    // Ramping page (L17/L18).
    try expect(p.rampType != .none || p.rampDistanceMm >= 0, "ramp type + distance keys present")
    // Leads page (L20–L24).
    try expect(p.leadInType == .none && p.leadInDistanceMm > 0 && p.leadInAngleDegrees > 0
                   && p.circularLeadRadiusMm > 0 && !p.doLeadOut && p.leadOutDistanceMm > 0,
               "lead-in/out key set present (type/length/angle/radius/lead-out)")
    // Corners page (L28/L29).
    try expect(!p.sharpExternalCorner && !p.sharpInternalCorner, "corner keys present")
    // Direction (F40: Climb/Conventional).
    try expect([ProfileCutDirection.climb, .conventional].contains(p.cutDirection),
               "cut direction key present")

    // ── 2. Round-trip: JSON + .shoppilot per-op params. ─────────────────────
    var custom = ProfileToolpathParams()
    custom.cutMode = .inCut
    custom.feedRateMmPerMin = 1500
    custom.addTabs = true
    custom.tabLengthMm = 8
    custom.rampType = .spiral
    custom.leadInType = .circularArc
    custom.doLeadOut = true
    custom.sharpExternalCorner = true
    custom.cutDirection = .conventional

    let data = try JSONEncoder().encode(custom)
    let decoded = try JSONDecoder().decode(ProfileToolpathParams.self, from: data)
    try expect(decoded.cutMode == .inCut && decoded.feedRateMmPerMin == 1500, "JSON round-trip: cut/feed")
    try expect(decoded.addTabs && decoded.tabLengthMm == 8, "JSON round-trip: tabs")
    try expect(decoded.rampType == .spiral && decoded.leadInType == .circularArc, "JSON round-trip: ramp/lead")
    try expect(decoded.doLeadOut && decoded.sharpExternalCorner, "JSON round-trip: lead-out/corner")
    try expect(decoded.cutDirection == .conventional, "JSON round-trip: direction")

    // PersistedToolpath → payload → restore keeps paramsJSON on the node.
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    node.paramsJSON = String(data: data, encoding: .utf8)
    let persisted = PersistedToolpath(from: node)
    try expect(persisted.paramsJSON != nil, "persist snapshot carries paramsJSON")
    let restored = ShopPilotPackagePayload.restoreToolpathTree(from: [persisted])
    let restoredNode = restored.allNodes.first { $0.isProfileOperation }!
    let restoredParams = restoredNode.profileParams()
    try expect(restoredParams.feedRateMmPerMin == 1500 && restoredParams.addTabs,
               ".shoppilot round-trip keeps per-op params")

    // ── 3. Backward-compat: pre-SPK-1136a JSON decodes with defaults. ────────
    let legacyJSON = """
    {"cutMode":"onCut","feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,
     "maxDepthOfCutMm":2.0,"toolDiameterMm":6.0,"tabWidths":[],
     "finishPasses":1,"leadInDistanceMm":5.0,"leadOutDistanceMm":5.0}
    """
    let legacy = try JSONDecoder().decode(
        ProfileToolpathParams.self,
        from: Data(legacyJSON.utf8)
    )
    try expect(!legacy.addTabs && legacy.rampType == .smooth && legacy.leadInType == .none
                   && legacy.cutDirection == .climb,
               "legacy JSON decodes with SPK-1136a defaults")

    // ── 4. Recalc respects stored params (not session defaults). ────────────
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    let dirtyNode = tree.addOperation("Profile 2")
    dirtyNode.paramsJSON = String(data: try JSONEncoder().encode(custom), encoding: .utf8)
    dirtyNode.toolpathResult = "// stale"
    dirtyNode.markDirty()

    let regenerated = tree.recalculateDirtyProfiles(
        vectors: [square],
        params: ProfileToolpathParams(),  // session defaults — must NOT win
        material: nil,
        stockHeightMm: 6.0
    )
    try expect(regenerated.contains { $0 === dirtyNode }, "custom-params node regenerated")
    let gcode = dirtyNode.toolpathResult ?? ""
    try expect(gcode.contains("F1500"), "regenerated G-code uses the stored feed rate")
    try expect(gcode.contains("O=PROFILE_TOOLPATH"), "regenerated G-code is real engine output")
    try expect(!dirtyNode.isDirty, "dirty flag cleared after recalc")

    print("ShopPilotVerify1136a: PASS — §R2 key presence, round-trip, legacy decode, recalc respects stored params")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1136a: FAIL — \(error)")
    exit(1)
}
