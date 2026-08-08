import Foundation

// MARK: - Wrapped fluting (parity rows H04/H05, rotary gadget)

/// Wrap direction around the rotary axis.
public enum WrapDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise
}

/// Fluting cut wrapped onto a rotary cylinder. The flute line lives in flat
/// (x, y) space; X stays the axial dimension (X word unchanged, in mm) while
/// the flat Y coordinate wraps to A-axis degrees about the cylinder axis:
/// `aDeg = y / (π · wrapDiameterMm) · 360`. Direction mirrors the sweep the
/// same way `RotaryWrapToolpathEngine` does.
public struct WrappedFlutingParams: Codable, Sendable {
    public var startDepthMm: Double
    public var cutDepthMm: Double
    public var passDepthMm: Double      // 0 = single pass to full depth
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var spindleRpm: Double
    public var wrapDiameterMm: Double
    public var direction: WrapDirection

    public init(
        startDepthMm: Double = 0,
        cutDepthMm: Double = 4.0,
        passDepthMm: Double = 2.0,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1500,
        plungeRateMmPerMin: Double = 300,
        toolDiameterMm: Double = 6.0,
        spindleRpm: Double = 0,
        wrapDiameterMm: Double = 50.0,
        direction: WrapDirection = .clockwise
    ) {
        self.startDepthMm = startDepthMm
        self.cutDepthMm = cutDepthMm
        self.passDepthMm = passDepthMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.toolDiameterMm = toolDiameterMm
        self.spindleRpm = spindleRpm
        self.wrapDiameterMm = wrapDiameterMm
        self.direction = direction
    }

    /// Create params from material defaults (mirrors the `fromMaterial`
    /// scaling convention used by `PocketToolpathParams`).
    public static func fromMaterial(_ material: Material) -> WrappedFlutingParams {
        let pass = max(0.5, material.maxDepthOfCutMm)
        return WrappedFlutingParams(
            startDepthMm: 0,
            cutDepthMm: pass * 2.0,
            passDepthMm: pass,
            safeZHeightMm: 5.0,
            feedRateMmPerMin: material.maxFeedRateMmPerMin * 0.7,
            plungeRateMmPerMin: material.maxFeedRateMmPerMin * 0.3,
            toolDiameterMm: 6.0,
            spindleRpm: 0,
            wrapDiameterMm: 50.0,
            direction: .clockwise
        )
    }

    private enum CodingKeys: String, CodingKey {
        case startDepthMm, cutDepthMm, passDepthMm, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, toolDiameterMm, spindleRpm
        case wrapDiameterMm, direction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 4.0
        passDepthMm = try c.decodeIfPresent(Double.self, forKey: .passDepthMm) ?? 2.0
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1500
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        wrapDiameterMm = try c.decodeIfPresent(Double.self, forKey: .wrapDiameterMm) ?? 50.0
        direction = try c.decodeIfPresent(WrapDirection.self, forKey: .direction) ?? .clockwise
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startDepthMm, forKey: .startDepthMm)
        try c.encode(cutDepthMm, forKey: .cutDepthMm)
        try c.encode(passDepthMm, forKey: .passDepthMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(wrapDiameterMm, forKey: .wrapDiameterMm)
        try c.encode(direction, forKey: .direction)
    }
}

public struct WrappedFlutingResult: Codable, Sendable {
    public let gcode: [String]
    public let moveCount: Int
    public let marker: String

    public init(gcode: [String], moveCount: Int, marker: String) {
        self.gcode = gcode
        self.moveCount = moveCount
        self.marker = marker
    }
}

public enum WrappedFlutingToolpathEngine {

    /// Flute a single line of `points` (flat x, y) around the cylinder.
    /// X stays the axial word; flat Y becomes the A word (degrees about the
    /// X axis). Each flute is cut with step-down passes of `passDepthMm`
    /// (0 = one pass to full depth). The marker `O=WRAPPED_FLUTING` is the
    /// first line; M3 S<rpm> follows when spindleRpm > 0; the program ends
    /// with M30.
    public static func compute(
        points: [VectorPoint],
        params: WrappedFlutingParams
    ) -> WrappedFlutingResult {
        var gcode: [String] = ["O=WRAPPED_FLUTING"]
        gcode.append("(Wrapped fluting: Ø \(String(format: "%.1f", params.wrapDiameterMm))mm · depth \(String(format: "%.2f", params.cutDepthMm))mm · \(params.direction == .clockwise ? "CW" : "CCW"))")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let passes = params.passDepthMm > 0 ? max(1, Int(ceil(params.cutDepthMm / params.passDepthMm))) : 1
        var moveCount = 0
        let circumference = .pi * params.wrapDiameterMm

        func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

        /// Flat Y (mm) → A (degrees, direction-aware), normalized to 0..360.
        /// Mirrors `RotaryEngine.linearToAngular` + the CCW mirror used by
        /// `RotaryWrapToolpathEngine`.
        func angle(forY y: Double) -> Double {
            let a = ((y / circumference * 360.0).truncatingRemainder(dividingBy: 360.0) + 360.0)
                .truncatingRemainder(dividingBy: 360.0)
            return params.direction == .clockwise ? a : (360.0 - a).truncatingRemainder(dividingBy: 360.0)
        }

        guard points.count >= 2 else {
            gcode.append("")
            gcode.append("M30")
            return WrappedFlutingResult(gcode: gcode, moveCount: 0, marker: "O=WRAPPED_FLUTING")
        }

        let first = points[0]
        for p in 1...passes {
            let depth = params.passDepthMm > 0
                ? min(Double(p) * params.passDepthMm, params.cutDepthMm)
                : params.cutDepthMm
            let z = -(params.startDepthMm + depth)
            gcode.append("")
            gcode.append("(Wrapped flute pass \(p)/\(passes))")
            gcode.append("G0 X\(fmt(first.x)) A\(fmt(angle(forY: first.y)))")
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
            gcode.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
            moveCount += 1
            for point in points.dropFirst() {
                gcode.append("G1 X\(fmt(point.x)) A\(fmt(angle(forY: point.y))) F\(Int(params.feedRateMmPerMin))")
                moveCount += 1
            }
            gcode.append("G0 Z\(String(format: "%.1f", params.safeZHeightMm))")
        }
        gcode.append("")
        gcode.append("M30")
        return WrappedFlutingResult(gcode: gcode, moveCount: moveCount, marker: "O=WRAPPED_FLUTING")
    }
}
