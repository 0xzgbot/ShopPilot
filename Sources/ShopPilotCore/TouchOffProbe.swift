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

// MARK: - SPK-2022a — XYZ plate probe cycle (Z → X → Y)

/// A validated XYZ plate probing plan. Three legs run in order Z → X → Y;
/// each leg probes its axis (`G38.2`) and then immediately commits its own
/// `G10 L20 P1 <axis><offset>` work-offset, so a mid-cycle abort keeps every
/// already-committed leg's offset while applying nothing from uncompleted legs.
public struct XYZPlatePlan: Equatable, Sendable {
    /// Probe feed rate, mm/min.
    public let probeSpeed: Double
    /// Maximum probe travel below/beside the start position, mm.
    public let maxDepth: Double
    /// Safe Z to rapid to before the Z leg, mm.
    public let retractHeight: Double
    /// Zero-plate thickness, mm.
    public let plateThickness: Double
    /// Operator X/Y compensation (e.g. tool radius) added on top of the plate
    /// half-thickness for the X and Y commits, mm.
    public let userXYOffset: Double
}

extension TouchOff {
    /// Build a validated XYZ plate plan, clamping every input into the same
    /// safe ranges as `plan`.
    public static func planXYZPlate(
        plateThickness: Double,
        probeSpeed: Double = 120,
        maxDepth: Double = 10,
        retractHeight: Double = 5,
        userXYOffset: Double = 0
    ) -> XYZPlatePlan {
        XYZPlatePlan(
            probeSpeed: min(max(probeSpeed, probeSpeedRange.lowerBound), probeSpeedRange.upperBound),
            maxDepth: min(max(maxDepth, maxDepthRange.lowerBound), maxDepthRange.upperBound),
            retractHeight: min(max(retractHeight, retractHeightRange.lowerBound), retractHeightRange.upperBound),
            plateThickness: min(max(plateThickness, plateThicknessRange.lowerBound), plateThicknessRange.upperBound),
            userXYOffset: userXYOffset
        )
    }

    /// The Z-leg commit: current position (= plate top) becomes Z = thickness,
    /// so the stock surface under the plate reads Z = 0 — identical math to
    /// `zOffset(probeHitZ: 0, plateThickness:)`.
    public static func zCommitOffset(plateThickness: Double) -> Double {
        zOffset(probeHitZ: 0, plateThickness: plateThickness)
    }

    /// The X/Y-leg commit: the probe contacts the plate edge, whose center is
    /// half a plate thickness away, plus the operator's tool-radius offset.
    public static func xyCommitOffset(plateThickness: Double, userXYOffset: Double) -> Double {
        plateThickness / 2 + userXYOffset
    }

    /// One leg of the XYZ cycle, as its own all-or-nothing unit:
    /// 1. `G90` — absolute positioning.
    /// 2. `G38.2 <axis>-<maxDepth> F<probeSpeed>` — probe until contact.
    /// 3. `G10 L20 P1 <axis><commit>` — commit this leg's work offset.
    /// 4. `G91` + `G0 <axis><maxDepth>` + `G90` — back off the contact.
    public static func xyzPlateLeg(_ plan: XYZPlatePlan, axis: String) -> [String] {
        let commit: Double
        switch axis {
        case "Z": commit = zCommitOffset(plateThickness: plan.plateThickness)
        case "X", "Y": commit = xyCommitOffset(plateThickness: plan.plateThickness, userXYOffset: plan.userXYOffset)
        default: fatalError("xyzPlateLeg: unknown axis '\(axis)'")
        }
        return [
            "G90",
            "G38.2 \(axis)-\(fmt(plan.maxDepth)) F\(fmt(plan.probeSpeed))",
            "G10 L20 P1 \(axis)\(fmt(commit))",
            "G91",
            "G0 \(axis)\(fmt(plan.maxDepth))",
            "G90",
        ]
    }

    /// The three legs in mandatory run order: Z → X → Y.
    public static func xyzPlateLegs(_ plan: XYZPlatePlan) -> [[String]] {
        ["Z", "X", "Y"].map { xyzPlateLeg(plan, axis: $0) }
    }

    /// The full XYZ plate cycle as one flat sequence (legs concatenated in
    /// Z → X → Y order). Senders that want per-leg abort semantics should use
    /// `xyzPlateLegs` instead and commit leg-by-leg.
    public static func xyzPlateGcode(_ plan: XYZPlatePlan) -> [String] {
        xyzPlateLegs(plan).flatMap { $0 }
    }
}

// MARK: - SPK-2022b — Tool-length offset (Z-only re-probe after tool change)

/// A validated tool-length-offset plan. After a tool change (`M6`), the new
/// bit's tip is found by re-probing **Z only** against the touch plate and
/// committing `G10 L20 P1 Z<thickness>` — so the stock surface reads Z = 0
/// under the new tool while every XY work register stays exactly as the
/// operator left it.
public struct ToolLengthOffsetPlan: Equatable, Sendable {
    /// Tool number carried by the `M6 T<n>` change, ≥ 1.
    public let toolNumber: Int
    /// Zero-plate thickness, mm.
    public let plateThickness: Double
    /// Probe feed rate, mm/min.
    public let probeSpeed: Double
    /// Maximum probe travel below the safe start height, mm.
    public let maxDepth: Double
    /// Safe Z to rapid to / retract to, mm.
    public let retractHeight: Double
}

extension TouchOff {
    /// Build a validated tool-length-offset plan, clamping inputs into the
    /// same safe ranges as `plan`.
    public static func planToolLengthOffset(
        toolNumber: Int = 1,
        plateThickness: Double,
        probeSpeed: Double = 120,
        maxDepth: Double = 10,
        retractHeight: Double = 5
    ) -> ToolLengthOffsetPlan {
        ToolLengthOffsetPlan(
            toolNumber: max(toolNumber, 1),
            plateThickness: min(max(plateThickness, plateThicknessRange.lowerBound), plateThicknessRange.upperBound),
            probeSpeed: min(max(probeSpeed, probeSpeedRange.lowerBound), probeSpeedRange.upperBound),
            maxDepth: min(max(maxDepth, maxDepthRange.lowerBound), maxDepthRange.upperBound),
            retractHeight: min(max(retractHeight, retractHeightRange.lowerBound), retractHeightRange.upperBound)
        )
    }

    /// The tool-length-offset sequence. Every line touches Z (or no axis) —
    /// there are deliberately NO X or Y words anywhere in the emission:
    /// 1. `G90` — absolute positioning.
    /// 2. `M6 T<tool>` — the tool change itself.
    /// 3. `G0 Z<retractHeight>` — rapid to safe Z (Z axis only).
    /// 4. `G38.2 Z-<maxDepth> F<probeSpeed>` — probe down until contact.
    /// 5. `G10 L20 P1 Z<commit>` — current position (= plate top) becomes
    ///    Z = plate thickness; identical math to `zCommitOffset`, so the
    ///    stock surface reads Z = 0 under the new tool.
    /// 6. `G0 Z<retractHeight>` — retract off the plate.
    public static func toolLengthOffsetSequence(_ plan: ToolLengthOffsetPlan) -> [String] {
        [
            "G90",
            "M6 T\(plan.toolNumber)",
            "G0 Z\(fmt(plan.retractHeight))",
            "G38.2 Z-\(fmt(plan.maxDepth)) F\(fmt(plan.probeSpeed))",
            "G10 L20 P1 Z\(fmt(zCommitOffset(plateThickness: plan.plateThickness)))",
            "G0 Z\(fmt(plan.retractHeight))",
        ]
    }

    /// True when the sequence is provably Z-only: no line carries an X or Y
    /// word (the guard senders rely on — XY work offsets cannot be touched
    /// because no X/Y coordinate is ever transmitted).
    public static func isZOnly(_ sequence: [String]) -> Bool {
        sequence.allSatisfy { line in
            line.range(of: "[XY]", options: .regularExpression) == nil
        }
    }
}
