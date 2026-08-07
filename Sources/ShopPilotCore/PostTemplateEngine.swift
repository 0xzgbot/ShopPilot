import Foundation

// MARK: - Post template engine (SPK-1134)

/// Expands `PostTemplate` recipes over raw move lines.
///
/// Template sections:
///   - Lines BEFORE the `(--- moves ---)` marker are the header (emitted once).
///   - Lines between `(--- moves ---)` and `(--- end ---)` are MOVE templates
///     (emitted once per G/M line).
///   - Lines after `(--- end ---)` are the footer (emitted once).
///
/// Per-line expansion:
///   - `[G]`  → the raw line's G-code (command + words). In rotary-wrap
///              templates the Y word is converted to A degrees here. When a
///              move template line contains per-word tokens, `[G]` expands to
///              the command word only (so the line can be rebuilt from parts).
///   - `[W|M|O|F]` → word W's value: M=`A` (absolute, as written), `C`
///              (current — emit only when changed since the last move), `I`
///              (delta since the previous move); printed as O (a letter, or
///              `-` for value-only) with F decimals (`1.3` = 3 dp). Words
///              absent from the move emit nothing.
///   - `[D|A|-|F]` → the template's wrap diameter (rotary posts).
///   - `[N|A|N|F]` → line number (starts at 10, steps 10 per emitted line).
///   - Any other text is copied verbatim.
///
/// Rotary wrap (Y2A): when `template.rotaryWrap` is set, every Y coordinate
/// converts to A-axis degrees about X: `a = y / (π · diameter) · 360`.
public struct PostTemplateEngine {

    public struct EmitResult: Codable, Sendable {
        public let lines: [String]
        public let moveCount: Int
        public init(lines: [String], moveCount: Int) {
            self.lines = lines
            self.moveCount = moveCount
        }
    }

    private static let movesMarker = "(--- moves ---)"
    private static let endMarker = "(--- end ---)"

    // MARK: - Entry point

    public static func emit(gcodeLines: [String], template: PostTemplate) -> EmitResult {
        let recipeLines = template.text.components(separatedBy: "\n")
        var header: [String] = []
        var moveTemplates: [String] = []
        var footer: [String] = []
        var section = 0 // 0 = header, 1 = moves, 2 = footer
        for line in recipeLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == movesMarker { section = 1; continue }
            if trimmed == endMarker { section = 2; continue }
            switch section {
            case 0: header.append(line)
            case 1: moveTemplates.append(line)
            default: footer.append(line)
            }
        }

        var out: [String] = []
        var lineNumber = 10
        var lastWords: [String: Double] = [:]
        var moveCount = 0

        func emitRecipeLine(_ recipe: String, move: ParsedMove?) {
            var expanded = recipe
            // Line number token (any decimals specifier accepted).
            if expanded.contains("[N|A|N|") {
                expanded = expanded.replacingOccurrences(
                    of: #"\[N\|A\|N\|[0-9]\.[0-9]\]"#,
                    with: "N\(lineNumber)",
                    options: .regularExpression
                )
                lineNumber += 10
            }
            if let move {
                expanded = expandMove(expanded, move: move, template: template, words: &lastWords)
            } else {
                // Header/footer: expand diameter + current-mode tokens against
                // the last-emitted values (e.g. a safe-Z retract).
                expanded = expandNonMove(expanded, template: template, words: &lastWords)
            }
            out.append(expanded)
        }

        for line in header { emitRecipeLine(line, move: nil) }

        for raw in gcodeLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || trimmed.hasPrefix("(")
                || trimmed == "%"
                || trimmed.hasPrefix("O=") {
                out.append(trimmed)
                continue
            }
            guard let parsed = parseMove(trimmed) else {
                out.append(trimmed)
                continue
            }
            moveCount += 1
            for mt in moveTemplates {
                emitRecipeLine(mt, move: parsed)
            }
        }

        for line in footer { emitRecipeLine(line, move: nil) }

        let cleaned = out.map { line -> String in
            line.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return EmitResult(lines: cleaned, moveCount: moveCount)
    }

    // MARK: - Move model

    struct ParsedMove {
        let command: String          // e.g. "G0", "G1", "M3", "M30"
        let words: [String: Double]  // X/Y/Z/A/B/C/F/S/T → value
    }

    static func parseMove(_ line: String) -> ParsedMove? {
        let pattern = #"([A-Za-z])([+-]?\d*\.?\d+)"#
        var command: String? = nil
        var words: [String: Double] = [:]
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = line as NSString
        regex?.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let letter = ns.substring(with: m.range(at: 1)).uppercased()
            let numStr = ns.substring(with: m.range(at: 2))
            guard let num = Double(numStr) else { return }
            if letter == "G" || letter == "M" {
                if command == nil { command = "\(letter)\(Int(num))" }
            } else {
                words[letter] = num
            }
        }
        guard let command else { return nil }
        return ParsedMove(command: command, words: words)
    }

    // MARK: - Token expansion

    /// The full processed line for a move — command + words, with Y→A
    /// conversion applied when the template wraps. Coordinates keep 3
    /// decimals; feeds/speeds/tools are integers (how the engines emit them).
    static func fullLine(_ move: ParsedMove, template: PostTemplate) -> String {
        var parts = [move.command]
        // Preserve the original word order: sort deterministically (X Y Z
        // A B C F S T), matching how engines emit.
        let order = ["X", "Y", "Z", "A", "B", "C", "F", "S", "T"]
        for word in order {
            guard let v = move.words[word] else { continue }
            let printed = wrappedValue(v, word: word, template: template)
            // Rotary wrap: the Y word is emitted as the A axis.
            let emittedWord = (template.rotaryWrap && word == "Y") ? "A" : word
            let decimals = (word == "F" || word == "S" || word == "T") ? 0 : 3
            parts.append("\(emittedWord)\(String(format: "%.\(decimals)f", printed))")
        }
        return parts.joined(separator: " ")
    }

    static func wrappedValue(_ v: Double, word: String, template: PostTemplate) -> Double {
        if template.rotaryWrap && word == "Y" {
            return v / (Double.pi * template.wrapDiameterMm) * 360.0
        }
        return v
    }

    static func expandMove(_ recipe: String, move: ParsedMove, template: PostTemplate, words: inout [String: Double]) -> String {
        // Does the line use per-word tokens?
        let tokenPattern = #"\[([A-Za-z])\|([ACI])\|(-|[A-Za-z])\|([0-9]\.[0-9])\]"#
        let hasTokens = recipe.range(of: tokenPattern, options: .regularExpression) != nil

        // Substitute [G] — full line when no per-word tokens, command only
        // when the line is being rebuilt from parts.
        let gReplacement = hasTokens ? move.command : fullLine(move, template: template)
        var expanded = recipe.replacingOccurrences(of: "[G]", with: gReplacement)
        if !hasTokens {
            // Track emitted words so footer [W|C|W|F] tokens resolve.
            for (word, value) in move.words {
                words[word] = value
            }
            return expanded
        }

        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return expanded }
        let ns = expanded as NSString
        var result = ""
        var lastRange = NSRange(location: 0, length: 0)

        regex.enumerateMatches(in: expanded, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            result += ns.substring(with: NSRange(
                location: lastRange.location + lastRange.length,
                length: m.range.location - (lastRange.location + lastRange.length)
            ))
            let word = ns.substring(with: m.range(at: 1)).uppercased()
            let mode = ns.substring(with: m.range(at: 2))
            let outLetter = ns.substring(with: m.range(at: 3))
            let format = ns.substring(with: m.range(at: 4))
            if let replacement = expandToken(word: word, mode: mode, outLetter: outLetter, format: format,
                                             move: move, template: template, words: &words) {
                result += replacement
            }
            lastRange = m.range
        }
        result += ns.substring(from: lastRange.location + lastRange.length)
        return result
    }

    static func expandToken(word: String, mode: String, outLetter: String, format: String,
                            move: ParsedMove, template: PostTemplate, words: inout [String: Double]) -> String? {
        var value: Double?
        switch word {
        case "G":
            return move.command
        case "D":
            value = template.wrapDiameterMm
        default:
            value = move.words[word]
        }
        guard let raw = value else { return nil }

        let displayValue: Double
        switch mode {
        case "C":
            if let last = words[word], abs(last - raw) < 1e-9 {
                return nil
            }
            displayValue = raw
        case "I":
            displayValue = raw - (words[word] ?? 0)
        default:
            displayValue = raw
        }
        words[word] = raw

        let printed = wrappedValue(displayValue, word: word, template: template)
        let decimals = Int(format.split(separator: ".").last ?? "3") ?? 3
        let formatted = String(format: "%.\(decimals)f", printed)
        if outLetter == "-" {
            return formatted
        }
        return "\(outLetter)\(formatted)"
    }

    /// Expand tokens on a header/footer line (no move): diameter `[D]` and
    /// current-mode `[C]` tokens resolve against the last-emitted values.
    static func expandNonMove(_ recipe: String, template: PostTemplate, words: inout [String: Double]) -> String {
        let pattern = #"\[([A-Za-z])\|([ACI])\|(-|[A-Za-z])\|([0-9]\.[0-9])\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return recipe }
        let ns = recipe as NSString
        var result = ""
        var lastRange = NSRange(location: 0, length: 0)

        regex.enumerateMatches(in: recipe, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            result += ns.substring(with: NSRange(
                location: lastRange.location + lastRange.length,
                length: m.range.location - (lastRange.location + lastRange.length)
            ))
            let word = ns.substring(with: m.range(at: 1)).uppercased()
            let mode = ns.substring(with: m.range(at: 2))
            let outLetter = ns.substring(with: m.range(at: 3))
            let format = ns.substring(with: m.range(at: 4))

            if word == "D" {
                let decimals = Int(format.split(separator: ".").last ?? "1") ?? 1
                result += String(format: "%.\(decimals)f", template.wrapDiameterMm)
            } else if mode == "C", let last = words[word] {
                let decimals = Int(format.split(separator: ".").last ?? "3") ?? 3
                let printed = wrappedValue(last, word: word, template: template)
                let formatted = String(format: "%.\(decimals)f", printed)
                result += outLetter == "-" ? formatted : "\(outLetter)\(formatted)"
            }
            lastRange = m.range
        }
        result += ns.substring(from: lastRange.location + lastRange.length)
        return result
    }
}
