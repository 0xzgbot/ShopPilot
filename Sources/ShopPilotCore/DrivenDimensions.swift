import Foundation

// MARK: - Driven Dimension

/// A driven (computed) dimension whose value is derived from an expression
/// referencing document variables.
public struct DrivenDimension: Identifiable, Codable, Hashable {
    public let id: UUID
    public var key: String          // dimension name (e.g. "width", "height")
    public var expression: String   // expression string (e.g. "stockWidth / 2")
    public var category: String

    /// Default category used when none is specified.
    public static let defaultCategory = "Dimensions"

    public init(
        id: UUID = UUID(),
        key: String,
        expression: String,
        category: String = DrivenDimension.defaultCategory
    ) {
        self.id = id
        self.key = key
        self.expression = expression
        self.category = category
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable

    public static func == (lhs: DrivenDimension, rhs: DrivenDimension) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Driven Dimension Resolver

/// Evaluates driven dimension expressions by substituting document variable
/// values and computing the result.
///
/// This is a self-contained evaluator so ShopPilotCore does not need to
/// import ShopPilotGeometry (which houses ExpressionParser).
public final class DrivenDimensionResolver {

    /// Resolve an expression string against a set of document variables.
    ///
    /// - Parameters:
    ///   - expression: A numeric expression, e.g. `"stockWidth / 2"` or `"materialThickness * 2 + 5"`.
    ///   - variables:  Document variables whose `key`/`value` pairs are substituted.
    ///                 String values are parsed as `Double`; non-numeric values are ignored.
    /// - Returns: The evaluated `Double`, or `nil` if resolution fails.
    public static func resolve(
        expression: String,
        variables: [DocumentVariable]
    ) -> Double? {
        ExpressionCalculator.evaluate(expression, variables: variables)
    }
}

// MARK: - Public expression calculator (SPK-0209)

/// Public numeric-expression evaluator backing the calculation edit boxes
/// (SPK-0209). Supports + − × ÷, parentheses, decimal numbers, named
/// variables (`$width` / bare `width`), and the π/pi constant. Any expression
/// that does not parse to a finite number returns nil (the field keeps its
/// typed text and the UI reports the error).
public enum ExpressionCalculator {

    /// Evaluate `expression` against an optional variable set.
    /// - Returns: the numeric result, or nil when the expression is empty,
    ///   unparsable, or non-finite.
    public static func evaluate(
        _ expression: String,
        variables: [DocumentVariable] = []
    ) -> Double? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var varMap: [String: Double] = [:]
        for v in variables {
            if let num = Double(v.value) {
                varMap[v.key] = num
            }
        }
        // Longest keys first so `$width` is substituted before `width`.
        let sorted = varMap.sorted { $0.key.count > $1.key.count }

        var processed = trimmed
        // Strip a leading `$` on bare variable names, then substitute.
        for (name, value) in sorted {
            processed = processed.replacingOccurrences(of: "$\(name)", with: String(value))
            processed = processed.replacingOccurrences(of: name, with: String(value))
        }
        processed = processed.replacingOccurrences(of: "π", with: String(Double.pi))
        processed = processed.replacingOccurrences(of: "pi", with: String(Double.pi))

        // SPK-0209 hardening: the shared evaluator SILENTLY SKIPS unknown
        // characters (so "stockWidth / 2" would parse as "2"), which is wrong
        // for calc fields — an unresolved variable must error, not quietly
        // become a different number. Reject any leftover letters.
        let letters = processed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.isEmpty else { return nil }

        let evaluator = ExpressionEvaluator(string: processed)
        guard let result = try? evaluator.evaluate(), result.isFinite else { return nil }
        return result
    }
}

// MARK: - Internal Expression Evaluator (mirrors ExpressionParser logic)

/// Recursive-descent numeric expression evaluator.
/// Self-contained copy of the core evaluator from ShopPilotGeometry so that
/// ShopPilotCore can evaluate expressions without importing GeometryKit.
private final class ExpressionEvaluator {

    private let chars: [Character]
    private var pos: Int = 0

    init(string: String) {
        self.chars = Array(string)
    }

    func evaluate() throws -> Double {
        skipWhitespace()
        let result = try parseExpression()
        skipWhitespace()
        guard pos >= chars.count else {
            throw ExpressionError.unexpectedCharacter(chars[pos])
        }
        return result
    }

    private func peek() -> Character? {
        pos < chars.count ? chars[pos] : nil
    }

    private func advance() -> Character? {
        guard pos < chars.count else { return nil }
        let ch = chars[pos]
        pos += 1
        return ch
    }

    private func skipWhitespace() {
        while pos < chars.count, chars[pos].isWhitespace {
            pos += 1
        }
    }

    // MARK: Expression ( + and - )

    @discardableResult
    private func parseExpression() throws -> Double {
        var result = try parseTerm()

        while true {
            skipWhitespace()
            guard let ch = peek(), ch == "+" || ch == "-" else { break }
            advance()
            skipWhitespace()
            let right = try parseTerm()
            if ch == "+" {
                result += right
            } else {
                result -= right
            }
        }

        return result
    }

    // MARK: Term ( * and / )

    @discardableResult
    private func parseTerm() throws -> Double {
        var result = try parseFactor()

        while true {
            skipWhitespace()
            guard let ch = peek(), ch == "*" || ch == "/" else { break }
            advance()
            skipWhitespace()
            let right = try parseFactor()
            if ch == "*" {
                result *= right
            } else {
                guard right != 0 else { throw ExpressionError.divisionByZero }
                result /= right
            }
        }

        return result
    }

    // MARK: Factor (unary ops, numbers, parentheses)

    @discardableResult
    private func parseFactor() throws -> Double {
        skipWhitespace()
        guard let ch = peek() else { throw ExpressionError.missingOperand }

        if ch == "-" {
            advance()
            return -(try parseFactor())
        }
        if ch == "+" {
            advance()
            return try parseFactor()
        }
        if ch == "(" {
            advance() // consume '('
            let result = try parseExpression()
            skipWhitespace()
            guard peek() == ")" else { throw ExpressionError.missingClosingParen }
            advance() // consume ')'
            return result
        }

        // Number literal
        if ch.isNumber || ch == "." {
            var numStr = ""
            while pos < chars.count,
                  let c = String(chars[pos]).first,
                  (c.isNumber || c == ".") && numStr.filter({ $0 == "." }).count < 2
            {
                numStr.append(c)
                pos += 1
            }

            guard let value = Double(numStr) else {
                throw ExpressionError.invalidNumber(numStr)
            }
            return value
        }

        // Skip unknown characters (e.g. leftover variable names)
        advance()
        return try parseFactor()
    }
}

// MARK: - Expression Error

enum ExpressionError: Error {
    case invalidNumber(String)
    case divisionByZero
    case missingOperand
    case missingClosingParen
    case unexpectedCharacter(Character)
}
