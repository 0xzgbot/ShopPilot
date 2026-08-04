import Foundation

// MARK: - Pocket Toolpath Strategy

/// How the pocket toolpath clears material inside a closed boundary.
public enum PocketClearanceMode: String, Codable, Sendable {
    /// Zigzag pattern (back and forth).
    case zigzag
    /// Spiral outward from center.
    case spiralOut
    /// Follow contours inward (adaptive).
    case adaptive
    
    public var displayName: String {
        switch self {
        case .zigzag: return "Zigzag"
        case .spiralOut: return "Spiral Out"
        case .adaptive: return "Adaptive"
        }
    }
}

// MARK: - Pocket Toolpath Parameters

/// Shared cut-direction enum (Climb/Conventional) — used by Profile and
/// Pocket strategies (installer-verified §R2/§M).
public typealias CutDirection = ProfileCutDirection

/// Edge cleanup timing for pocket clearing (installer-verified M11).
public enum PocketProfilePass: String, Codable, Sendable {
    case first
    case last
    case none

    public var displayName: String {
        switch self {
        case .first: return "First"
        case .last: return "Last"
        case .none: return "No Profile Pass"
        }
    }
}

/// Configuration for a pocket toolpath operation.
public struct PocketToolpathParams: Codable, Sendable {
    
    public var clearanceMode: PocketClearanceMode
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var maxDepthOfCutMm: Double
    public var toolDiameterMm: Double
    public var safetyHeightMm: Double

    // SPK-1133b — linked spindle RPM (0 = not configured; recalc fills it
    // from the assigned tool's cut data and engines emit M3 S).
    public var spindleRpm: Double

    // SPK-1136b — installer-verified §M key set (start depth, pass control,
    // raster angle, profile pass, allowance, ramping). Additive with defaults
    // so existing call sites and persisted documents decode unchanged.
    public var startDepthMm: Double
    public var passCount: Int            // 0 = auto (from maxDepthOfCutMm)
    public var exactStepDepth: Bool
    public var cutDirection: CutDirection
    public var rasterAngleDegrees: Double
    public var profilePass: PocketProfilePass
    public var allowanceMm: Double
    public var rampPlungeMoves: Bool
    public var useVectorSelectionOrder: Bool
    
    /// Minimum pocket size below which the toolpath is skipped.
    public static let minPocketSizeMm = 2.0
    
    public init(
        clearanceMode: PocketClearanceMode = .zigzag,
        stepOverMm: Double = 3.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        maxDepthOfCutMm: Double = 2.0,
        toolDiameterMm: Double = 6.0,
        safetyHeightMm: Double = 5.0,
        spindleRpm: Double = 0,
        startDepthMm: Double = 0.0,
        passCount: Int = 0,
        exactStepDepth: Bool = false,
        cutDirection: CutDirection = .climb,
        rasterAngleDegrees: Double = 0.0,
        profilePass: PocketProfilePass = .last,
        allowanceMm: Double = 0.0,
        rampPlungeMoves: Bool = false,
        useVectorSelectionOrder: Bool = false
    ) {
        self.clearanceMode = clearanceMode
        self.stepOverMm = stepOverMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.toolDiameterMm = toolDiameterMm
        self.safetyHeightMm = safetyHeightMm
        self.spindleRpm = spindleRpm
        self.startDepthMm = startDepthMm
        self.passCount = passCount
        self.exactStepDepth = exactStepDepth
        self.cutDirection = cutDirection
        self.rasterAngleDegrees = rasterAngleDegrees
        self.profilePass = profilePass
        self.allowanceMm = allowanceMm
        self.rampPlungeMoves = rampPlungeMoves
        self.useVectorSelectionOrder = useVectorSelectionOrder
    }
    
    /// Create params from material defaults.
    public static func fromMaterial(_ material: Material, toolDiameter: Double) -> PocketToolpathParams {
        let stepOver = min(toolDiameter * 0.75, 3.0) // 75% of tool diameter or max 3mm
        return PocketToolpathParams(
            clearanceMode: .zigzag,
            stepOverMm: stepOver,
            feedRateMmPerMin: material.maxFeedRateMmPerMin * 0.7,
            plungeFeedRateMmPerMin: material.maxFeedRateMmPerMin * 0.3,
            maxDepthOfCutMm: min(material.maxDepthOfCutMm, toolDiameter),
            toolDiameterMm: toolDiameter,
            safetyHeightMm: 5.0
        )
    }

    // MARK: - Codable (backward-compatible: every key decodes with a default,
    // so documents written before SPK-1136b still load).

    private enum CodingKeys: String, CodingKey {
        case clearanceMode, stepOverMm, feedRateMmPerMin, plungeFeedRateMmPerMin
        case maxDepthOfCutMm, toolDiameterMm, safetyHeightMm
        case spindleRpm
        case startDepthMm, passCount, exactStepDepth, cutDirection
        case rasterAngleDegrees, profilePass, allowanceMm, rampPlungeMoves
        case useVectorSelectionOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clearanceMode = try c.decodeIfPresent(PocketClearanceMode.self, forKey: .clearanceMode) ?? .zigzag
        stepOverMm = try c.decodeIfPresent(Double.self, forKey: .stepOverMm) ?? 3.0
        feedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .feedRateMmPerMin) ?? 1000
        plungeFeedRateMmPerMin = try c.decodeIfPresent(Double.self, forKey: .plungeFeedRateMmPerMin) ?? 300
        maxDepthOfCutMm = try c.decodeIfPresent(Double.self, forKey: .maxDepthOfCutMm) ?? 2.0
        toolDiameterMm = try c.decodeIfPresent(Double.self, forKey: .toolDiameterMm) ?? 6.0
        safetyHeightMm = try c.decodeIfPresent(Double.self, forKey: .safetyHeightMm) ?? 5.0
        spindleRpm = try c.decodeIfPresent(Double.self, forKey: .spindleRpm) ?? 0
        startDepthMm = try c.decodeIfPresent(Double.self, forKey: .startDepthMm) ?? 0.0
        passCount = try c.decodeIfPresent(Int.self, forKey: .passCount) ?? 0
        exactStepDepth = try c.decodeIfPresent(Bool.self, forKey: .exactStepDepth) ?? false
        cutDirection = try c.decodeIfPresent(CutDirection.self, forKey: .cutDirection) ?? .climb
        rasterAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .rasterAngleDegrees) ?? 0.0
        profilePass = try c.decodeIfPresent(PocketProfilePass.self, forKey: .profilePass) ?? .last
        allowanceMm = try c.decodeIfPresent(Double.self, forKey: .allowanceMm) ?? 0.0
        rampPlungeMoves = try c.decodeIfPresent(Bool.self, forKey: .rampPlungeMoves) ?? false
        useVectorSelectionOrder = try c.decodeIfPresent(Bool.self, forKey: .useVectorSelectionOrder) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clearanceMode, forKey: .clearanceMode)
        try c.encode(stepOverMm, forKey: .stepOverMm)
        try c.encode(feedRateMmPerMin, forKey: .feedRateMmPerMin)
        try c.encode(plungeFeedRateMmPerMin, forKey: .plungeFeedRateMmPerMin)
        try c.encode(maxDepthOfCutMm, forKey: .maxDepthOfCutMm)
        try c.encode(toolDiameterMm, forKey: .toolDiameterMm)
        try c.encode(safetyHeightMm, forKey: .safetyHeightMm)
        try c.encode(spindleRpm, forKey: .spindleRpm)
        try c.encode(startDepthMm, forKey: .startDepthMm)
        try c.encode(passCount, forKey: .passCount)
        try c.encode(exactStepDepth, forKey: .exactStepDepth)
        try c.encode(cutDirection, forKey: .cutDirection)
        try c.encode(rasterAngleDegrees, forKey: .rasterAngleDegrees)
        try c.encode(profilePass, forKey: .profilePass)
        try c.encode(allowanceMm, forKey: .allowanceMm)
        try c.encode(rampPlungeMoves, forKey: .rampPlungeMoves)
        try c.encode(useVectorSelectionOrder, forKey: .useVectorSelectionOrder)
    }
}

// MARK: - Pocket Toolpath Result

/// Represents the computed pocket toolpath with G-code segments and metadata.
public struct PocketToolpathResult: Codable, Sendable {
    
    public let params: PocketToolpathParams
    public let material: Material?
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let passCount: Int
    public let pocketAreaMm2: Double
    
    /// Whether the pocket is too small for the tool.
    public var isTooSmall: Bool { pocketAreaMm2 < PocketToolpathParams.minPocketSizeMm * PocketToolpathParams.minPocketSizeMm }
}

// MARK: - Pocket Toolpath Engine

/// Computes pocket toolpaths from closed vector boundaries with zigzag/spiral/adaptive clearing.
public struct PocketToolpathEngine {
    
    /// Compute a pocket toolpath for the given vectors and parameters.
    public static func compute(
        vectors: [VectorPath],
        params: PocketToolpathParams,
        material: Material? = nil,
        stockHeightMm: Double = 25.0
    ) -> PocketToolpathResult {
        
        var allGcodeLines: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin
        
        // Generate G-code header
        allGcodeLines.append("%")
        allGcodeLines.append("O=POCKET_TOOLPATH")
        allGcodeLines.append("(Tool: \(Int(params.toolDiameterMm * 10))mm)")
        // SPK-1133b — linked spindle RPM from the assigned tool's cut data.
        if params.spindleRpm > 0 {
            allGcodeLines.append("M3 S\(Int(params.spindleRpm))")
        }
        
        var totalLength = 0.0
        var maxPassCount = 0
        
        for vector in vectors {
            guard !vector.points.isEmpty && vector.isClosed else { continue }
            
            // Calculate bounding box of the pocket
            let bounds = calculateBounds(vector.points)
            guard let b = bounds else { continue }
            
            let width = b.maxX - b.minX
            let height = b.maxY - b.minY
            
            // Check if pocket is too small for the tool
            if width < params.toolDiameterMm || height < params.toolDiameterMm {
                allGcodeLines.append("(SKIPPED: Pocket too small for \(Int(params.toolDiameterMm * 10))mm tool)")
                continue
            }
            
            // Calculate depth passes
            let passCount = Int(ceil(stockHeightMm / params.maxDepthOfCutMm))
            maxPassCount = max(maxPassCount, passCount)
            
            for pass in 1...passCount {
                let zDepth = -Double(pass) * params.maxDepthOfCutMm
                
                // Add G-code for this pass
                allGcodeLines.append("")
                allGcodeLines.append("(Pocket Pass \(pass)/\(passCount), Z=\(String(format: "%.3f", zDepth)))")
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
                
                switch params.clearanceMode {
                case .zigzag:
                    let zigzagPath = generateZigzagPath(
                        bounds: b,
                        toolDiameter: params.toolDiameterMm,
                        stepOver: params.stepOverMm,
                        points: vector.points,
                        feedRate: feedRate
                    )
                    allGcodeLines.append(contentsOf: insertPlunge(
                        into: zigzagPath,
                        depth: zDepth,
                        plungeFeed: Int(plungeFeed)
                    ))
                    
                case .spiralOut:
                    let spiralPath = generateSpiralPath(
                        bounds: b,
                        toolDiameter: params.toolDiameterMm,
                        stepOver: params.stepOverMm,
                        points: vector.points,
                        feedRate: feedRate
                    )
                    allGcodeLines.append(contentsOf: insertPlunge(
                        into: spiralPath,
                        depth: zDepth,
                        plungeFeed: Int(plungeFeed)
                    ))
                    
                case .adaptive:
                    // Adaptive uses zigzag with boundary clipping for now
                    let adaptivePath = generateZigzagPath(
                        bounds: b,
                        toolDiameter: params.toolDiameterMm,
                        stepOver: params.stepOverMm * 1.5, // Wider stepover for adaptive
                        points: vector.points,
                        feedRate: feedRate
                    )
                    allGcodeLines.append(contentsOf: insertPlunge(
                        into: adaptivePath,
                        depth: zDepth,
                        plungeFeed: Int(plungeFeed)
                    ))
                }
                
                // Rapid to safe height
                allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
            }
            
            totalLength += width * height / max(params.stepOverMm, 1.0)
        }
        
        // Add G-code footer
        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")
        
        // Calculate estimated time (rough approximation)
        let cuttingTime = totalLength / feedRate * 60.0
        
        return PocketToolpathResult(
            params: params,
            material: material,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: cuttingTime,
            passCount: maxPassCount,
            pocketAreaMm2: totalLength * params.stepOverMm
        )
    }
    
    /// Ensure a pass actually descends to depth: inserts a plunge line
    /// (`G1 Z{depth} F{plungeFeed}`) after the path's first positioning move,
    /// or positions + plunges when the generator emits no rapid at all
    /// (SPK-1102h). Without this the tool would traverse the whole pocket in
    /// the air at safety height.
    private static func insertPlunge(
        into path: [String],
        depth: Double,
        plungeFeed: Int
    ) -> [String] {
        var out = path
        let plunge = "G1 Z\(String(format: "%.3f", depth)) F\(plungeFeed)"
        if let rapidIndex = out.firstIndex(where: { $0.hasPrefix("G0") }) {
            // Generator positions first (e.g. spiral's G0 to pocket center):
            // plunge immediately after that rapid, before the first cut move.
            out.insert(plunge, at: rapidIndex + 1)
        } else if let firstCut = out.first(where: { $0.hasPrefix("G1") }) {
            // No positioning move: rapid to the first cut point, then plunge.
            let xy = firstCut
                .split(separator: " ")
                .filter { $0.hasPrefix("X") || $0.hasPrefix("Y") }
                .joined(separator: " ")
            out.insert("G0 \(xy)", at: 0)
            out.insert(plunge, at: 1)
        }
        return out
    }

    /// Generate a zigzag pocket clearing path.
    private static func generateZigzagPath(
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        toolDiameter: Double,
        stepOver: Double,
        points: [VectorPoint],
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        
        let minX = bounds.minX + toolDiameter / 2
        let maxX = bounds.maxX - toolDiameter / 2
        let minY = bounds.minY + toolDiameter / 2
        let maxY = bounds.maxY - toolDiameter / 2
        
        guard maxX > minX && maxY > minY else { return gcodeLines }
        
        var y = minY
        var goingRight = true
        
        while y <= maxY {
            if goingRight {
                // Move right
                gcodeLines.append("G1 X\(String(format: "%.3f", maxX)) Y\(String(format: "%.3f", y)) F\(Int(feedRate))")
            } else {
                // Move left
                gcodeLines.append("G1 X\(String(format: "%.3f", minX)) Y\(String(format: "%.3f", y)) F\(Int(feedRate))")
            }
            
            y += stepOver
            goingRight = !goingRight
            
            // Step down at end of row
            if y <= maxY {
                gcodeLines.append("G1 X\(String(format: "%.3f", goingRight ? minX : maxX)) Y\(String(format: "%.3f", y)) F\(Int(feedRate))")
            }
        }
        
        return gcodeLines
    }
    
    /// Generate a spiral-out pocket clearing path.
    private static func generateSpiralPath(
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        toolDiameter: Double,
        stepOver: Double,
        points: [VectorPoint],
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        
        // Start from center of pocket
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2
        
        // Rapid to start position
        gcodeLines.append("G0 X\(String(format: "%.3f", centerX)) Y\(String(format: "%.3f", centerY))")
        
        // Generate spiral points. Start at the tool radius, clamped so a
        // pocket that fits the tool always emits at least one ring (a 10 mm
        // pocket with a 6 mm tool must still cut — SPK-1102h).
        let maxRadius = min(
            (bounds.maxX - bounds.minX) / 2,
            (bounds.maxY - bounds.minY) / 2
        ) - toolDiameter / 2
        var radius = min(toolDiameter / 2, max(0.5, maxRadius))
        
        while radius <= maxRadius {
            // Generate arc points for this radius; the ring closes back onto
            // its start (angle 0 … 2π) so seams don't leave uncut gaps.
            let numPoints = Int(max(8.0, Double(Int(radius * 10))))
            for i in 0...numPoints {
                let angle = Double(i) / Double(numPoints) * 2.0 * .pi
                let x = centerX + cos(angle) * radius
                let y = centerY + sin(angle) * radius
                gcodeLines.append("G1 X\(String(format: "%.3f", x)) Y\(String(format: "%.3f", y)) F\(Int(feedRate))")
            }
            
            // Expand to next radius
            radius += stepOver / 2.0
        }
        
        return gcodeLines
    }
    
    /// Calculate the bounding box of a set of points.
    private static func calculateBounds(_ points: [VectorPoint]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard !points.isEmpty else { return nil }
        
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        
        return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct PocketToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Pocket toolpath is a non-visual component")
    }
}
#endif
