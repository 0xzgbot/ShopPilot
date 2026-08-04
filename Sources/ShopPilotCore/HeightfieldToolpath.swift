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

    public init(
        toolDiameterMm: Double = 6.0,
        stepDownMm: Double = 2.0,
        stepOverMm: Double = 1.5,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safeZHeightMm: Double = 5.0,
        stockAllowanceMm: Double = 0.5
    ) {
        self.toolDiameterMm = toolDiameterMm
        self.stepDownMm = stepDownMm
        self.stepOverMm = stepOverMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safeZHeightMm = safeZHeightMm
        self.stockAllowanceMm = stockAllowanceMm
    }
}

/// Surface-following finish params for the heightfield finish engine.
public struct HeightfieldFinishParams: Codable, Sendable, ToolFeedApplicable {
    public var toolDiameterMm: Double
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var safeZHeightMm: Double

    public init(
        toolDiameterMm: Double = 3.175,
        stepOverMm: Double = 0.8,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safeZHeightMm: Double = 5.0
    ) {
        self.toolDiameterMm = toolDiameterMm
        self.stepOverMm = stepOverMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safeZHeightMm = safeZHeightMm
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
        let stockTop = heightfield.maxHeight + params.stockAllowanceMm
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
        lines.append("(Rough: \(String(format: "%.1f", params.toolDiameterMm))mm, \(levels.count) z-levels)")
        var totalLength = 0.0

        for (pass, level) in levels.enumerated() {
            let depthZ = -(stockTop - level)
            lines.append("")
            lines.append("(Pass \(pass + 1)/\(levels.count), Z=\(String(format: "%.3f", depthZ)))")
            lines.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

            let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
            var row = 0
            while row < heightfield.height {
                let cy = heightfield.minY + (Double(row) + 0.5) * heightfield.cellSizeMm
                // Contiguous runs of cuttable cells in this row. Detection is
                // per-CELL (stride 1): a coarser step would let runs bleed into
                // skipped columns and cut cells above the level.
                var col = 0
                while col < heightfield.width {
                    // Skip uncut cells.
                    while col < heightfield.width {
                        let cx = heightfield.minX + (Double(col) + 0.5) * heightfield.cellSizeMm
                        if heightfield.heightInterpolated(atX: cx, y: cy) <= level + 1e-9 { break }
                        col += 1
                    }
                    guard col < heightfield.width else { break }
                    let runStartCol = col
                    var runEndCol = col
                    while runEndCol < heightfield.width {
                        let cx = heightfield.minX + (Double(runEndCol) + 0.5) * heightfield.cellSizeMm
                        if heightfield.heightInterpolated(atX: cx, y: cy) > level + 1e-9 { break }
                        runEndCol += 1
                    }
                    let x0 = heightfield.minX + (Double(runStartCol) + 0.5) * heightfield.cellSizeMm
                    let x1 = heightfield.minX + (Double(runEndCol - 1) + 0.5) * heightfield.cellSizeMm
                    lines.append("G0 X\(String(format: "%.3f", x0)) Y\(String(format: "%.3f", cy))")
                    lines.append("G1 Z\(String(format: "%.3f", depthZ)) F\(Int(params.plungeFeedRateMmPerMin))")
                    lines.append("G1 X\(String(format: "%.3f", x1)) Y\(String(format: "%.3f", cy)) F\(Int(params.feedRateMmPerMin))")
                    totalLength += abs(x1 - x0) + params.safeZHeightMm + stockTop - level
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
}

// MARK: - Finish engine

/// SPK-3D-spine-b — real surface-following finish from a heightfield. Raster
/// rows at `stepOver` spacing; along each row the Z axis follows the bilinear
/// heightfield surface (Z = h - stockTop), so the tool skims the relief.
public enum HeightfieldFinishEngine {

    public static func compute(
        heightfield: HeightfieldData,
        params: HeightfieldFinishParams
    ) -> HeightfieldToolpathResult {
        let b = heightfield.bounds
        let stockTop = heightfield.maxHeight + 0.0 // finish cuts exactly the surface
        let stepOver = max(0.1, params.stepOverMm)

        var lines: [String] = ["%", "O=FINISH_3D"]
        lines.append("(Finish: \(String(format: "%.1f", params.toolDiameterMm))mm ball nose)")
        var totalLength = 0.0
        var row = 0
        var passCount = 0

        let rowStride = max(1, Int(round(stepOver / heightfield.cellSizeMm)))
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
                let h = heightfield.heightInterpolated(atX: cx, y: cy)
                let z = -(stockTop - h)
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
