import Foundation

// MARK: - Expression Parser

/// Minimal numeric expression evaluator for form fields.
/// Supports +, -, *, /, parentheses, decimal numbers, and named variables.
public struct ExpressionParser {
    
    /// Evaluate a numeric expression string to a Double result.
    public static func evaluate(_ expression: String, variables: [String: Double] = [:]) -> Double? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        var processed = trimmed
        
        // Replace named variables with their values (longest first to avoid partial replacements)
        for (name, value) in variables.sorted(by: { $0.key.count > $1.key.count }) {
            processed = processed.replacingOccurrences(of: name, with: String(value))
        }
        
        // Replace common constants
        processed = processed.replacingOccurrences(of: "π", with: String(Double.pi))
        processed = processed.replacingOccurrences(of: "pi", with: String(Double.pi))
        
        let evaluator = ExpressionEvaluator(string: processed)
        return try? evaluator.evaluate()
    }
}

// MARK: - Expression Evaluator (class-based to allow mutating state)

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
    
    // Parse expression (handles + and -)
    @discardableResult
    private func parseExpression() throws -> Double {
        var result = try parseTerm()
        
        while let ch = peek(), ch == "+" || ch == "-" {
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
    
    // Parse term (handles * and /)
    @discardableResult
    private func parseTerm() throws -> Double {
        var result = try parseFactor()
        
        while let ch = peek(), ch == "*" || ch == "/" {
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
    
    // Parse factor (unary ops, numbers, parentheses)
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
            while pos < chars.count, let c = String(chars[pos]).first, (c.isNumber || c == ".") && numStr.filter({ $0 == "." }).count < 2 {
                numStr.append(c)
                pos += 1
            }
            
            guard let value = Double(numStr) else {
                throw ExpressionError.invalidNumber(numStr)
            }
            return value
        }
        
        // Skip unknown characters (e.g., leftover variable names)
        advance()
        return try parseFactor()
    }
}

// MARK: - Expression Error

public enum ExpressionError: LocalizedError {
    case invalidNumber(String)
    case divisionByZero
    case missingOperand
    case missingClosingParen
    case unexpectedCharacter(Character)
    
    public var errorDescription: String? {
        switch self {
        case .invalidNumber(let num): return "Invalid number: \(num)"
        case .divisionByZero: return "Division by zero"
        case .missingOperand: return "Missing operand"
        case .missingClosingParen: return "Missing closing parenthesis"
        case .unexpectedCharacter(let ch): return "Unexpected character: '\(ch)'"
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ExpressionParser_Previews: PreviewProvider {
    static var previews: some View {
        Text("Expression parser is a non-visual component")
    }
}
#endif
