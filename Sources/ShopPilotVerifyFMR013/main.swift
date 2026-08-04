import Foundation
import ShopPilotCore

/// SPK-FM-R013 verify (CLT machine, no XCTest).
/// Proves the V-CARVE PUNCH-THROUGH preflight rule (FM-06 → NEW R013):
///   1. MATH: `maxVectorGapWidth` measures the widest channel between
///      vectors (two parallel strokes 20mm apart → 20.0); `maxVDepth` derives
///      the depth the V-bit must reach to span it (90° bit → gap/2; 45° bit →
///      gap / 2·tan(22.5°) ≈ 24.14 for a 20mm gap).
///   2. TRIGGER: wide gap + thin material + NO flat depth → error issue with
///      plain-English copy and a "Set Flat Depth" CTA prefilled to
///      materialThickness − safetyMargin (6mm stock → 5.5mm).
///   3. SUPPRESSION: flatBottomMode ON floors the carve → no issue; narrow
///      gap that fits the material → no issue; a single vector has nothing to
///      bridge → no issue.
///   4. TREE INTEGRATION: `checkTree` flags the V-Carve op with the real
///      paramsJSON, skips non-V-Carve ops, and honors session dismissals.
///   5. PERSIST: applying the fix (flatBottomMode=true + capped
///      maxDepthOfCutMm) round-trips through the node's paramsJSON and the
///      rule stops firing — the fix survives save/open exactly like every
///      other per-op param.
/// The session/UI glue (alert with Set Flat Depth / Warn Only CTAs before the
/// save panel) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func lineVector(x: Double, y0: Double, y1: Double) -> VectorPath {
    VectorPath(points: [
        VectorPoint(x: x, y: y0),
        VectorPoint(x: x, y: y1),
    ], isClosed: false)
}

func encodeParams(_ params: VCarveParams) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func main() throws {
    // ── 1. Math: gap width + derived V depth. ──────────────────────────────
    let gapVectors = [lineVector(x: 0, y0: 0, y1: 20), lineVector(x: 20, y0: 0, y1: 20)]
    let gap = ToolpathPreflight.maxVectorGapWidth(vectors: gapVectors)
    try expect(abs(gap - 20.0) < 1e-6, "widest channel between 20mm-apart strokes is 20mm (got \(gap))")
    try expect(abs(ToolpathPreflight.maxVDepth(vBitAngleDegrees: 90, gapWidthMm: 20) - 10.0) < 1e-6,
               "90° bit spans a 20mm gap at 10mm depth")
    try expect(abs(ToolpathPreflight.maxVDepth(vBitAngleDegrees: 45, gapWidthMm: 20) - 24.142) < 0.01,
               "45° bit needs ~24.14mm to span a 20mm gap")
    try expect(ToolpathPreflight.maxVectorGapWidth(vectors: [lineVector(x: 0, y0: 0, y1: 20)]) == 0,
               "single vector has nothing to bridge")

    // ── 2. Trigger: wide gap, thin material, no flat depth → error. ────────
    var params = VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1000)
    params.flatBottomMode = false
    let issue = try unwrap(ToolpathPreflight.vCarvePunchThrough(
        params: params,
        vectors: gapVectors,
        materialThicknessMm: 6.0
    ))
    try expect(issue.ruleID == "R013", "rule id is R013")
    try expect(issue.severity == .error, "punch-through is an error (blocks export)")
    try expect(issue.message.contains("through your material"), "plain-English copy surfaces the through-cut: \(issue.message)")
    guard case .setFlatDepth(let recommended) = issue.fix else {
        throw VerifyError.failed("fix CTA is Set Flat Depth")
    }
    try expect(abs(recommended - 5.5) < 0.001, "flat-depth prefill = material 6mm − 0.5mm safety margin (got \(recommended))")

    // ── 3. Suppression: flat bottom floors it; fit gap; single vector. ─────
    var floored = params
    floored.flatBottomMode = true
    try expect(ToolpathPreflight.vCarvePunchThrough(params: floored, vectors: gapVectors, materialThicknessMm: 6.0) == nil,
               "flat-bottom floor suppresses punch-through")

    let narrow = [lineVector(x: 0, y0: 0, y1: 20), lineVector(x: 2, y0: 0, y1: 20)]
    try expect(ToolpathPreflight.vCarvePunchThrough(params: params, vectors: narrow, materialThicknessMm: 6.0) == nil,
               "2mm gap fits 6mm stock (1mm needed) — no issue")
    try expect(ToolpathPreflight.vCarvePunchThrough(params: params, vectors: [lineVector(x: 0, y0: 0, y1: 20)], materialThicknessMm: 6.0) == nil,
               "single-vector carve cannot punch through")

    // ── 4. Tree integration: real paramsJSON, V-Carve ops only, dismissals. ─
    let tree = ToolpathTreeManager()
    let vcarveNode = tree.addOperation("V-Carve Wide")
    vcarveNode.paramsJSON = encodeParams(params)
    vcarveNode.clearDirty()
    let profileNode = tree.addOperation("Profile Outline")
    profileNode.paramsJSON = (try? JSONEncoder().encode(ProfileToolpathParams())).flatMap { String(data: $0, encoding: .utf8) }
    profileNode.clearDirty()

    let issues = ToolpathPreflight.checkTree(tree, vectors: gapVectors, materialThicknessMm: 6.0)
    try expect(issues.count == 1, "checkTree flags exactly the V-Carve op (got \(issues.count))")
    try expect(issues[0].nodeName == "V-Carve Wide", "issue names the offending node")
    try expect(issues[0].nodeID == vcarveNode.id, "issue carries the node id for the CTA")

    let dismissed = ToolpathPreflight.checkTree(tree, vectors: gapVectors, materialThicknessMm: 6.0,
                                                dismissedNodeIDs: [vcarveNode.id])
    try expect(dismissed.isEmpty, "warn-only dismissal skips the node this session")

    // ── 5. Persist: the fix round-trips through paramsJSON and clears. ─────
    var fixed = params
    fixed.flatBottomMode = true
    fixed.maxDepthOfCutMm = min(fixed.maxDepthOfCutMm, 5.5)
    vcarveNode.paramsJSON = encodeParams(fixed)
    let afterFix = ToolpathPreflight.checkTree(tree, vectors: gapVectors, materialThicknessMm: 6.0)
    try expect(afterFix.isEmpty, "flat-depth fix persisted in paramsJSON clears the rule")

    // Round-trip the persisted node params (save/open semantics).
    guard let json = vcarveNode.paramsJSON,
          let data = json.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(VCarveParams.self, from: data) else {
        throw VerifyError.failed("fixed paramsJSON decodes")
    }
    try expect(decoded.flatBottomMode, "flatBottomMode survives the Codable round-trip")
    try expect(decoded.maxDepthOfCutMm <= 5.5 + 1e-9, "capped depth survives the Codable round-trip")

    print("ShopPilotVerifyFMR013: PASS — gap math, wide-gap trigger (error, plain CTA, 5.5mm prefill), flat-bottom/narrow/single suppression, tree integration + dismissal, paramsJSON persistence")
}

func unwrap(_ issue: ToolpathPreflightIssue?) throws -> ToolpathPreflightIssue {
    guard let issue else { throw VerifyError.failed("wide-gap carve must produce an issue") }
    return issue
}

do {
    try main()
} catch {
    print("ShopPilotVerifyFMR013: FAIL — \(error)")
    exit(1)
}
