import Foundation

// MARK: - Machine Acceleration Profile

/// Acceleration characteristics of a machine (SPK-1320).
/// Values are clamped to [10, 10000] mm/s² at init.
public struct MachineAccelProfile: Codable, Equatable, Sendable {

    /// Display name for the profile.
    public let name: String

    /// Cutting acceleration in mm/s² (default 300).
    public let accelMmPerSec2: Double

    /// Cutting deceleration in mm/s² (default 300).
    public let decelMmPerSec2: Double

    /// Rapid (G0) acceleration in mm/s² (default 500).
    public let rapidAccelMmPerSec2: Double

    /// Memberwise init; every accel value is clamped to [10, 10000] mm/s².
    public init(
        name: String,
        accelMmPerSec2: Double = 300,
        decelMmPerSec2: Double = 300,
        rapidAccelMmPerSec2: Double = 500
    ) {
        self.name = name
        self.accelMmPerSec2 = min(max(accelMmPerSec2, 10), 10000)
        self.decelMmPerSec2 = min(max(decelMmPerSec2, 10), 10000)
        self.rapidAccelMmPerSec2 = min(max(rapidAccelMmPerSec2, 10), 10000)
    }

    /// Stock GRBL-class machine profile: 300/300 mm/s² cut, 500 mm/s² rapid.
    public static let grblDefault = MachineAccelProfile(
        name: "GRBL Default",
        accelMmPerSec2: 300,
        decelMmPerSec2: 300,
        rapidAccelMmPerSec2: 500
    )
}

// MARK: - Acceleration-Aware Time Estimator

/// Trapezoidal velocity-profile time estimation (SPK-1320).
///
/// The legacy `TimeEstimator` divides distance by feed rate (constant speed),
/// which under-estimates short moves: a real machine accelerates and
/// decelerates, so a move that never reaches the commanded feed rate takes
/// longer than the naive `distance / v` estimate. This estimator models each
/// move as accel → cruise → decel (trapezoid), falling back to accel →
/// immediate decel (triangle) when the distance is too short to reach
/// `v_max = feedRate / 60`.
public enum AccelTimeEstimator {

    /// Time (seconds) for one straight move under a trapezoidal profile.
    ///
    /// - Parameters:
    ///   - distanceMm: move length in mm (<= 0 → 0 seconds).
    ///   - feedRateMmPerMin: commanded feed rate (<= 0 → 0 seconds).
    ///   - accelMmPerSec2: acceleration in mm/s² (<= 0 → 0 seconds).
    ///   - decelMmPerSec2: deceleration in mm/s² (<= 0 → 0 seconds).
    public static func moveTime(
        distanceMm: Double,
        feedRateMmPerMin: Double,
        accelMmPerSec2: Double,
        decelMmPerSec2: Double
    ) -> Double {
        guard distanceMm > 0, feedRateMmPerMin > 0, accelMmPerSec2 > 0, decelMmPerSec2 > 0 else {
            return 0
        }
        let vMax = feedRateMmPerMin / 60.0  // mm/s
        let a = accelMmPerSec2
        let d = decelMmPerSec2

        // Distance required to reach vMax then stop again: v²/2a + v²/2d.
        let distToReachVMax = (vMax * vMax) / (2 * a) + (vMax * vMax) / (2 * d)

        if distToReachVMax >= distanceMm {
            // Triangle profile: accelerate to vPeak, immediately decelerate.
            // distance = v²/2a + v²/2d  →  v = sqrt(2·a·d·distance/(a+d))
            let vPeak = (2 * a * d * distanceMm / (a + d)).squareRoot()
            return vPeak / a + vPeak / d
        }

        // Trapezoid: accel → cruise at vMax → decel.
        let tAccel = vMax / a
        let tDecel = vMax / d
        let distAccel = 0.5 * a * tAccel * tAccel
        let distDecel = 0.5 * d * tDecel * tDecel
        let distCruise = distanceMm - distAccel - distDecel
        let tCruise = distCruise / vMax
        return tAccel + tCruise + tDecel
    }

    /// Estimate cutting/travel/total time for a G-code program.
    ///
    /// - G0 moves are rapid (travel) at `rapidRateMmPerMin` with
    ///   `profile.rapidAccelMmPerSec2`.
    /// - G1/G2/G3 moves are cutting at `feedRateMmPerMin` with
    ///   `profile.accelMmPerSec2`.
    /// - Z-only moves count as travel at the cutting accel.
    /// - Motion mode is modal: a line without a G word inherits the previous
    ///   mode. XY axes are modal too — a missing axis keeps its last position.
    /// - Malformed / non-move lines (comments, M-codes, garbage) are skipped;
    ///   the estimator never throws.
    public static func estimate(
        gcodeLines: [String],
        profile: MachineAccelProfile = .grblDefault,
        feedRateMmPerMin: Double = 1000,
        rapidRateMmPerMin: Double = 5000
    ) -> (cuttingTimeSeconds: Double, travelTimeSeconds: Double, totalTimeSeconds: Double) {
        var cuttingTime = 0.0
        var travelTime = 0.0
        var lastX = 0.0
        var lastY = 0.0
        var isRapid = false  // modal motion mode (initial: cutting move)

        for rawLine in gcodeLines {
            let line = rawLine.trimmingCharacters(in: CharacterSet.whitespaces)
            if line.isEmpty || line.hasPrefix("(") || line.hasPrefix(";") || line.hasPrefix("%") || line.hasPrefix("O=") {
                continue
            }

            var gCode: String?
            var x: Double?
            var y: Double?
            var z: Double?
            var hasMoveWord = false

            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let word = String(token)
                if word.hasPrefix("G") {
                    gCode = word
                } else if word.hasPrefix("X") {
                    x = Double(word.dropFirst())
                } else if word.hasPrefix("Y") {
                    y = Double(word.dropFirst())
                } else if word.hasPrefix("Z") {
                    z = Double(word.dropFirst())
                }
            }

            if let g = gCode {
                let code = g.dropFirst()
                if code == "0" {
                    isRapid = true
                    hasMoveWord = true
                } else if code == "1" || code == "2" || code == "3" {
                    isRapid = false
                    hasMoveWord = true
                }
            }

            // Not a move: no explicit G0-G3 word and no axis words.
            guard hasMoveWord || x != nil || y != nil || z != nil else { continue }

            // Modal XY: missing axis keeps its previous position.
            let newX = x ?? lastX
            let newY = y ?? lastY
            let dx = newX - lastX
            let dy = newY - lastY
            let distance = (dx * dx + dy * dy).squareRoot()

            // Z-only moves (no XY delta) count as travel at the cut accel.
            let accel = (distance > 0 && isRapid) ? profile.rapidAccelMmPerSec2 : profile.accelMmPerSec2
            let feed = isRapid ? rapidRateMmPerMin : feedRateMmPerMin
            let time = moveTime(
                distanceMm: distance,
                feedRateMmPerMin: feed,
                accelMmPerSec2: accel,
                decelMmPerSec2: accel
            )

            if isRapid || distance == 0 {
                travelTime += time
            } else {
                cuttingTime += time
            }

            lastX = newX
            lastY = newY
        }

        let totalTime = cuttingTime + travelTime
        return (cuttingTimeSeconds: cuttingTime, travelTimeSeconds: travelTime, totalTimeSeconds: totalTime)
    }
}
