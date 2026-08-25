import Foundation

// MARK: - Alarm Decoder (SPK-2022g)

/// Plain-text decoding of GRBL 1.1 controller fault lines.
///
/// GRBL reports faults as terse wire tokens (`ALARM:3`, `error:9`). Raw tokens
/// stay verbatim in the console (Safety Req #6); this decoder turns them into
/// shop-floor copy for the status banner. Pure function — no state, no I/O.
///
/// Contract:
/// - Every GRBL 1.1 ALARM code (1–9) decodes to distinct plain text that
///   carries the original token (`"ALARM:1 — …"`).
/// - A common subset of `error:` codes decodes the same way.
/// - Anything unknown (`ALARM:99`, garbage, ordinary traffic) returns `nil` so
///   callers fall back to showing the raw line untouched.
public enum AlarmDecoder {

    /// GRBL 1.1 alarm codes → short plain text (without the leading token).
    /// Copy names what tripped and what to do about it.
    private static let alarmTexts: [Int: String] = [
        1: "hard limit triggered; check limit switches, then home after clearing",
        2: "soft limit triggered; move jogged past travel — jog back inside the envelope",
        3: "abort during cycle; machine reset mid-motion — re-home before running",
        4: "probe fail — probe did not contact within the travel distance; check wiring and gap",
        5: "probe fail — probe already engaged when the move started; retract the probe",
        6: "homing fail — reset during homing cycle; check switches, retry homing",
        7: "homing fail — no switch found during the homing cycle; check switch wiring",
        8: "homing fail — pull-off direction ambiguous; check the $27 pull-off setting",
        9: "homing fail — switch not found on approach; check orientation and $23 mask"
    ]

    /// Common GRBL 1.1 error codes → short plain text. The full table runs to
    /// 40+ codes; these are the ones a router operator actually hits. Unknown
    /// codes fall through to `nil` (raw line shown).
    private static let errorTexts: [Int: String] = [
        1: "expected a command letter — line was malformed",
        2: "bad number format — check the numeric value",
        3: "invalid statement — `$` system command not recognized",
        4: "negative value where one is not allowed",
        5: "homing cycle disabled ($22=0) — enable homing first",
        6: "minimum step pulse time below 3µs — check settings",
        7: "EEPROM read failed — reset and restore settings",
        8: "`$` command only valid while idle",
        9: "locked out — homing required first (safety door / alarm latched)"
    ]

    /// Decode one controller output line.
    ///
    /// Accepts bare tokens (`ALARM:1`, `error:9`) and embedded ones
    /// (`ALARM:3 [MSG:…]`, status lines carrying the fault). Case-insensitive.
    /// Returns e.g. `"ALARM:1 — hard limit triggered; …"` or `nil` for
    /// anything it does not recognize.
    public static func decode(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let code = code(in: trimmed, after: "ALARM:"), let text = alarmTexts[code] {
            return "ALARM:\(code) — \(text)"
        }
        if let code = code(in: trimmed, after: "ERROR:"), let text = errorTexts[code] {
            return "error:\(code) — \(text)"
        }
        return nil
    }

    /// First integer immediately following `token` (case-insensitive) anywhere
    /// in `line`. `nil` when the token is absent or no digits follow it.
    private static func code(in line: String, after token: String) -> Int? {
        guard let range = line.range(of: token, options: .caseInsensitive) else {
            return nil
        }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        guard let value = Int(digits) else { return nil }
        return value
    }
}
