/// Validation utilities for ShopPilot.
///
/// Provides static helper methods for common string/double validation
/// used across the app (user input, config parsing, etc.).
import Foundation

/// Possible validation errors returned by `validate*` methods.
public enum ValidationError: Error, CustomStringConvertible {
    case invalidEmail
    case invalidURL
    case invalidUUID
    case invalidDimension
    case invalidName

    public var description: String {
        switch self {
        case .invalidEmail: return "Invalid email address."
        case .invalidURL: return "Invalid URL."
        case .invalidUUID: return "Invalid UUID format."
        case .invalidDimension: return "Value is out of the allowed range."
        case .invalidName: return "Name is invalid."
        }
    }
}

/// A collection of static validation helpers.
public struct Validation {

    // MARK: - Email

    /// Returns `true` if `email` looks like a valid email address.
    ///
    /// Basic pattern: `local@domain.tld` where local and domain contain
    /// only allowed characters and the domain has at least one dot.
    public static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: email)
    }

    // MARK: - URL

    /// Returns `true` if `url` can be parsed as a valid URL.
    public static func isValidURL(_ url: String) -> Bool {
        guard !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    // MARK: - UUID

    /// Returns `true` if `uuid` is a valid 36-character UUID string.
    public static func isValidUUID(_ uuid: String) -> Bool {
        guard uuid.count == 36 else { return false }
        let uuidRegex = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidRegex)
        return predicate.evaluate(with: uuid)
    }

    // MARK: - Dimension

    /// Returns `true` if `value` is within the inclusive range `[min, max]`.
    public static func isValidDimension(_ value: Double, min: Double, max: Double) -> Bool {
        value >= min && value <= max
    }

    // MARK: - Tool Name

    /// Returns `true` if `name` is non-empty and contains only
    /// alphanumeric characters, spaces, hyphens, or underscores.
    public static func isValidToolName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let nameRegex = #"^[A-Za-z0-9 \-_]+$"#
        let predicate = NSPredicate(format: "SELF MATCHES %@", nameRegex)
        return predicate.evaluate(with: trimmed)
    }

    // MARK: - Material Name

    /// Returns `true` if `name` is non-empty after trimming whitespace.
    public static func isValidMaterialName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Math Expression

    /// Returns `true` if `expr` contains only digits, basic math
    /// operators (`+ - * /`), parentheses, decimal points, and spaces.
    ///
    /// This does **not** evaluate the expression — it only checks
    /// that it contains no unexpected characters.
    public static func isValidExpression(_ expr: String) -> Bool {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789+-*/(). ")
        return trimmed.rangeOfCharacter(from: allowed.inverted) == nil
    }
}
