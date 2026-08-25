import Foundation

/// SPK-2022c — skip-first-M6 send-time filter (pure, no I/O).
///
/// When the operator confirms "bit already loaded", the send path suppresses
/// EXACTLY the FIRST tool change (`M6` / `M06`) in the outgoing program plus
/// its immediate dwell/pause line if one directly follows (an `M0`, `M1`, or
/// `G4 P…` within the next 1–2 lines). All later M6s pass through untouched.
///
/// The filter is a pure function over the program lines: it never mutates the
/// document, never touches parameters, and with the toggle OFF returns its
/// input unchanged so toggling back restores the full program byte-for-byte.

public enum SendTimeM6Filter {

    /// Result of applying the filter.
    public struct Output: Equatable, Sendable {
        /// Lines to send (identical to the input when nothing was suppressed).
        public let lines: [String]
        /// How many lines were suppressed (0 when the filter is off or the
        /// program has no leading tool change).
        public let suppressedCount: Int
    }

    /// Apply the skip-first-M6 filter.
    ///
    /// - Parameters:
    ///   - lines: the full outgoing program, one line per element.
    ///   - skipEnabled: the operator's "bit already loaded" choice. `false`
    ///     returns the input untouched (suppressedCount 0).
    public static func apply(_ lines: [String], skipEnabled: Bool) -> Output {
        guard skipEnabled else { return Output(lines: lines, suppressedCount: 0) }

        guard let m6Index = lines.firstIndex(where: isToolChange) else {
            return Output(lines: lines, suppressedCount: 0)
        }

        // Suppress the first M6 itself, plus an immediate dwell/pause line if
        // one directly follows within the next 1–2 lines ("directly follows"
        // = within the two lines right after the M6).
        var dropSet = Set([m6Index])
        if let pauseIndex = lines.indices
            .dropFirst(m6Index + 1)
            .prefix(2)
            .first(where: { isPauseOrDwell(lines[$0]) }) {
            dropSet.insert(pauseIndex)
        }

        let filtered = lines.enumerated()
            .filter { !dropSet.contains($0.offset) }
            .map { $0.element }

        return Output(lines: filtered, suppressedCount: dropSet.count)
    }

    /// Convenience overload taking the whole program text; returns the
    /// filtered text plus the number of suppressed lines.
    public static func apply(_ text: String, skipEnabled: Bool)
        -> (text: String, suppressedCount: Int) {
        guard skipEnabled else { return (text, 0) }
        let hadTrailingNewline = text.hasSuffix("\n")
        let lines = text.components(separatedBy: "\n")
        // components(separatedBy:) yields a trailing "" for a trailing \n;
        // keep that element so round-trips stay byte-stable.
        let result = apply(lines, skipEnabled: true)
        var joined = result.lines.joined(separator: "\n")
        if hadTrailingNewline && !joined.hasSuffix("\n") { joined += "\n" }
        return (joined, result.suppressedCount)
    }

    // MARK: - Line classification

    /// True when the line is an active G-code tool-change command (`M6`/`M06`
    /// word). Comment-only lines (`(…)`, `;…`) and other M-codes never match.
    public static func isToolChange(_ line: String) -> Bool {
        guard !isComment(line) else { return false }
        // M6 / M06 — leading zeros tolerated, never M60/M16.
        return matchesWord(line, pattern: #"(?<![A-Z0-9])M0*6(?![0-9])"#)
    }

    /// True when the line is a program pause/dwell: `M0`/`M00` (stop),
    /// `M1`/`M01`/`M001` (optional stop), or a `G4`/`G04` dwell.
    public static func isPauseOrDwell(_ line: String) -> Bool {
        guard !isComment(line) else { return false }
        return matchesWord(line, pattern: #"(?<![A-Z0-9])M0*[01](?![0-9])"#)
            || matchesWord(line, pattern: #"(?<![A-Z0-9])G0*4(?![0-9])"#)
    }

    /// Strip inline comments so `(M6 hint)` or `M3 ; not M6` can't fool the
    /// classifier.
    private static func codePortion(_ line: String) -> String {
        var s = line
        if let open = s.firstIndex(of: "("), let close = s.firstIndex(of: ")"), open < close {
            s.removeSubrange(open...close)
        } else if let open = s.firstIndex(of: "(") {
            s = String(s[..<open])
        }
        if let semi = s.firstIndex(of: ";") {
            s = String(s[..<semi])
        }
        return s
    }

    private static func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("(") || trimmed.hasPrefix(";")
    }

    private static func matchesWord(_ line: String, pattern: String) -> Bool {
        let code = codePortion(line).uppercased()
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(code.startIndex..., in: code)
        return regex.firstMatch(in: code, options: [], range: range) != nil
    }
}
