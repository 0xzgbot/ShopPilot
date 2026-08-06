import Foundation

// MARK: - Photo V-Carve (SPK-0901)

/// Real photo V-Carve: a V-bit raster where PIXEL BRIGHTNESS maps to cut
/// DEPTH — dark pixels carve deep, bright pixels stay high. Unlike the 3D
/// finish engine (which skims the surface with a ball nose), this is the
/// classic sign-shop photo carve: fine raster lines, depth = (1 − luminance)
/// × maxDepth, walls sloped by the V-bit angle.
public struct PhotoVCarveToolpathParams: Codable, Sendable {
    public var vBitAngleDegrees: Double
    public var maxDepthMm: Double
    public var stepOverMm: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        vBitAngleDegrees: Double = 60.0,
        maxDepthMm: Double = 3.0,
        stepOverMm: Double = 0.5,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.vBitAngleDegrees = vBitAngleDegrees
        self.maxDepthMm = maxDepthMm
        self.stepOverMm = stepOverMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case vBitAngleDegrees, maxDepthMm, stepOverMm, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 60.0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 3.0
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 0.5
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vBitAngleDegrees, forKey: .vBitAngleDegrees)
        try c.encode(maxDepthMm, forKey: .maxDepthMm)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum PhotoVCarveToolpathEngine {

    /// Raster the heightfield at `stepOver` row spacing; along each row the
    /// Z axis follows depth = (1 − luminance)·maxDepth, where luminance is
    /// the normalized height (0 = black → deepest, maxHeight = white → 0).
    /// Returns the same SpecialtyResult shape as the specialty engines so the
    /// tree/session wiring is uniform.
    public static func compute(
        heightfield: HeightfieldData,
        params: PhotoVCarveToolpathParams
    ) -> SpecialtyResult {
        let maxH = max(heightfield.maxHeight, 1e-9)
        let stepOver = max(0.1, params.stepOverMm)
        let stockTop = heightfield.maxHeight

        var lines: [String] = ["%", "O=PHOTO_V_CARVE_TOOLPATH"]
        lines.append("(Photo V-Carve: V-bit \(Int(params.vBitAngleDegrees))° · depth \(String(format: "%.2f", params.maxDepthMm))mm · step \(String(format: "%.2f", params.stepOverMm))mm)")
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        var totalLength = 0.0
        var row = 0
        var passCount = 0

        let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
        while row < heightfield.height {
            passCount += 1
            let cy = heightfield.minY + (Double(row) + 0.5) * heightfield.cellSizeMm
            lines.append("")
            lines.append("(Photo pass \(passCount), Y=\(String(format: "%.3f", cy)))")
            lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

            var first = true
            var prevX = 0.0
            var col = 0
            while col < heightfield.width {
                let cx = heightfield.minX + (Double(col) + 0.5) * heightfield.cellSizeMm
                let h = heightfield.heightInterpolated(atX: cx, y: cy)
                let luminance = min(1.0, max(0.0, h / maxH))
                let depth = (1.0 - luminance) * params.maxDepthMm
                let z = -(stockTop - h) - depth
                if first {
                    lines.append("G0 X\(String(format: "%.3f", cx)) Y\(String(format: "%.3f", cy))")
                    lines.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                    first = false
                } else {
                    lines.append("G1 X\(String(format: "%.3f", cx)) Y\(String(format: "%.3f", cy)) Z\(String(format: "%.3f", z)) F\(Int(params.feedRateMmPerMin))")
                    totalLength += abs(cx - prevX)
                }
                prevX = cx
                col += rowStride
            }
            row += rowStride
        }

        lines.append("")
        lines.append("M30")
        lines.append("%")
        let time = totalLength / max(1, params.feedRateMmPerMin) * 60.0
        return SpecialtyResult(gcodeLines: lines, estimatedTimeSeconds: time, featureCount: passCount)
    }
}
