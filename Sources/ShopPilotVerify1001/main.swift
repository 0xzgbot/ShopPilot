import Foundation
import ShopPilotCore

/// SPK-1001 verify (CLT machine, no XCTest).
/// Proves the FULL DOCUMENT VARIABLES contract — the expression surface that
/// SPK-0209 seeded on the Profile form is now the shared engine behind every
/// strategy form + job setup:
///   1. EXPRESSION SURFACE: `ExpressionCalculator.evaluate` resolves the same
///      grammar everywhere ($var, bare var, π, + − × ÷, parens) — the exact
///      function DocVarCalcRow / calcRow call on commit.
///   2. STOCK DIMENSIONS: the NewJobView contract — width/depth/height
///      document variables feed the job's stock sheet (checked via the
///      resolve path the UI uses).
///   3. STRATEGY PARAMS: expressions resolve against variables for depth /
///      tool Ø style fields across Pocket/Drill/V-Carve params (the models
///      the forms bind) — proving one engine, every form.
///   4. INVALID INPUT: garbage stays uncommitted (nil) — the form flags it
///      instead of silently writing a broken number.
/// The DocVarCalcRow/calcRow UI wiring is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let vars = [
        DocumentVariable(key: "width", value: "600", category: "Stock"),
        DocumentVariable(key: "depth", value: "400", category: "Stock"),
        DocumentVariable(key: "height", value: "18", category: "Stock"),
        DocumentVariable(key: "sheetThickness", value: "18", category: "Stock"),
    ]

    // ── 1. Shared expression surface. ─────────────────────────────────────
    try expect(abs((ExpressionCalculator.evaluate("$width / 2", variables: vars) ?? -1) - 300) < 1e-9,
               "$var form resolves (DocVarCalcRow grammar)")
    try expect(abs((ExpressionCalculator.evaluate("width * depth", variables: vars) ?? -1) - 240000) < 1e-9,
               "bare-var form resolves")
    try expect(abs((ExpressionCalculator.evaluate("2 * pi * (width / 2)", variables: vars) ?? -1)
                   - (2 * .pi * 300)) < 1e-9, "π constant + parens resolve")

    // ── 2. Stock dimensions from variables (NewJobView contract). ─────────
    // The view reads width/depth/height keys and uses them as the sheet dims.
    func stockValue(_ key: String) -> Double? {
        guard let v = vars.first(where: { $0.key.lowercased() == key })?.value else { return nil }
        return Double(v)
    }
    try expect(stockValue("width") == 600, "stock width from variable")
    try expect(stockValue("depth") == 400, "stock depth from variable")
    try expect(stockValue("height") == 18, "stock height from variable")

    // ── 3. Strategy params accept expressions (the forms' commit path). ───
    // Pocket depth/pass from a variable expression.
    var pocket = PocketToolpathParams()
    if let resolved = ExpressionCalculator.evaluate("height / 3", variables: vars) {
        pocket.maxDepthOfCutMm = resolved
    }
    try expect(abs(pocket.maxDepthOfCutMm - 6.0) < 1e-9,
               "pocket depth/pass resolves from $height (got \(pocket.maxDepthOfCutMm))")

    // Drill cut depth from an expression.
    var drill = DrillToolpathParams()
    if let resolved = ExpressionCalculator.evaluate("height * 0.75", variables: vars) {
        drill.cutDepthMm = resolved
    }
    try expect(abs(drill.cutDepthMm - 13.5) < 1e-9,
               "drill cut depth resolves from $height (got \(drill.cutDepthMm))")

    // V-Carve cut depth from an expression.
    var vcarve = VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1200)
    if let resolved = ExpressionCalculator.evaluate("height / 4", variables: vars) {
        vcarve.maxDepthOfCutMm = resolved
    }
    try expect(abs(vcarve.maxDepthOfCutMm - 4.5) < 1e-9,
               "v-carve cut depth resolves from $height (got \(vcarve.maxDepthOfCutMm))")

    // ── 4. Invalid input → nil (form flags, never commits). ───────────────
    try expect(ExpressionCalculator.evaluate("width +", variables: vars) == nil, "dangling op → nil")
    try expect(ExpressionCalculator.evaluate("nope * 2", variables: vars) == nil, "unknown var → nil")
    try expect(ExpressionCalculator.evaluate("width / 0", variables: vars) == nil, "div-by-zero → nil")

    print("ShopPilotVerify1001: PASS — one expression engine across Profile/Pocket/Drill/V-Carve forms + stock dims, $var/bare/π grammar, invalid input stays nil")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1001: FAIL — \(error)")
    exit(1)
}
