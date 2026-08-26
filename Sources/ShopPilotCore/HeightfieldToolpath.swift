import Foundation

// MARK: - Heightfield 3D toolpaths (SPK-3D-spine-b)

/// Shared result of a heightfield toolpath computation.
public struct HeightfieldToolpathResult: Sendable {
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let passCount: Int
    public let bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)

    public init(
        gcodeLines: [String],
        estimatedTimeSeconds: Double,
        passCount: Int,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) {
        self.gcodeLines = gcodeLines
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.passCount = passCount
        self.bounds = bounds
    }
}

/// Z-level roughing params for the heightfield rough engine.
/// `ToolFeedApplicable` (SPK-1133) + linked spindle RPM (SPK-1133b). Custom
/// Codable keeps old paramsJSON decodable.
public struct HeightfieldRoughParams: Codable, Sendable, ToolFeedApplicable {
    public var toolDiameterMm: Double
    public var stepDownMm: Double
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var safeZHeightMm: Double
    /// Raw stock sits this far above the relief's highest point; Z=0 is the
    /// stock top, so all cut depths are negative.
    public var stockAllowanceMm: Double
    public var spindleRpm: Double
    /// SPK-3D-rest — rest machining: when > 0, this rough is a REST pass with
    /// the CURRENT (smaller) tool after a previous rough with
    /// `previousToolDiameterMm`. Only valleys narrower than the previous tool
    /// are cut — wider runs were already cleared by the prior pass. 0 = plain
    /// z-level rough (default, so legacy params decode unchanged).
    public var previousToolDiameterMm: Double
    /// SPK-1920d (H-304) — inverse mill: flip the effective surface (Z vs
    /// stock) so the machine cuts the COMPLEMENT of the relief — the fixture
    /// pocket / mold cavity around the part instead of the part itself.
    public var inverseMill: Bool

    public init(
        toolDiameterMm: Double = 6.0,
        stepDownMm: Double = 2.0,
        stepOverMm: Double = 1.5,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safeZHeightMm: Double = 5.0,
        stockAllowanceMm: Double = 0.5,
        spindleRpm: Double = 0,
        previousToolDiameterMm: Double = 0,
        inverseMill: Bool = false
    ) {
        self.toolDiameterMm = toolDiameterMm
        self.stepDownMm = stepDownMm
        self.stepOverMm = stepOverMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safeZHeightMm = safeZHeightMm
        self.stockAllowanceMm = stockAllowanceMm
        self.spindleRpm = spindleRpm
        self.previousToolDiameterMm = previousToolDiameterMm
        self.inverseMill = inverseMill
    }

    /// True when this pass is a rest rough (smaller tool clearing the valleys
    /// a previous larger tool left).
    public var isRestRough: Bool { previousToolDiameterMm > 1e-9 }

    private enum CodingKeys: String, CodingKey {
        case toolDiameterMm, stepDownMm, stepOverMm, feedRateMmPerMin
        case plungeFeedRateMmPerMin, safeZHeightMm, stockAllowanceMm, spindleRpm
        case previousToolDiameterMm
        case inverseMill
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        stepDownMm = try c.decodeIfPresent(Double.self, forKey: .stepDownMm) ?? 2.0
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 1.5
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        stockAllowanceMm = try c.decodeIfPresent(Double.self, forKey: .stockAllowanceMm) ?? 0.5
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        previousToolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .previousToolDiameterMm) ?? 0
        inverseMill = try c.decodeIfPresent(Bool.self, forKey: .inverseMill) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(stepDownMm, forKey: .stepDownMm)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(stockAllowanceMm, forKey: .stockAllowanceMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(previousToolDiameterMm, forKey: .previousToolDiameterMm)
        try c.encode(inverseMill, forKey: .inverseMill)
    }
}

/// Surface-following finish params for the heightfield finish engine.
public struct HeightfieldFinishParams: Codable, Sendable, ToolFeedApplicable {
    public var toolDiameterMm: Double
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var safeZHeightMm: Double
    public var spindleRpm: Double
    /// SPK-2100b — raster lace direction in degrees (0 = today's Y-lace rows
    /// running along X, 90 = X-stepover with runs along Y, 45 = diagonal).
    public var rasterAngleDegrees: Double

    public init(
        toolDiameterMm: Double = 3.175,
        stepOverMm: Double? = nil,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safeZHeightMm: Double = 5.0,
        spindleRpm: Double = 0,
        rasterAngleDegrees: Double = 0
    ) {
        self.toolDiameterMm = toolDiameterMm
        // SPK-2100a — default finish stepover is 10% of D (Aspire's documented
        // 8-12% finish quality band); an explicit value still wins. The legacy
        // DECODE path below keeps 0.8 for pre-existing stored paramsJSON.
        self.stepOverMm = stepOverMm ?? (toolDiameterMm * 0.10)
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safeZHeightMm = safeZHeightMm
        self.spindleRpm = spindleRpm
        self.rasterAngleDegrees = rasterAngleDegrees
    }

    private enum CodingKeys: String, CodingKey {
        case toolDiameterMm, stepOverMm, feedRateMmPerMin
        case plungeFeedRateMmPerMin, safeZHeightMm, spindleRpm
        case rasterAngleDegrees
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 3.175
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 0.8
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        safeZHeightMm = try c.decodeIfPresent(Double.self, forKey: .safeZHeightMm) ?? 5.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        // SPK-2100b — legacy-safe: pre-existing stored paramsJSON has no angle;
        // decode defaults to 0 so old jobs regenerate the same Y-lace path.
        rasterAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .rasterAngleDegrees) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(safeZHeightMm, forKey: .safeZHeightMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(rasterAngleDegrees, forKey: .rasterAngleDegrees)
    }

    /// SPK-2100b — leftover scallop for shallow ball lace: h ≈ s² / (8R).
    public var scallopHeightMm: Double {
        let r = max(1e-9, toolDiameterMm * 0.5)
        return (stepOverMm * stepOverMm) / (8.0 * r)
    }

    /// SPK-2100b — shipped raster set is {0, 45, 90}.
    public var snappedRasterAngleDegrees: Double {
        Self.snapRasterAngle(rasterAngleDegrees)
    }

    public static func snapRasterAngle(_ degrees: Double) -> Double {
        var a = degrees.truncatingRemainder(dividingBy: 180.0)
        if a < 0 { a += 180.0 }
        if a >= 135 { return 0 }
        let d0 = min(a, 180 - a)
        let d45 = abs(a - 45)
        let d90 = abs(a - 90)
        if d90 <= d45 && d90 <= d0 { return 90 }
        if d45 <= d0 { return 45 }
        return 0
    }
}

// MARK: - Rough engine

/// SPK-3D-spine-b — real z-level roughing from a heightfield. The stock is a
/// flat block whose top sits `stockAllowanceMm` above the relief's maximum;
/// each horizontal slice removes every grid cell whose surface is at or below
/// that level (contiguous X-runs per row), stepping down to Z=0. Coordinate
/// convention: Z=0 is the stock top, surface height h maps to Z = h - stockTop,
/// so all cut depths are negative (consistent with the 2D engines).
public enum HeightfieldRoughEngine {

    public static func compute(
        heightfield: HeightfieldData,
        params: HeightfieldRoughParams
    ) -> HeightfieldToolpathResult {
        let b = heightfield.bounds
        // SPK-1920d (H-304) — inverse mill: the effective surface is flipped
        // (Z vs stock). Normal: stock top sits above the relief max, cutting
        // DOWN to the surface. Inverse: treat each cell's height as its
        // DISTANCE BELOW the stock top (h' = maxHeight - h), so the machine
        // cuts the complement — valleys where the part had peaks. The flip is
        // applied once here; everything downstream (stockTop, levels, run
        // detection) works on the flipped grid unchanged.
        let effective = params.inverseMill ? inverted(heightfield) : heightfield
        let stockTop = effective.maxHeight + params.stockAllowanceMm
        let stepDown = max(0.1, params.stepDownMm)
        let stepOver = max(0.1, params.stepOverMm)

        // Z levels above the stock bottom: stockTop - stepDown … 0, always
        // including a final level at the floor so the grid is fully cleared
        // (the decrement may skip past 0 — append it explicitly).
        var levels: [Double] = []
        var z = stockTop - stepDown
        while z > 0.001 {
            levels.append(z)
            z -= stepDown
        }
        levels.append(0)

        var lines: [String] = ["%", "O=ROUGH_3D"]
        // SPK-1133b — linked spindle RPM from the assigned tool's cut data.
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        // SPK-3D-rest — rest pass header names the prior tool so the G-code
        // documents what the rest is clearing.
        if params.isRestRough {
            lines.append("(Rest Rough: \(String(format: "%.1f", params.toolDiameterMm))mm after \(String(format: "%.1f", params.previousToolDiameterMm))mm, \(levels.count) z-levels)")
        } else {
            lines.append("(Rough: \(String(format: "%.1f", params.toolDiameterMm))mm, \(levels.count) z-levels)")
        }
        var totalLength = 0.0

        for (pass, level) in levels.enumerated() {
            let depthZ = -(stockTop - level)
            lines.append("")
            lines.append("(Pass \(pass + 1)/\(levels.count), Z=\(String(format: "%.3f", depthZ)))")
            lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

            let rowStride = max(1, Int(round(stepOver / effective.cellSizeMm)))
            var row = 0
            while row < effective.height {
                let cy = effective.minY + (Double(row) + 0.5) * effective.cellSizeMm
                // Contiguous runs of cuttable cells in this row. Detection is
                // per-CELL (stride 1): a coarser step would let runs bleed into
                // skipped columns and cut cells above the level.
                var col = 0
                while col < effective.width {
                    // Skip uncut cells (h <= level: the pass plane is above
                    // the surface here, nothing to remove at this Z).
                    while col < effective.width {
                        let cx = effective.minX + (Double(col) + 0.5) * effective.cellSizeMm
                        if effective.heightInterpolated(atX: cx, y: cy) <= level + 1e-9 { break }
                        col += 1
                    }
                    guard col < effective.width else { break }
                    let runStartCol = col
                    var runEndCol = col
                    while runEndCol < effective.width {
                        let cx = effective.minX + (Double(runEndCol) + 0.5) * effective.cellSizeMm
                        if effective.heightInterpolated(atX: cx, y: cy) > level + 1e-9 { break }
                        runEndCol += 1
                    }
                    // SPK-3D-rest: in a rest pass, a run at least as wide as
                    // the previous tool's diameter was already cleared by that
                    // tool — only narrower valleys (which the big tool could
                    // not reach) are cut by the smaller rest tool.
                    let runWidthMm = Double(runEndCol - runStartCol) * effective.cellSizeMm
                    if !params.isRestRough || runWidthMm < params.previousToolDiameterMm - 1e-9 {
                        let x0 = effective.minX + (Double(runStartCol) + 0.5) * effective.cellSizeMm
                        let x1 = effective.minX + (Double(runEndCol - 1) + 0.5) * effective.cellSizeMm
                        lines.append("G0 X\(String(format: "%.3f", x0)) Y\(String(format: "%.3f", cy))")
                        lines.append("G1 Z\(String(format: "%.3f", depthZ)) F\(Int(params.plungeFeedRateMmPerMin))")
                        lines.append("G1 X\(String(format: "%.3f", x1)) Y\(String(format: "%.3f", cy)) F\(Int(params.feedRateMmPerMin))")
                        totalLength += abs(x1 - x0) + params.safeZHeightMm + stockTop - level
                    }
                    col = runEndCol
                }
                row += rowStride
            }
        }

        lines.append("")
        lines.append("M30")
        lines.append("%")
        return HeightfieldToolpathResult(
            gcodeLines: lines,
            estimatedTimeSeconds: totalLength / max(1, params.feedRateMmPerMin) * 60.0,
            passCount: levels.count,
            bounds: b
        )
    }

    /// SPK-1920d — flip the surface: each cell's height becomes its distance
    /// below the original maximum, so peaks become valleys and vice versa.
    private static func inverted(_ hf: HeightfieldData) -> HeightfieldData {
        let maxH = hf.maxHeight
        var heights = hf.heights
        for i in heights.indices { heights[i] = maxH - heights[i] }
        return HeightfieldData(
            width: hf.width,
            height: hf.height,
            cellSizeMm: hf.cellSizeMm,
            minX: hf.minX,
            minY: hf.minY,
            heights: heights
        )
    }
}

// MARK: - Finish engine

/// SPK-3D-spine-b — real surface-following finish from a heightfield. Raster
/// rows at `stepOver` spacing.
/// SPK-2100a — drop-cutter / ball-nose compensation: the G-code traces the
/// tool CENTER, not the surface contact point. For a ball of radius
/// R = D/2 resting on the heightfield at (cx, cy), the center height must
/// satisfy zc >= h(px, py) + sqrt(R^2 - d^2) for every sampled surface point
/// within horizontal reach d <= R. Tracing the bare surface instead overcuts
/// concave valleys by ~R and leaves cusps on convex peaks; with compensation
/// the emitted Z is NOT the surface Z (on a flat it rides +R above).
public enum HeightfieldFinishEngine {

    /// SPK-2100a — relief-space height of the ball CENTER at (cx, cy) so the
    /// ball rests ON the heightfield without gouging: max over grid samples
    /// within horizontal distance R of [surface + sqrt(R^2 - d^2)]. The query
    /// point is always a cell center, so its own sample (d = 0) is included.
    /// R <= 0 degenerates to the raw surface (point cutter).
    static func ballCenterHeight(
        heightfield: HeightfieldData,
        x cx: Double,
        y cy: Double,
        radiusMm R: Double
    ) -> Double {
        let ownHeight = heightfield.heightInterpolated(atX: cx, y: cy)
        guard R > 1e-9 else { return ownHeight }
        let cell = heightfield.cellSizeMm
        let reach = Int(ceil(R / cell))
        let ci = Int((cx - heightfield.minX) / cell)
        let cj = Int((cy - heightfield.minY) / cell)
        var required = -Double.infinity
        let jLo = max(0, cj - reach), jHi = min(heightfield.height - 1, cj + reach)
        let iLo = max(0, ci - reach), iHi = min(heightfield.width - 1, ci + reach)
        if jLo <= jHi && iLo <= iHi {
            for dj in jLo...jHi {
                let py = heightfield.minY + (Double(dj) + 0.5) * cell
                let dy = py - cy
                for di in iLo...iHi {
                    let px = heightfield.minX + (Double(di) + 0.5) * cell
                    let dx = px - cx
                    let d2 = dx * dx + dy * dy
                    if d2 > R * R { continue }
                    let h = heightfield.heightInterpolated(atX: px, y: py)
                    required = max(required, h + (R * R - d2).squareRoot())
                }
            }
        }
        return max(required, ownHeight)
    }

    public static func compute(
        heightfield: HeightfieldData,
        params: HeightfieldFinishParams
    ) -> HeightfieldToolpathResult {
        let b = heightfield.bounds
        let stockTop = heightfield.maxHeight + 0.0 // finish cuts exactly the surface
        let stepOver = max(0.1, params.stepOverMm)
        // SPK-2100a — ball radius R = D/2 drives the drop-cutter offset.
        let ballRadiusMm = max(0, params.toolDiameterMm * 0.5)

        var lines: [String] = ["%", "O=FINISH_3D"]
        // SPK-1133b — linked spindle RPM from the assigned tool's cut data.
        if params.spindleRpm > 0 {
            lines.append("M3 S\(Int(params.spindleRpm))")
        }
        // SPK-2100b — raster angle dispatch. 0 keeps today's Y-lace path
        // BYTE-FOR-BYTE (goldens stay stable, header comment included); any
        // other angle rotates the lace direction (45 diagonal, 90 transposed)
        // and re-runs the same drop-cutter compensation at each sampled XY.
        let rasterAngleDeg = params.snappedRasterAngleDegrees
        if rasterAngleDeg < 0.01 {
            lines.append("(Finish: \(String(format: "%.1f", params.toolDiameterMm))mm ball nose, drop-cutter compensated)")
        } else {
            lines.append("(Finish: \(String(format: "%.1f", params.toolDiameterMm))mm ball nose, drop-cutter compensated, raster \(Int(rasterAngleDeg.rounded()))°)")
        }
        var totalLength = 0.0
        var passCount = 0

        let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))

        if rasterAngleDeg < 0.01 {
        var row = 0
        while row < heightfield.height {
            passCount += 1
            let cy = heightfield.minY + (Double(row) + 0.5) * heightfield.cellSizeMm
            lines.append("")
            lines.append("(Pass \(passCount), Y=\(String(format: "%.3f", cy)))")
            lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

            var first = true
            var prevX = 0.0
            var col = 0
            while col < heightfield.width {
                let cx = heightfield.minX + (Double(col) + 0.5) * heightfield.cellSizeMm
                // SPK-2100a — trace the compensated tool CENTER, not the surface.
                let centerH = ballCenterHeight(
                    heightfield: heightfield, x: cx, y: cy, radiusMm: ballRadiusMm
                )
                let z = -(stockTop - centerH)
                if first {
                    lines.append("G0 X\(String(format: "%.3f", cx)) Y\(String(format: "%.3f", cy))")
                    lines.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeFeedRateMmPerMin))")
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
            // Rotated lace: parallel passes along direction u spaced stepOver
            // apart on the perpendicular n, clipped to the grid rectangle of
            // cell centers. Samples every cell along each pass and traces the
            // SAME ballCenterHeight drop-cutter offset as the 0-degree path,
            // so a 45-degree pass visits diagonal ridges straight rows miss.
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
                    let degLabel = Int(rasterAngleDeg.rounded())
                    lines.append("(Pass \(passCount), raster \(degLabel)deg)")
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
                        let centerH = ballCenterHeight(
                            heightfield: heightfield, x: sx, y: sy, radiusMm: ballRadiusMm
                        )
                        let z = -(stockTop - centerH)
                        if firstPt {
                            lines.append("G0 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy))")
                            lines.append("G1 Z\(String(format: "%.3f", z)) F\(Int(params.plungeFeedRateMmPerMin))")
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
        return HeightfieldToolpathResult(
            gcodeLines: lines,
            estimatedTimeSeconds: totalLength / max(1, params.feedRateMmPerMin) * 60.0,
            passCount: passCount,
            bounds: b
        )
    }
}
