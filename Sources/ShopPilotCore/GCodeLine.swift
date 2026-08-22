import Foundation

/// GRBL command-line shaping helpers (SPK-1401c).
///
/// GRBL only executes a command once its line terminator (`\n`) arrives — a
/// bare command without the newline sits in the receive buffer and never
/// runs. Every line sent from the jog/console path must therefore carry a
/// trailing newline, and jogging must restore absolute mode (G90) after the
/// relative (G91) block so the machine does not stay in relative mode.
public enum GCodeLine {

    /// The command with exactly one trailing `\n`: appends `\n` when the
    /// command does not already end with one, otherwise returns it unchanged
    /// (never double-terminates). Handles `\r\n`-terminated input too, since
    /// it already ends with `\n`.
    public static func sending(_ command: String) -> String {
        // Compare the last Unicode SCALAR (U+000A), not String.hasSuffix:
        // hasSuffix is grapheme-cluster based, and CRLF is a single cluster,
        // so "G0 X0\r\n".hasSuffix("\n") is false — a CRLF-terminated line
        // would otherwise be double-terminated.
        command.unicodeScalars.last?.value == 0x0A ? command : command + "\n"
    }
}

/// Builds the GRBL line sequence for a jog (SPK-1401c).
public enum JogCommandFormatter {

    /// GRBL modal-state restore: after jogging in relative mode (G91), the
    /// machine must be returned to absolute positioning (G90) so the next
    /// absolute-coordinate command means what it says.
    public static let restoreLine = "G90"

    /// The G91 relative-rapid jog block followed by the G90 restore:
    /// `["G91 G0 <axis><signed distance>", "G90"]`. `distanceMm` carries the
    /// sign (negative = reverse direction); formatting matches the prior jog
    /// command shape (`%.3f`).
    public static func lines(axis: String, distanceMm: Double) -> [String] {
        ["G91 G0 \(axis)\(String(format: "%.3f", distanceMm))", restoreLine]
    }
}

/// SPK-1900b — click-to-jog: one absolute rapid to a canvas point. The jog
/// discipline restores G90 after every relative jog, so an absolute G0 is
/// the correct modal state here; no M3, no Z motion, no auto-run.
public enum JogToFormatter {
    public static func line(xMm: Double, yMm: Double) -> String {
        "G0 X\(String(format: "%.3f", xMm)) Y\(String(format: "%.3f", yMm))"
    }
}

/// SPK-1900b — frame the job bounds: trace the sheet rectangle in AIR at a
/// safe clearance height so the operator can visually confirm stock position
/// and job bounds before any cut. Pure G0 motion — never a spindle command,
/// never a cut depth.
public enum FrameJobFormatter {
    public static func lines(widthMm: Double, heightMm: Double, clearanceZMm: Double = 5.0) -> [String] {
        let f = { (v: Double) in String(format: "%.3f", v) }
        return [
            "G0 Z\(f(clearanceZMm))",       // lift to clearance FIRST
            "G0 X0.000 Y0.000",              // to the job origin corner
            "G0 X\(f(widthMm)) Y0.000",      // perimeter at clearance height
            "G0 X\(f(widthMm)) Y\(f(heightMm))",
            "G0 X0.000 Y\(f(heightMm))",
            "G0 X0.000 Y0.000",              // return to origin
        ]
    }
}
