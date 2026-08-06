import Foundation

// MARK: - Rotary wrap toolpath (SPK-0904 lean slice)

/// Wrap 2D vectors around a rotary axis: the design's X dimension maps to
/// A-axis rotation (degrees), Y stays the axis dimension. This is the
/// classic "wrap 2D toolpaths" feature — draw the flat unwrap, cut the
/// cylinder. The legacy `RotaryEngine.linearToAngular` provides the
/// linear→angular mapping; this engine emits real A-axis G-code.
public struct RotaryWrapToolpathParams: Codable, Sendable {
    public var diameterMm: Double
    public var cutDepthMm: Double
    public var direction: RotaryDirection
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        diameterMm: Double = 50.0,
        cutDepthMm: Double = 1.0,
        direction: RotaryDirection = .clockwise,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.diameterMm = diameterMm
        self.cutDepthMm = cutDepthMm
        self.direction = direction
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case diameterMm, cutDepthMm, direction, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        diameterMm = try c.decodeIfPresent(Double.self, forKey: .diameterMm) ?? 50.0
        cutDepthMm = try c.decodeIfPresent(Double.self, forKey: .cutDepthMm) ?? 1.0
        direction = try c.decodeIfPresent(RotaryDirection.self, forKey: .direction) ?? .clockwise
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(diameterMm, forKey: .diameterMm)
        try c.encode(cutDepthMm, forKey: .cutDepthMm)
        try c.encode(direction, forKey: .direction)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum RotaryWrapToolpathEngine {

    /// Wrap each vector onto the rotary axis. X → A (degrees around the
    /// cylinder, 0..360, direction-aware), Y → Y (axis dimension). A full
    /// circumference of X maps to 360°; longer spans wrap modulo.
    /// Returns the same SpecialtyResult shape as the other engines.
    public static func compute(
        paths: [VectorPath],
        params: RotaryWrapToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> SpecialtyResult {
        var gcode: [String] = ["%", "O=ROTARY_WRAP_TOOLPATH"]
        gcode.append("(Rotary wrap: Ø \(String(format: "%.1f", params.diameterMm))mm · depth \(String(format: "%.2f", params.cutDepthMm))mm · \(params.direction == .clockwise ? "CW" : "CCW"))")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        let config = RotaryConfig(
            mode: .cylinder,
            diameter: params.diameterMm,
            axisLength: 0,
            direction: params.direction,
            wrapEnabled: true
        )
        let z = -params.cutDepthMm
        var featureCount = 0
        var totalLength = 0.0

        func fmt(_ v: Double) -> String { String(format: "%.3f", v) }

        /// X (flat unwrap mm) → A (degrees, direction-aware).
        func angle(forX x: Double) -> Double {
            let a = RotaryEngine.linearToAngular(linearPosition: x, config: config)
            return params.direction == .clockwise ? a : (360 - a).truncatingRemainder(dividingBy: 360)
        }

        for path in paths {
            guard path.points.count >= 2 else { continue }
            featureCount += 1
            let first = path.points[0]
            gcode.append("")
            gcode.append("(Wrapped path \(featureCount))")
            gcode.append("G0 A\(fmt(angle(forX: first.x))) Y\(fmt(first.y))")
            gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
            gcode.append("G1 Z\(fmt(z)) F\(Int(params.plungeRateMmPerMin))")
            for point in path.points.dropFirst() {
                gcode.append("G1 A\(fmt(angle(forX: point.x))) Y\(fmt(point.y)) F\(Int(params.feedRateMmPerMin))")
            }
            // Real length: unwrapped 2D distance between consecutive points.
            for i in 1..<path.points.count {
                let a = path.points[i - 1]
                let b = path.points[i]
                totalLength += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            }
            gcode.append("G0 Z\(fmt(params.safeZHeightMm))")
        }
        gcode.append("")
        gcode.append("M30")
        gcode.append("%")
        let time = totalLength / max(params.feedRateMmPerMin, 1) * 60.0 + Double(featureCount) * 1.2
        return SpecialtyResult(gcodeLines: gcode, estimatedTimeSeconds: time, featureCount: featureCount)
    }
}
