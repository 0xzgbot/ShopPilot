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
    /// SPK-2110a — flat tip diameter at the V-bit point. 0 = sharp point.
    /// Groove top width w = tip + 2·d·tan(θ/2).
    public var tipDiameterMm: Double
    /// SPK-2110a — carve dark pixels SHALLOW instead of deep (white-on-dark
    /// artwork without inverting the image first).
    public var invertLuminance: Bool
    /// SPK-2110a — raster direction in degrees. Init default 45° (a diagonal
    /// pass visits ridges the 0° Y-raster misses); legacy decode stays 0 so
    /// stored jobs regenerate byte-stable.
    public var rasterAngleDegrees: Double

    public init(
        vBitAngleDegrees: Double = 60.0,
        maxDepthMm: Double = 3.0,
        stepOverMm: Double? = nil,
        safeZHeightMm: Double = 5.0,
        feedRateMmPerMin: Double = 1200,
        plungeRateMmPerMin: Double = 300,
        spindleRpm: Double = 0,
        tipDiameterMm: Double = 0.1,
        invertLuminance: Bool = false,
        rasterAngleDegrees: Double = 45.0
    ) {
        self.vBitAngleDegrees = vBitAngleDegrees
        self.maxDepthMm = maxDepthMm
        // SPK-2110a — default stepover is 50% of the WIDEST groove so adjacent
        // grooves overlap and no uncut ridge is wider than the tip; an
        // explicit value still wins.
        let widest = PhotoVCarveToolpathParams.grooveWidthMm(
            vBitAngleDegrees: vBitAngleDegrees, tipDiameterMm: tipDiameterMm,
            depthMm: maxDepthMm)
        self.stepOverMm = stepOverMm ?? max(0.05, widest * 0.5)
        self.safeZHeightMm = safeZHeightMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
        self.tipDiameterMm = tipDiameterMm
        self.invertLuminance = invertLuminance
        self.rasterAngleDegrees = rasterAngleDegrees
    }

    /// SPK-2110a — groove TOP WIDTH at cut depth d for a V-bit of angle θ
    /// with a flat tip Ø t: w = t + 2·d·tan(θ/2). Depth from luminance is
    /// unchanged; only the lateral extent of each groove is derived here.
    public static func grooveWidthMm(
        vBitAngleDegrees theta: Double, tipDiameterMm tip: Double, depthMm d: Double
    ) -> Double {
        let t = max(0, tip)
        guard theta > 0, theta < 180 else { return t }
        return t + 2 * max(0, d) * tan(theta / 2 * .pi / 180)
    }

    private enum CodingKeys: String, CodingKey {
        case vBitAngleDegrees, maxDepthMm, stepOverMm, safeZHeightMm
        case feedRateMmPerMin, plungeRateMmPerMin, spindleRpm
        case tipDiameterMm, invertLuminance, rasterAngleDegrees
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vBitAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .vBitAngleDegrees) ?? 60.0
        maxDepthMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthMm) ?? 3.0
        // SPK-2110a — legacy decode keeps the old literal 0.5 (byte-stable).
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 0.5
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1200
        plungeRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeRateMmPerMin) ?? 300
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        // SPK-2110a — legacy decode defaults: no tip (sharp), no inversion,
        // raster angle 0 (today's Y-lace) so old jobs regenerate identically.
        tipDiameterMm = try c.decodeIfPresent(Double.self, forKey: .tipDiameterMm) ?? 0
        invertLuminance = try c.decodeIfPresent(Bool.self, forKey: .invertLuminance) ?? false
        rasterAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .rasterAngleDegrees) ?? 0
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
        try c.encode(tipDiameterMm, forKey: .tipDiameterMm)
        try c.encode(invertLuminance, forKey: .invertLuminance)
        try c.encode(rasterAngleDegrees, forKey: .rasterAngleDegrees)
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
        // SPK-2110a — announce tip + widest-groove width; 0° keeps today's
        // exact header so legacy (decode angle 0) output stays byte-stable.
        if params.rasterAngleDegrees < 0.01 {
            lines.append("(Photo V-Carve: V-bit \(Int(params.vBitAngleDegrees))° · depth \(String(format: "%.2f", params.maxDepthMm))mm · step \(String(format: "%.2f", params.stepOverMm))mm)")
        } else {
            let widest = PhotoVCarveToolpathParams.grooveWidthMm(
                vBitAngleDegrees: params.vBitAngleDegrees,
                tipDiameterMm: params.tipDiameterMm,
                depthMm: params.maxDepthMm)
            lines.append("(Photo V-Carve: V-bit \(Int(params.vBitAngleDegrees))° tip Ø\(String(format: "%.2f", params.tipDiameterMm)) · groove ≤\(String(format: "%.2f", widest))mm wide at maxDepth · depth \(String(format: "%.2f", params.maxDepthMm))mm · step \(String(format: "%.2f", params.stepOverMm))mm · raster \(Int(params.rasterAngleDegrees.rounded()))°)")
        }
        if params.invertLuminance {
            lines.append("(Invert: dark pixels carve shallow)")
        }
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        var totalLength = 0.0
        var passCount = 0

        /// Depth at one sample — luminance drives it; invert flips which end
        /// is deep. Kept as a closure so both lace branches share the rule.
        func depthAt(_ h: Double) -> Double {
            let luminance = min(1.0, max(0.0, h / maxH))
            let base = (1.0 - luminance) * params.maxDepthMm
            return params.invertLuminance ? params.maxDepthMm - base : base
        }

        let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
        if params.rasterAngleDegrees < 0.01 {
            var row = 0
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
                let depth = depthAt(h)
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
        } else {
            // SPK-2110a — rotated lace (45° default): parallel passes along u,
            // spaced stepOver apart on n, clipped to the grid rectangle of cell
            // centers. A diagonal pass visits ridges the 0° Y-raster misses.
            let theta = params.rasterAngleDegrees * Double.pi / 180.0
            let ux = cos(theta), uy = sin(theta)
            let nx = -uy, ny = ux
            let cell = heightfield.cellSizeMm
            let cxMin = heightfield.minX + 0.5 * cell
            let cxMax = heightfield.minX + (Double(heightfield.width) - 0.5) * cell
            let cyMin = heightfield.minY + 0.5 * cell
            let cyMax = heightfield.minY + (Double(heightfield.height) - 0.5) * cell
            let corners = [(cxMin, cyMin), (cxMax, cyMin), (cxMin, cyMax), (cxMax, cyMax)]
            var dMin = Double.infinity
            var dMax = -Double.infinity
            for corner in corners {
                let d = nx * corner.0 + ny * corner.1
                dMin = min(dMin, d)
                dMax = max(dMax, d)
            }

            let strideMm = Double(rowStride) * cell
            var dOffset = dMin + 0.5 * strideMm
            while dOffset <= dMax {
                var tLo = -Double.infinity
                var tHi = Double.infinity
                var inside = true
                // X slab of the clip rectangle.
                if abs(ux) < 1e-12 {
                    inside = (nx * dOffset) >= cxMin && (nx * dOffset) <= cxMax
                } else {
                    var a = (cxMin - nx * dOffset) / ux
                    var b = (cxMax - nx * dOffset) / ux
                    if a > b { swap(&a, &b) }
                    tLo = max(tLo, a); tHi = min(tHi, b)
                }
                // Y slab of the clip rectangle.
                if inside {
                    if abs(uy) < 1e-12 {
                        inside = (ny * dOffset) >= cyMin && (ny * dOffset) <= cyMax
                    } else {
                        var a = (cyMin - ny * dOffset) / uy
                        var b = (cyMax - ny * dOffset) / uy
                        if a > b { swap(&a, &b) }
                        tLo = max(tLo, a); tHi = min(tHi, b)
                    }
                }
                if inside && tLo <= tHi {
                    passCount += 1
                    lines.append("")
                    lines.append("(Photo pass \(passCount), raster \(Int(params.rasterAngleDegrees.rounded()))deg)")
                    lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")
                    var firstPt = true
                    var prevX = 0.0
                    var prevY = 0.0
                    var t = tLo
                    while t <= tHi + 1e-9 {
                        var sx = nx * dOffset + ux * t
                        var sy = ny * dOffset + uy * t
                        sx = min(max(sx, cxMin), cxMax)
                        sy = min(max(sy, cyMin), cyMax)
                        let h = heightfield.heightInterpolated(atX: sx, y: sy)
                        let depth = depthAt(h)
                        let z = -(stockTop - h) - depth
                        if firstPt {
                            lines.append("G0 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy))")
                            lines.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                            firstPt = false
                        } else {
                            lines.append("G1 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy)) Z\(String(format: "%.3f", z)) F\(Int(params.feedRateMmPerMin))")
                            totalLength += ((sx - prevX) * (sx - prevX) + (sy - prevY) * (sy - prevY)).squareRoot()
                        }
                        prevX = sx
                        prevY = sy
                        t += cell
                    }
                }
                dOffset += strideMm
            }
        }

        lines.append("")
        lines.append("M30")
        lines.append("%")
        let time = totalLength / max(1, params.feedRateMmPerMin) * 60.0
        return SpecialtyResult(gcodeLines: lines, estimatedTimeSeconds: time, featureCount: passCount)
    }
}
