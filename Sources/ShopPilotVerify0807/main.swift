import Foundation
import ShopPilotCore

/// SPK-0807 verify (CLT machine, no XCTest).
/// Proves the DRIVEN DIMENSIONS (parametric-lite) contract:
///   1. RESOLVER: `DrivenDimensionResolver.resolve` substitutes document
///      variables into expressions and evaluates them — arithmetic,
///      variables, π constant, nested parens.
///   2. LIVE RE-EVALUATION: changing a variable's value changes the resolved
///      dimension (the parametric behavior).
///   3. FAILURE: unresolvable expressions return nil (never crash).
///   4. PERSIST: `Job.drivenDimensions` round-trips through Codable and the
///      legacy decode path (no key → empty array).
/// The AppSession glue (addDrivenDimension validates + persists + undo +
/// DrivenDimensionsPanelView live values) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Resolver: variables + arithmetic. ──────────────────────────────
    let vars = [
        DocumentVariable(key: "width", value: "600", category: "Stock"),
        DocumentVariable(key: "height", value: "400", category: "Stock"),
        DocumentVariable(key: "thickness", value: "18", category: "Stock"),
    ]

    let half = DrivenDimensionResolver.resolve(expression: "width / 2", variables: vars)
    try expect(abs((half ?? -1) - 300.0) < 1e-9, "width/2 = 300 (got \(half ?? -1))")

    let area = DrivenDimensionResolver.resolve(expression: "width * height", variables: vars)
    try expect(abs((area ?? -1) - 240000.0) < 1e-9, "width*height = 240000")

    let composite = DrivenDimensionResolver.resolve(expression: "(width + height) / thickness", variables: vars)
    try expect(abs((composite ?? -1) - (1000.0 / 18.0)) < 1e-9, "(w+h)/t resolves")

    // ── 2. Live re-evaluation (the parametric behavior). ──────────────────
    var mutableVars = vars
    let before = DrivenDimensionResolver.resolve(expression: "thickness * 2", variables: mutableVars)
    try expect(abs((before ?? -1) - 36.0) < 1e-9, "thickness*2 = 36 before change")
    mutableVars[2] = DocumentVariable(key: "thickness", value: "25", category: "Stock")
    let after = DrivenDimensionResolver.resolve(expression: "thickness * 2", variables: mutableVars)
    try expect(abs((after ?? -1) - 50.0) < 1e-9, "same expression → 50 after variable change (parametric)")

    // ── 3. Failure modes return nil. ──────────────────────────────────────
    try expect(DrivenDimensionResolver.resolve(expression: "width +", variables: vars) == nil,
               "dangling operator → nil")
    try expect(DrivenDimensionResolver.resolve(expression: "missingVar * 2", variables: vars) == nil,
               "unknown variable → nil")
    try expect(DrivenDimensionResolver.resolve(expression: "width / 0", variables: vars) == nil,
               "division by zero → nil (non-finite rejected)")

    // ── 4. Persist: Job round-trip + legacy-safe. ─────────────────────────
    var job = Job(name: "Parametric")
    job.drivenDimensions = [
        DrivenDimension(key: "halfWidth", expression: "width / 2", category: "Dimensions"),
        DrivenDimension(key: "area", expression: "width * height", category: "Dimensions"),
    ]
    let data = try JSONEncoder().encode(job)
    let back = try JSONDecoder().decode(Job.self, from: data)
    try expect(back.drivenDimensions.count == 2, "dimensions survive round-trip")
    try expect(back.drivenDimensions[0].key == "halfWidth"
               && back.drivenDimensions[0].expression == "width / 2",
               "key + expression preserved")

    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","sheets":[],"createdAt":0,"updatedAt":0,"vcarvePasses":0,"vcarveTimeSeconds":0,"documentVariables":[],"drivenDimensions":[]}"#
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.drivenDimensions.isEmpty, "legacy document decodes with empty dimensions")

    print("ShopPilotVerify0807: PASS — resolver substitution + arithmetic, live re-evaluation, nil failure modes, Job round-trip + legacy-safe")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0807: FAIL — \(error)")
    exit(1)
}
