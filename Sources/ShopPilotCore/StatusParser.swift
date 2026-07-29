import Foundation

// MARK: - ParsedMachineStatus

/// Structured result of parsing a GRBL-style status report.
public struct ParsedMachineStatus {
    /// Current machine state (e.g. "Idle", "Run", "Hold", "Alarm").
    public var state: String = "unknown"
    /// Machine coordinates (MPos).
    public var mPosX: Double = 0.0
    public var mPosY: Double = 0.0
    public var mPosZ: Double = 0.0
    /// Work coordinates (WPos / G54).
    public var wPosX: Double = 0.0
    public var wPosY: Double = 0.0
    public var wPosZ: Double = 0.0
}

// MARK: - StatusParser

/// Parses GRBL v1.x status reports from raw data.
///
/// Expected format: `<State|MPos:x,y,z|WPos:x,y,z|FS:r,s>`
public enum StatusParser {

    /// Parse a `Data` blob into structured coordinates and state.
    /// Returns nil if the data does not look like a GRBL status report.
    public static func parse(_ data: Data) -> ParsedMachineStatus? {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with '<' and end with '>'
        guard text.hasPrefix("<"), text.hasSuffix(">") else { return nil }

        let inner = String(text.dropFirst().dropLast())
        let components = inner.components(separatedBy: "|")

        var status = ParsedMachineStatus()

        for component in components {
            if let state = parseState(component) {
                status.state = state
            } else if let coords = try? parseCoordinates(component, prefix: "MPos:") {
                status.mPosX = coords.x
                status.mPosY = coords.y
                status.mPosZ = coords.z
            } else if let coords = try? parseCoordinates(component, prefix: "WPos:") {
                status.wPosX = coords.x
                status.wPosY = coords.y
                status.wPosZ = coords.z
            }
        }

        return status
    }

    // MARK: - Private helpers

    private static func parseState(_ component: String) -> String? {
        let validStates = ["Idle", "Run", "Hold", "Home", "Alarm", "Check", "Door"]
        guard validStates.contains(component) else { return nil }
        return component
    }

    private enum CoordinateParseError: Error { case invalidFormat }

    private static func parseCoordinates(_ component: String, prefix: String) throws -> (x: Double, y: Double, z: Double) {
        guard component.hasPrefix(prefix) else { throw CoordinateParseError.invalidFormat }
        let values = String(component.dropFirst(prefix.count))
        let parts = values.components(separatedBy: ",")

        guard parts.count >= 3 else { throw CoordinateParseError.invalidFormat }

        func toDouble(_ s: String) -> Double? {
            // Strip trailing units like "mm" or "in"
            let cleaned = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "[a-zA-Z]", with: "", options: .regularExpression)
            return Double(cleaned)
        }

        guard let x = toDouble(parts[0]),
              let y = toDouble(parts[1]),
              let z = toDouble(parts[2]) else {
            throw CoordinateParseError.invalidFormat
        }

        return (x, y, z)
    }
}
