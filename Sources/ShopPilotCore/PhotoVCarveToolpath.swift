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
    /// SPK-2110b — linked two-pass: a rough pass at `roughStepOverFraction`
    /// of the widest groove clears bulk, then a finish pass at
    /// `finishStepOverFraction` cleans the surface. Default OFF (single pass
    /// keeps today's output byte-stable).
    public var twoPass: Bool
    /// SPK-2110b — rough pass stepover as a fraction of the widest groove
    /// (default 50%).
    public var roughStepOverFraction: Double
    /// SPK-2110b — finish pass stepover as a fraction of the widest groove
    /// (default 10%, inside Aspire's 8–12% finish band).
    public var finishStepOverFraction: Double

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
        rasterAngleDegrees: Double = 45.0,
        twoPass: Bool = false,
        roughStepOverFraction: Double = 0.5,
        finishStepOverFraction: Double = 0.10
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
        self.twoPass = twoPass
        self.roughStepOverFraction = roughStepOverFraction
        self.finishStepOverFraction = finishStepOverFraction
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
        case twoPass, roughStepOverFraction, finishStepOverFraction
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
        tipDiameterMm = try c.decodeIfPresent(Double.self, forKey: .tipDiameterMm) ?? 0
        invertLuminance = try c.decodeIfPresent(Bool.self, forKey: .invertLuminance) ?? false
        rasterAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .rasterAngleDegrees) ?? 0
        twoPass = try c.decodeIfPresent(Bool.self, forKey: .twoPass) ?? false
        roughStepOverFraction = try c.decodeIfPresent(Double.self, forKey: .roughStepOverFraction) ?? 0.5
        finishStepOverFraction = try c.decodeIfPresent(Double.self, forKey: .finishStepOverFraction) ?? 0.10
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
        try c.encode(twoPass, forKey: .twoPass)
        try c.encode(roughStepOverFraction, forKey: .roughStepOverFraction)
        try c.encode(finishStepOverFraction, forKey: .finishStepOverFraction)
    }
}

public enum PhotoVCarveToolpathEngine {

    /// Raster the heightfield; along each row the Z axis follows depth =
    /// (1 − luminance)·maxDepth, where luminance is the normalized height
    /// (0 = black → deepest, maxHeight = white → 0).
    /// SPK-2110b — when `params.twoPass`, a rough pass at
    /// `roughStepOverFraction` clears bulk first, then a finish pass at
    /// `finishStepOverFraction` cleans the surface.
    public static func compute(
        heightfield: HeightfieldData,
        params: PhotoVCarveToolpathParams
    ) -> SpecialtyResult {
        let maxH = max(heightfield.maxHeight, 1e-9)
        let stockTop = heightfield.maxHeight

        var lines: [String] = ["%", "O=PHOTO_V_CARVE_TOOLPATH"]
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
        if params.twoPass {
            let widest = PhotoVCarveToolpathParams.grooveWidthMm(
                vBitAngleDegrees: params.vBitAngleDegrees,
                tipDiameterMm: params.tipDiameterMm,
                depthMm: params.maxDepthMm)
            lines.append("(Two-pass: rough \(Int(params.roughStepOverFraction * 100))% / finish \(Int(params.finishStepOverFraction * 100))% of \(String(format: "%.2f", widest))mm widest groove)")
        }
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        var totalLength = 0.0
        var passCount = 0

        func depthAt(_ h: Double) -> Double {
            let luminance = min(1.0, max(0.0, h / maxH))
            let base = (1.0 - luminance) * params.maxDepthMm
            return params.invertLuminance ? params.maxDepthMm - base : base
        }

        /// Emit one lace (0° Y-raster or rotated diagonal) at a given stepover.
        /// Returns the G-code lines; shared by single-pass and both two-pass legs.
        func emitLace(rasterAngleDeg: Double, stepOverMm: Double, label: String) -> [String] {
            var out: [String] = []
            let stepOver = max(0.1, stepOverMm)
            let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
            if rasterAngleDeg < 0.01 {
                var row = 0
                while row < heightfield.height {
                    passCount += 1
                    let cy = heightfield.minY + (Double(row) + 0.5) * heightfield.cellSizeMm
                    out.append("")
                    out.append("(\(label) \(passCount), Y=\(String(format: "%.3f", cy)))")
                    out.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")
                    var first = true
                    var prevX = 0.0
                    var col = 0
                    while col < heightfield.width {
                        let cx = heightfield.minX + (Double(col) + 0.5) * heightfield.cellSizeMm
                        let depth = depthAt(heightfield.heightInterpolated(atX: cx, y: cy))
                        let z = -(stockTop) - depth
                        if first {
                            out.append("G0 X\(String(format: "%.3f", cx)) Y\(String(format: "%.3f", cy))")
                            out.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                            first = false
                        } else {
                            out.append("G1 X\(String(format: "%.3f", cx)) Y\(String(format: "%.3f", cy)) Z\(String(format: "%.3f", z)) F\(Int(params.feedRateMmPerMin))")
                            totalLength += abs(cx - prevX)
                        }
                        prevX = cx
                        col += rowStride
                    }
                    row += rowStride
                }
            } else {
                let theta = rasterAngleDeg * Double.pi / 180.0
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
                    dMin = min(dMin, d); dMax = max(dMax, d)
                }
                let strideMm = Double(rowStride) * cell
                var dOffset = dMin + 0.5 * strideMm
                while dOffset <= dMax {
                    var tLo = -Double.infinity
                    var tHi = Double.infinity
                    var inside = true
                    if abs(ux) < 1e-12 {
                        inside = (nx * dOffset) >= cxMin && (nx * dOffset) <= cxMax
                    } else {
                        var a = (cxMin - nx * dOffset) / ux
                        var b = (cxMax - nx * dOffset) / ux
                        if a > b { swap(&a, &b) }
                        tLo = max(tLo, a); tHi = min(tHi, b)
                    }
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
                        out.append("")
                        out.append("(\(label) \(passCount), raster \(Int(rasterAngleDeg.rounded()))deg)")
                        out.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")
                        var firstPt = true
                        var prevX = 0.0
                        var prevY = 0.0
                        var t = tLo
                        while t <= tHi + 1e-9 {
                            var sx = nx * dOffset + ux * t
                            var sy = ny * dOffset + uy * t
                            sx = min(max(sx, cxMin), cxMax)
                            sy = min(max(sy, cyMin), cyMax)
                            let depth = depthAt(heightfield.heightInterpolated(atX: sx, y: sy))
                            let z = -(stockTop) - depth
                            if firstPt {
                                out.append("G0 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy))")
                                out.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeRateMmPerMin))")
                                firstPt = false
                            } else {
                                out.append("G1 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy)) Z\(String(format: "%.3f", z)) F\(Int(params.feedRateMmPerMin))")
                                totalLength += ((sx - prevX) * (sx - prevX) + (sy - prevY) * (sy - prevY)).squareRoot()
                            }
                            prevX = sx; prevY = sy
                            t += cell
                        }
                    }
                    dOffset += strideMm
                }
            }
            return out
        }

        let widest = PhotoVCarveToolpathParams.grooveWidthMm(
            vBitAngleDegrees: params.vBitAngleDegrees,
            tipDiameterMm: params.tipDiameterMm,
            depthMm: params.maxDepthMm)
        if params.twoPass {
            lines.append("")
            lines.append("(=== ROUGH PASS ===)")
            lines.append(contentsOf: emitLace(rasterAngleDeg: params.rasterAngleDegrees,
                                  stepOverMm: widest * params.roughStepOverFraction,
                                  label: "Rough"))
            lines.append("")
            lines.append("(=== FINISH PASS ===)")
            lines.append(contentsOf: emitLace(rasterAngleDeg: params.rasterAngleDegrees,
                                  stepOverMm: widest * params.finishStepOverFraction,
                                  label: "Finish"))
        } else {
            lines.append(contentsOf: emitLace(rasterAngleDeg: params.rasterAngleDegrees,
                                  stepOverMm: max(0.1, params.stepOverMm),
                                  label: "Photo pass"))
        }

        lines.append("")
        lines.append("M30")
        lines.append("%")
        let time = totalLength / max(1, params.feedRateMmPerMin) * 60.0
        return SpecialtyResult(gcodeLines: lines, estimatedTimeSeconds: time, featureCount: passCount)
    }
}
