import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0209 verify (CLT machines, no XCTest).
/// Proves the calculation edit-box engine (`ExpressionCalculator`):
///   1. Arithmetic: + − × ÷, parentheses, decimals, precedence.
///   2. Constants: π / pi.
///   3. Variables: `$width` and bare `width` resolve from document vars;
///      longest-key-first substitution (width vs wide).
///   4. Invalid input → nil (never a partial/false result).
///   5. DrivenDimensionResolver (the existing consumer) still resolves.
///   6. Back-compat: the legacy parse path (plain numbers) is unchanged.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double?, _ b: Double, _ msg: String, tol: Double = 1e-6) throws {
    guard let a else { throw VerifyError.failed("\(msg): expected \(b), got nil") }
    if abs(a - b) > tol { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func vars(_ pairs: [(String, String)]) -> [DocumentVariable] {
    pairs.map { DocumentVariable(key: $0.0, value: $0.1, category: "Test") }
}

func main() throws {
    // ── 1. Arithmetic + precedence ─────────────────────────────────────────
    try expectClose(ExpressionCalculator.evaluate("2+3"), 5, "add")
    try expectClose(ExpressionCalculator.evaluate("2*3+4"), 10, "precedence")
    try expectClose(ExpressionCalculator.evaluate("2 * 3 + 4"), 10, "spaced operators")
    try expectClose(ExpressionCalculator.evaluate("2440 / 2"), 1220, "spaced division")
    try expectClose(ExpressionCalculator.evaluate("2*(3+4)"), 14, "parens")
    try expectClose(ExpressionCalculator.evaluate("10/4"), 2.5, "divide")
    try expectClose(ExpressionCalculator.evaluate("7-2-1"), 4, "left-assoc minus")
    try expectClose(ExpressionCalculator.evaluate("1.5*2"), 3, "decimals")

    // ── 2. Constants ───────────────────────────────────────────────────────
    try expectClose(ExpressionCalculator.evaluate("pi"), Double.pi, "pi constant")
    try expectClose(ExpressionCalculator.evaluate("2*π"), 2 * Double.pi, "π constant")
    try expectClose(ExpressionCalculator.evaluate("2*pi*r", variables: vars([("r", "3")])),
                    2 * Double.pi * 3,
                    "circle circumference with r=3", tol: 1e-6)

    // ── 3. Variables ───────────────────────────────────────────────────────
    let v = vars([("width", "100"), ("depth", "4"), ("wide", "7")])
    try expectClose(ExpressionCalculator.evaluate("width/2", variables: v), 50, "$-less var")
    try expectClose(ExpressionCalculator.evaluate("$width/2", variables: v), 50, "$-prefixed var")
    try expectClose(ExpressionCalculator.evaluate("width*depth", variables: v), 400, "two vars")
    // Longest-key-first: "wide" must not be swallowed by "width".
    try expectClose(ExpressionCalculator.evaluate("wide", variables: v), 7, "longest-key substitution")
    try expectClose(ExpressionCalculator.evaluate("width", variables: v), 100, "width intact after wide")

    // ── 4. Invalid input → nil ─────────────────────────────────────────────
    try expect(ExpressionCalculator.evaluate("") == nil, "empty → nil")
    try expect(ExpressionCalculator.evaluate("2+") == nil, "trailing op → nil")
    try expect(ExpressionCalculator.evaluate("abc") == nil, "garbage → nil")
    try expect(ExpressionCalculator.evaluate("2/0") == nil, "div-by-zero → nil (non-finite)")
    try expect(ExpressionCalculator.evaluate("1/0") == nil, "non-finite guarded")

    // ── 5. DrivenDimensionResolver still resolves (regression) ─────────────
    try expect(
        DrivenDimensionResolver.resolve(expression: "stockWidth / 2", variables: v) == nil,
        "unknown var → nil"
    )
    let stock = vars([("stockWidth", "2440")])
    try expectClose(
        DrivenDimensionResolver.resolve(expression: "stockWidth / 2", variables: stock),
        1220, "driven resolver regression"
    )

    // ── 6. Plain-number passthrough ────────────────────────────────────────
    try expectClose(ExpressionCalculator.evaluate("42"), 42, "plain int")
    try expectClose(ExpressionCalculator.evaluate(" 12.5 "), 12.5, "whitespace-trimmed")

    print("ShopPilotVerify0209: PASS — arithmetic + precedence, π/pi, $-vars + longest-key, invalid→nil, DrivenDimensionResolver regression, plain numbers")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0209: FAIL — \(error)")
    exit(1)
}
