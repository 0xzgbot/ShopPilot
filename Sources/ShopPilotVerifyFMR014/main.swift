import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-FM-R014 verify (CLT machine, no XCTest).
/// Proves the THROUGH-CUT WITHOUT HOLD-DOWN preflight rule (FM-07 → NEW R014):
///   1. TRIGGER: a profile cut through the full material thickness
///      (maxDepthOfCutMm ≥ material) with NO tabs and NO vacuum hold-down on
///      the machine profile → warning issue, plain-English copy, "Add Tabs" CTA.
///   2. SUPPRESSION: tabs enabled → nil; cut not through the material → nil;
///      machine profile has vacuumHoldDown → nil (the table holds the part).
///   3. TREE INTEGRATION: checkTree flags the Profile op via real paramsJSON,
///      never the V-Carve op, and honors session dismissals.
///   4. PERSIST: applying the fix (addTabs = true) round-trips through the
///      node's paramsJSON and the rule stops firing; `MachineProfile`
///      vacuumHoldDown round-trips and legacy profiles (no key) decode false.
/// The session/UI glue (Add Tabs / Warn Only alert before the save panel,
/// active-profile vacuum flag) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func encodeParams(_ params: ProfileToolpathParams) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func makeThroughCutParams() -> ProfileToolpathParams {
    var params = ProfileToolpathParams()
    params.maxDepthOfCutMm = 6.0
    params.addTabs = false
    return params
}

func main() throws {
    // ── 1. Trigger: through-cut, no tabs, no vacuum → warning. ─────────────
    let params = makeThroughCutParams()
    let issue = ToolpathPreflight.throughCutWithoutHoldDown(
        params: params,
        materialThicknessMm: 6.0,
        vacuumHoldDown: false
    )
    guard let issue else { throw VerifyError.failed("through-cut with no tabs/vacuum must warn") }
    try expect(issue.ruleID == "R014", "rule id is R014")
    try expect(issue.severity == .warning, "fly-out is a warning (override)")
    try expect(issue.message.contains("fly"), "plain-English copy surfaces the fly-out: \(issue.message)")
    try expect(issue.fix.isAddTabsFix, "fix CTA is Add Tabs")

    // ── 2. Suppression: tabs / shallow cut / vacuum hold-down. ─────────────
    var withTabs = params
    withTabs.addTabs = true
    try expect(ToolpathPreflight.throughCutWithoutHoldDown(params: withTabs, materialThicknessMm: 6.0, vacuumHoldDown: false) == nil,
               "tabs enabled → no fly-out warning")

    var shallow = params
    shallow.maxDepthOfCutMm = 3.0
    try expect(ToolpathPreflight.throughCutWithoutHoldDown(params: shallow, materialThicknessMm: 6.0, vacuumHoldDown: false) == nil,
               "cut not through the material → no warning")

    try expect(ToolpathPreflight.throughCutWithoutHoldDown(params: params, materialThicknessMm: 6.0, vacuumHoldDown: true) == nil,
               "vacuum hold-down holds the part → no warning")

    // ── 3. Tree integration: Profile op flagged, V-Carve not, dismissal. ───
    let tree = ToolpathTreeManager()
    let profileNode = tree.addOperation("Profile Cutout")
    profileNode.paramsJSON = encodeParams(params)
    profileNode.clearDirty()
    let vcarveNode = tree.addOperation("V-Carve Detail")
    vcarveNode.paramsJSON = (try? JSONEncoder().encode(VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1000)))
        .flatMap { String(data: $0, encoding: .utf8) }
    vcarveNode.clearDirty()

    let issues = ToolpathPreflight.checkTree(tree, vectors: [], materialThicknessMm: 6.0, vacuumHoldDown: false)
    try expect(issues.count == 1, "checkTree flags exactly the Profile op (got \(issues.count))")
    try expect(issues[0].nodeName == "Profile Cutout", "issue names the offending node")
    try expect(issues[0].nodeID == profileNode.id, "issue carries the node id for the CTA")

    let withVacuum = ToolpathPreflight.checkTree(tree, vectors: [], materialThicknessMm: 6.0, vacuumHoldDown: true)
    try expect(withVacuum.isEmpty, "vacuum profile clears the tree-level rule")

    let dismissed = ToolpathPreflight.checkTree(tree, vectors: [], materialThicknessMm: 6.0,
                                                dismissedNodeIDs: [profileNode.id])
    try expect(dismissed.isEmpty, "warn-only dismissal skips the node this session")

    // ── 4. Persist: the fix round-trips through paramsJSON and clears. ─────
    var fixed = params
    fixed.addTabs = true
    profileNode.paramsJSON = encodeParams(fixed)
    let afterFix = ToolpathPreflight.checkTree(tree, vectors: [], materialThicknessMm: 6.0)
    try expect(afterFix.isEmpty, "add-tabs fix persisted in paramsJSON clears the rule")

    guard let json = profileNode.paramsJSON,
          let data = json.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(ProfileToolpathParams.self, from: data) else {
        throw VerifyError.failed("fixed paramsJSON decodes")
    }
    try expect(decoded.addTabs, "addTabs survives the Codable round-trip")

    // MachineProfile vacuumHoldDown: round-trip + legacy decode (no key → false).
    let profile = MachineProfile(name: "Table Vac", config: .simulator, isSimulator: true, vacuumHoldDown: true)
    let profileData = try JSONEncoder().encode(profile)
    let profileBack = try JSONDecoder().decode(MachineProfile.self, from: profileData)
    try expect(profileBack.vacuumHoldDown, "vacuumHoldDown survives the profile round-trip")

    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Legacy","config":{"baudRate":115200,"portName":"/dev/ttyUSB0","dataBits":8,"parity":"none","stopBits":"one"},"isSimulator":false,"machineType":"grbl","units":"millimeter","createdAt":0,"updatedAt":0}
    """
    let legacy = try JSONDecoder().decode(MachineProfile.self, from: Data(legacyJSON.utf8))
    try expect(!legacy.vacuumHoldDown, "legacy profile without the key decodes vacuumHoldDown = false (conservative)")

    print("ShopPilotVerifyFMR014: PASS — through-cut trigger (warning, plain CTA), tabs/shallow/vacuum suppression, tree integration + dismissal, paramsJSON + MachineProfile persistence, legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyFMR014: FAIL — \(error)")
    exit(1)
}
