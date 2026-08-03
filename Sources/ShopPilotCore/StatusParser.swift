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
    /// Feed rate and spindle speed (from `FS:` field). `nil` when absent.
    public var fs: (feed: Double, spindle: Double)?
    /// Planner block buffer remaining (from `Bf:` field). `nil` when absent.
    public var buffer: Int?
    /// Pin states (from `Pn:` field). `nil` when absent.
    public var pins: PinStatus?
}

// MARK: - PinStatus

/// GRBL pin status from the `Pn:` field (GRBL 1.0c+).
///
/// Format: `Pn:xxx|x|xxx` where:
/// - First group: homing/limit switches (Z, Y, X) as 3-digit binary string
/// - Second: probe pin state (single digit, 0 or 1)
/// - Third: control pins (cycle start, feed hold, reset, safety door) as 4-digit binary
public struct PinStatus: Sendable {
    /// Limit switch states: [zTripped, yTripped, xTripped]. 0 = not tripped, 1 = tripped.
    public var limits: [Int]
    /// Probe pin state: 0 = not tripped, 1 = tripped.
    public var probe: Int
    /// Control pin states: [cycleStart, feedHold, reset, safetyDoor]. 0 or 1.
    public var controls: [Int]

    public init(limits: [Int], probe: Int, controls: [Int]) {
        self.limits = limits
        self.probe = probe
        self.controls = controls
    }
}

// MARK: - StatusParser

/// Parses GRBL v1.x status reports from raw data.
///
/// Expected format: `<State|MPos:x,y,z|WPos:x,y,z|FS:r,s|Bf:n|Pn:xxx|x|xxx>`
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

        // The Pn field itself contains pipe separators (`Pn:000|0|0000`), so
        // the component split above fragments it. Walk with an index and, on a
        // `Pn:` prefix, re-join following bare-value segments (no `:`) into one
        // group before handing it to parsePins. A real GRBL `Pn:P` token stays
        // single-segment and simply yields nil pins.
        var index = 0
        while index < components.count {
            let component = components[index]
            if component.hasPrefix("Pn:") {
                var group = component
                var cursor = index + 1
                while cursor < components.count,
                      !components[cursor].contains(":"),
                      group.components(separatedBy: "|").count < 3 {
                    group += "|" + components[cursor]
                    cursor += 1
                }
                status.pins = parsePins(group)
                index = cursor
                continue
            }
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
            } else if let fs = parseFS(component) {
                status.fs = fs
            } else if let buf = parseBuffer(component) {
                status.buffer = buf
            }
            index += 1
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

    /// Parse `FS:r,s` feed rate and spindle speed.
    private static func parseFS(_ component: String) -> (feed: Double, spindle: Double)? {
        guard component.hasPrefix("FS:") else { return nil }
        let values = String(component.dropFirst(3))
        let parts = values.components(separatedBy: ",")

        func toDouble(_ s: String) -> Double? {
            Double(s.trimmingCharacters(in: .whitespaces))
        }

        guard let feed = toDouble(parts[0]) else { return nil }
        let spindle = parts.count > 1 ? toDouble(parts[1]) ?? 0.0 : 0.0
        return (feed, spindle)
    }

    /// Parse `Bf:n` planner buffer remaining.
    private static func parseBuffer(_ component: String) -> Int? {
        guard component.hasPrefix("Bf:") else { return nil }
        let value = String(component.dropFirst(3))
        return Int(value.trimmingCharacters(in: .whitespaces))
    }

    /// Parse `Pn:xxx|x|xxx` pin states.
    private static func parsePins(_ component: String) -> PinStatus? {
        guard component.hasPrefix("Pn:") else { return nil }
        let values = String(component.dropFirst(3))
        let parts = values.components(separatedBy: "|")

        guard parts.count >= 3 else { return nil }

        func parseBinaryGroup(_ s: String) -> [Int] {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return trimmed.map { ch in
                if ch == "0" { return 0 }
                if ch == "1" { return 1 }
                return 0
            }
        }

        let limits = parseBinaryGroup(parts[0])
        let probeStr = parts[1].trimmingCharacters(in: .whitespaces)
        let probe: Int = probeStr == "1" ? 1 : 0
        let controls = parseBinaryGroup(parts[2])

        return PinStatus(limits: limits, probe: probe, controls: controls)
    }
}
