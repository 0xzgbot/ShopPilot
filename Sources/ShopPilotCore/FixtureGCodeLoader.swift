import Foundation
import ShopPilotCore

// MARK: - Fixture G-code loading (SPK-1403d)

/// The session surface the fixture loader needs. `AppSession` conforms with
/// its real stored properties; a CLI fake can drive loading without the app
/// target.
@preconcurrency
public protocol FixtureLoadingSession: AnyObject {
    /// The session G-code buffer — load is skipped when it is non-empty
    /// (a real job is already in hand).
    var gcodeLines: [String] { get set }
    /// Publish the one-line summary (also becomes the status line).
    func setLastToolpathSummary(_ text: String)
}

/// Owns the "load fixture G-code if the buffer is empty" orchestration
/// (SPK-1403d slice 4 of the AppSession split): when the session buffer is
/// empty, load `fixtures/gcode/calibration_square.nc` from the candidate
/// locations; when none exist, fall back to the built-in air-cut square.
/// Extracted verbatim from `AppSession.loadFixtureGCodeIfNeeded()` — no
/// behavior change. The candidate locations default to the app's standard
/// fixture search (CWD + Bundle.main) and are injectable so the CLT can
/// drive both the file branch and the fallback branch.
public enum FixtureGCodeLoader {

    /// Standard fixture locations (CWD then app bundle) — the same two the
    /// session searched.
    public static var defaultCandidateURLs: [URL] {
        [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("fixtures/gcode/calibration_square.nc"),
            Bundle.main.bundleURL
                .appendingPathComponent("fixtures/gcode/calibration_square.nc"),
        ]
    }

    /// The built-in air-cut square used when no fixture file exists.
    public static let builtInAirCutSquare: [String] = [
        "G21", "G90", "G0 Z5", "G0 X0 Y0",
        "G1 Z-1 F200", "G1 X20 F800", "G1 Y20", "G1 X0", "G1 Y0",
        "G0 Z5", "M2",
    ]

    /// Fill the session buffer with fixture G-code when it is empty.
    /// Returns true when something was loaded (file or built-in), false when
    /// the buffer already had lines (no-op).
    @discardableResult
    public static func loadIfNeeded(into session: FixtureLoadingSession,
                                    candidateURLs: [URL] = defaultCandidateURLs) -> Bool {
        guard session.gcodeLines.isEmpty else { return false }

        for url in candidateURLs where FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                session.gcodeLines = text
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                session.setLastToolpathSummary(
                    "Loaded fixture \(url.lastPathComponent) (\(session.gcodeLines.count) lines)"
                )
                return true
            }
        }

        session.gcodeLines = builtInAirCutSquare
        session.setLastToolpathSummary(
            "Built-in air-cut square (\(session.gcodeLines.count) lines)"
        )
        return true
    }
}
