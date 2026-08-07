import Foundation

// MARK: - Drill Bank (parity matrix F34)

/// Drill-point style for a Drill Bank: "through" reaches the full cut depth;
/// "brad-point" stops short (0.8× depth) so the center point of a brad-point
/// bit seats before the flutes engage — the installer-verified behavior the
/// reference form exposes ("through/brad-point").
public enum DrillBankPointStyle: String, Codable, Sendable {
    case through
    case bradPoint

    public var displayName: String {
        switch self {
        case .through: return "Through"
        case .bradPoint: return "Brad-point"
        }
    }
}

// MARK: - Drill Bank Parameters

/// A rectangular grid of drill holes (columns × rows at a spacing), with
/// unique per-hole numbers. Mirrors `DrillToolpathParams` conventions
/// (legacy-safe additive fields via custom Codable so stored paramsJSON
/// decodes unchanged).
public struct DrillBankToolpathParams: Codable, Sendable {
    public var gridCols: Int
    public var gridRows: Int
    public var spacingX: Double
    public var spacingY: Double
    public var originX: Double
    public var originY: Double
    public var toolDiameterMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var safetyHeightMm: Double
    public var cutDepthMm: Double
    public var style: DrillBankPointStyle

    /// SPK-1133b — linked spindle RPM (0 = not configured; recalc fills it
    /// from the assigned tool's cut data and the engine emits M3 S).
    public var spindleRpm: Double

    public init(
        gridCols: Int = 3,
        gridRows: Int = 2,
        spacingX: Double = 20.0,
        spacingY: Double = 25.0,
        originX: Double = 0.0,
        originY: Double = 0.0,
        toolDiameterMm: Double = 6.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        safetyHeightMm: Double = 10.0,
        cutDepthMm: Double = 10.0,
        style: DrillBankPointStyle = .through,
        spindleRpm: Double = 0
    ) {
        self.gridCols = gridCols
        self.gridRows = gridRows
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.originX = originX
        self.originY = originY
        self.toolDiameterMm = toolDiameterMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.safetyHeightMm = safetyHeightMm
        self.cutDepthMm = cutDepthMm
        self.style = style
        self.spindleRpm = spindleRpm
    }

    /// Create params from material defaults (drill slower than milling).
    public static func fromMaterial(_ material: Material, toolDiameter: Double) -> DrillBankToolpathParams {
        DrillBankToolpathParams(
            toolDiameterMm: toolDiameter,
            feedRateMmPerMin: material.maxFeedRateMmPerMin * 0.5,
            plungeFeedRateMmPerMin: material.maxFeedRateMmPerMin * 0.2
        )
    }

    /// Generate the grid of drill positions. Row-major: column index changes
    /// fastest (col 0..cols-1 at row 0, then row 1, …).
    public func gridPoints() -> [DrillPoint] {
        var points: [DrillPoint] = []
        for row in 0..<max(gridRows, 1) {
            for col in 0..<max(gridCols, 1) {
                points.append(DrillPoint(
                    x: originX + Double(col) * spacingX,
                    y: originY + Double(row) * spacingY,
                    zDepthMm: -cutDepthMm
                ))
            }
        }
        return points
    }
}

// MARK: - Drill Bank Result

/// Computed drill-bank toolpath with G-code and metadata.
public struct DrillBankToolpathResult: Codable, Sendable {
    public let params: DrillBankToolpathParams
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let pointCount: Int

    public init(
        params: DrillBankToolpathParams,
        gcodeLines: [String],
        estimatedTimeSeconds: Double,
        pointCount: Int
    ) {
        self.params = params
        self.gcodeLines = gcodeLines
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.pointCount = pointCount
    }
}

// MARK: - Drill Bank Engine

/// Computes a drill-bank toolpath: a W×H grid of uniquely-numbered holes.
/// Each hole: rapid to position, rapid to safety height, plunge to depth
/// (through = full cutDepth; brad-point = 0.8×cutDepth), retract to safety.
public struct DrillBankToolpathEngine {

    /// Compute the drill-bank G-code. When `points` is non-empty it overrides
    /// the generated grid (callers may feed a custom point list).
    public static func compute(
        points: [DrillPoint]? = nil,
        params: DrillBankToolpathParams,
        stockHeightMm: Double = 25.0
    ) -> DrillBankToolpathResult {
        let drillPoints = (points?.isEmpty == false) ? points! : params.gridPoints()
        let plungeFeed = params.plungeFeedRateMmPerMin
        let plungeDepth = params.cutDepthMm

        var allGcodeLines: [String] = []
        allGcodeLines.append("%")
        allGcodeLines.append("O=DRILL_BANK_TOOLPATH")
        allGcodeLines.append("(Drill Bank: \(params.gridCols)x\(params.gridRows) grid — \(drillPoints.count) holes)")
        allGcodeLines.append("(Tool: \(Int(params.toolDiameterMm * 10))mm)")
        allGcodeLines.append("(Style: \(params.style.displayName))")
        if params.spindleRpm > 0 {
            allGcodeLines.append("M3 S\(Int(params.spindleRpm))")
        }

        for (index, point) in drillPoints.enumerated() {
            let holeNumber = index + 1
            allGcodeLines.append("")
            allGcodeLines.append("(Hole \(holeNumber)/\(drillPoints.count): X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)))")
            allGcodeLines.append("G0 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y))")
            allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")

            let targetDepth: Double
            switch params.style {
            case .through:
                targetDepth = -plungeDepth
            case .bradPoint:
                targetDepth = -plungeDepth * 0.8
                allGcodeLines.append("(Brad-point: seats the center point at \(String(format: "%.1f", plungeDepth * 0.8))mm — full depth \(String(format: "%.1f", plungeDepth))mm)")
            }
            allGcodeLines.append("G1 Z\(String(format: "%.3f", targetDepth)) F\(Int(plungeFeed))")
            allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
        }

        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")

        let totalDrillDepth = Double(drillPoints.count) * plungeDepth
        let estimatedTimeSeconds = totalDrillDepth / plungeFeed * 60.0 + Double(drillPoints.count) * 2.0

        return DrillBankToolpathResult(
            params: params,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: estimatedTimeSeconds,
            pointCount: drillPoints.count
        )
    }
}
