import Foundation

// MARK: - Sketch Carving (SPK-0901 remainder)

/// Sketch Carving: the classic "pencil sketch" photo carve. Where photo
/// V-Carve carves BRIGHTNESS as depth (dark = deep everywhere), sketch
/// carving carves only the EDGES of the image — a Sobel gradient map gates
/// the V-bit: strong brightness transitions carve deep V-lines, flat areas
/// stay untouched. The result reads as hand-drawn line art, not a tone map.
public struct SketchCarveToolpathParams: Codable, Sendable {
    public var vBitAngleDegrees: Double
    public var maxDepthMm: Double
    public var edgeThreshold: Double      // 0…1 — normalized gradient gate
    public var stepOverMm: Double
    public var safeZHeightMm: Double
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double

    public init(
        vBitAngleDegrees: Double = 60.0,
        maxDepthMm: Double = 2.5,
        edgeThreshold: Double = 0.12,
        stepOverMm: Double = 0.5,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0
    ) {
        self.vBitAngleDegrees = vBitAngleDegrees
        self.maxDepthMm = maxDepthMm
        self.edgeThreshold = edgeThreshold
        self.stepOverMm = stepOverMm
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
    }

    private enum CodingKeys: String, CodingKey {
        case vBitAngleDegrees, maxDepthMm, edgeThreshold, stepOverMm
        case safeZHeightMm, feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 60.0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 2.5
        edgeThreshold = try c.decodeIfPresent(Double.self, forKey: .edgeThreshold) ?? 0.12
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
        try c.encode(edgeThreshold, forKey: .edgeThreshold)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeRateMmPerMin, forKey: .plungeRateMmPerMin)
        try c.encode(spindleRpm, forKey: .spindleRpm)
    }
}

public enum SketchCarveToolpathEngine {

    /// Raster the edge map at `stepOver` row spacing; along each row the Z
    /// axis follows depth = edgeStrength·maxDepth, where edgeStrength is the
    /// normalized Sobel gradient (0 = flat, 1 = strongest transition in the
    /// image). Gradients below `edgeThreshold` cut nothing, so flat regions
    /// stay untouched and only the "sketch lines" carve.
    public static func compute(
        heightfield: HeightfieldData,
        params: SketchCarveToolpathParams
    ) -> SpecialtyResult {
        let w = heightfield.width
        let h = heightfield.height
        let stepOver = max(0.1, params.stepOverMm)

        // 1. Sobel gradient magnitude per cell (clamped borders).
        var mag = [Double](repeating: 0, count: w * h)
        var maxMag = 0.0
        func at(_ r: Int, _ c: Int) -> Double {
            let rr = min(max(r, 0), h - 1)
            let cc = min(max(c, 0), w - 1)
            return heightfield.heights[rr * w + cc]
        }
        for r in 0..<h {
            for c in 0..<w {
                let gx = -at(r - 1, c - 1) - 2 * at(r, c - 1) - at(r + 1, c - 1)
                    + at(r - 1, c + 1) + 2 * at(r, c + 1) + at(r + 1, c + 1)
                let gy = -at(r - 1, c - 1) - 2 * at(r - 1, c) - at(r - 1, c + 1)
                    + at(r + 1, c - 1) + 2 * at(r + 1, c) + at(r + 1, c + 1)
                let m = (gx * gx + gy * gy).squareRoot()
                mag[r * w + c] = m
                if m > maxMag { maxMag = m }
            }
        }

        // 2. Normalize + threshold into the edge map.
        let norm = max(maxMag, 1e-9)
        let threshold = min(max(params.edgeThreshold, 0), 1)
        let edge = mag.map { m -> Double in
            let e = m / norm
            return e >= threshold ? e : 0
        }

        // 3. Raster the edge map (mirrors photo V-Carve's row walk).
        var lines: [String] = ["%", "O=SKETCH_CARVE_TOOLPATH"]
        lines.append("(Sketch Carve: V-bit \(Int(params.vBitAngleDegrees))° · depth \(String(format: "%.2f", params.maxDepthMm))mm · edge ≥ \(String(format: "%.0f", threshold * 100))%)")
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        var totalLength = 0.0
        var row = 0
        var passCount = 0
        var carvedCells = 0

        let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
        while row < h {
            passCount += 1
            let cy = heightfield.minY + (Double(row) + 0.5) * heightfield.cellSizeMm
            lines.append("")
            lines.append("(Sketch pass \(passCount), Y=\(String(format: "%.3f", cy)))")
            lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

            var first = true
            var prevX = 0.0
            var col = 0
            while col < w {
                let cx = heightfield.minX + (Double(col) + 0.5) * heightfield.cellSizeMm
                let depth = edge[row * w + col] * params.maxDepthMm
                let z = -depth
                if depth > 1e-6 { carvedCells += 1 }
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
        return SpecialtyResult(gcodeLines: lines, estimatedTimeSeconds: time, featureCount: carvedCells)
    }
}
