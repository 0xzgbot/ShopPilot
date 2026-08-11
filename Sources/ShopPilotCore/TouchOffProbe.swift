import Foundation

/// SPK-1303 — touch-off / zero-plate probing planner (pure model, no I/O).
///
/// A touch-off cycle finds the machine-coordinate Z of the stock surface by
/// probing down onto a zero plate of known thickness. The planner produces a
/// safe G-code probe sequence and computes the G54 Z work offset that makes
/// the stock surface (plate removed) read as Z = 0.

/// A validated touch-off probing plan.
public struct TouchOffPlan: Equatable, Sendable {
    /// Probe feed rate, mm/min.
    public let probeSpeed: Double
    /// Maximum probe travel below the start height, mm.
    public let maxDepth: Double
    /// Safe Z to rapid to / retract to, mm.
    public let retractHeight: Double
    /// Zero-plate thickness, mm.
    public let plateThickness: Double
}

/// Namespace for touch-off probe planning and G54 offset math.
public enum TouchOff {
    /// Clamping ranges for `plan`.
    static let probeSpeedRange: ClosedRange<Double> = 10...2000
    static let maxDepthRange: ClosedRange<Double> = 1...50
    static let retractHeightRange: ClosedRange<Double> = 0...50
    static let plateThicknessRange: ClosedRange<Double> = 0.1...20

    /// Build a validated probe plan, clamping every input into its safe range.
    ///
    /// - Parameters:
    ///   - plateThickness: zero-plate thickness in mm (clamped to 0.1...20).
    ///   - probeSpeed: probe feed rate in mm/min (clamped to 10...2000).
    ///   - maxDepth: max probe travel in mm (clamped to 1...50).
    ///   - retractHeight: safe retract Z in mm (clamped to 0...50).
    public static func plan(
        plateThickness: Double,
        probeSpeed: Double = 120,
        maxDepth: Double = 10,
        retractHeight: Double = 5
    ) -> TouchOffPlan {
        TouchOffPlan(
            probeSpeed: min(max(probeSpeed, probeSpeedRange.lowerBound), probeSpeedRange.upperBound),
            maxDepth: min(max(maxDepth, maxDepthRange.lowerBound), maxDepthRange.upperBound),
            retractHeight: min(max(retractHeight, retractHeightRange.lowerBound), retractHeightRange.upperBound),
            plateThickness: min(max(plateThickness, plateThicknessRange.lowerBound), plateThicknessRange.upperBound)
        )
    }

    /// A safe touch-off probe sequence:
    /// 1. `G90` — absolute positioning.
    /// 2. `G0 Z<retractHeight>` — rapid to safe Z.
    /// 3. `G38.2 Z-<maxDepth> F<probeSpeed>` — probe down until contact or depth.
    /// 4. `G0 Z<retractHeight>` — retract after the hit.
    ///
    /// Numbers are formatted with no trailing zeros (e.g. "G38.2 Z-10 F120").
    public static func gcode(_ plan: TouchOffPlan) -> [String] {
        [
            "G90",
            "G0 Z\(fmt(plan.retractHeight))",
            "G38.2 Z-\(fmt(plan.maxDepth)) F\(fmt(plan.probeSpeed))",
            "G0 Z\(fmt(plan.retractHeight))",
        ]
    }

    /// G54 Z work offset so the stock surface (plate removed) reads 0.
    ///
    /// The probe hits the plate top at machine Z `probeHitZ`; the stock surface
    /// sits `plateThickness` lower. Offset = plateThickness - probeHitZ.
    /// Example: hit at Z = -30 with a 3 mm plate → offset = 3 - (-30) = 33,
    /// which raises machine zero to the stock top.
    public static func zOffset(probeHitZ: Double, plateThickness: Double) -> Double {
        plateThickness - probeHitZ
    }

    /// Format a Double without trailing zeros ("10.0" → "10", "11.5" → "11.5").
    private static func fmt(_ value: Double) -> String {
        var s = String(value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }
}
