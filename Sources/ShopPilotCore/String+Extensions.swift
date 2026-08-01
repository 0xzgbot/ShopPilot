import Foundation

// MARK: - String+Extensions

extension String {

    /// Returns true if the string represents a valid number (Int or Double).
    var isNumeric: Bool {
        return self.toDouble != nil
    }

    /// Converts the string to a Double, or nil if it cannot be parsed.
    func toDouble() -> Double? {
        return Double(self)
    }

    /// Returns a new string with leading and trailing whitespace removed.
    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if the string is not empty and not whitespace-only.
    var isNotEmpty: Bool {
        return !self.trimmed().isEmpty
    }

    /// Returns a new string with the first character capitalized and the rest unchanged.
    var capitalizedFirst: String {
        guard let firstCharacter = self.first else { return self }
        return firstCharacter.uppercased() + self.dropFirst()
    }

    /// Truncates the string to maxLength characters, appending suffix if truncated.
    func truncate(to maxLength: Int, suffix: String = "...") -> String {
        guard self.count > maxLength else { return self }
        let truncated = self.prefix(maxLength)
        // Ensure the result plus suffix doesn't exceed maxLength
        let available = maxLength - suffix.count
        guard available > 0 else { return suffix }
        return String(truncated.prefix(available)) + suffix
    }

    /// Removes characters that are invalid in filenames on macOS.
    func sanitizeFilename() -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\0*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)
        let components = self.components(separatedBy: invalidCharacters)
        return components.joined(separator: "_")
    }
}
