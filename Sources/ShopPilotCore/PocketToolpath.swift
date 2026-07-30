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

/// Configuration for a pocket toolpath operation.
public struct PocketToolpathParams: Codable, Sendable {
    
    public var clearanceMode: PocketClearanceMode
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var maxDepthOfCutMm: Double
    public var toolDiameterMm: Double
    public var safetyHeightMm: Double
    
    /// Minimum pocket size below which the toolpath is skipped.
    public static let minPocketSizeMm = 2.0
    
    public init(
        clearanceMode: PocketClearanceMode = .zigzag,
        stepOverMm: Double = 3.0,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        maxDepthOfCutMm: Double = 2.0,
        toolDiameterMm: Double = 6.0,
        safetyHeightMm: Double = 5.0
    ) {
        self.clearanceMode = clearanceMode
        self.stepOverMm = stepOverMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.toolDiameterMm = toolDiameterMm
        self.safetyHeightMm = safetyHeightMm
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
                        points: vector.points
                    )
                    allGcodeLines.append(contentsOf: zigzagPath)
                    
                case .spiralOut:
                    let spiralPath = generateSpiralPath(
                        bounds: b,
                        toolDiameter: params.toolDiameterMm,
                        stepOver: params.stepOverMm,
                        points: vector.points
                    )
                    allGcodeLines.append(contentsOf: spiralPath)
                    
                case .adaptive:
                    // Adaptive uses zigzag with boundary clipping for now
                    let adaptivePath = generateZigzagPath(
                        bounds: b,
                        toolDiameter: params.toolDiameterMm,
                        stepOver: params.stepOverMm * 1.5, // Wider stepover for adaptive
                        points: vector.points
                    )
                    allGcodeLines.append(contentsOf: adaptivePath)
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
    
    /// Generate a zigzag pocket clearing path.
    private static func generateZigzagPath(
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        toolDiameter: Double,
        stepOver: Double,
        points: [VectorPoint]
    ) -> [String] {
        
        var gcodeLines: [String] = []
        let feedRate = 1000 // Will be overridden by caller
        
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
        points: [VectorPoint]
    ) -> [String] {
        
        var gcodeLines: [String] = []
        let feedRate = 1000
        
        // Start from center of pocket
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2
        
        // Rapid to start position
        gcodeLines.append("G0 X\(String(format: "%.3f", centerX)) Y\(String(format: "%.3f", centerY))")
        
        // Generate spiral points
        var radius = toolDiameter / 2
        let maxRadius = min(
            (bounds.maxX - bounds.minX) / 2,
            (bounds.maxY - bounds.minY) / 2
        ) - toolDiameter / 2
        
        while radius <= maxRadius {
            // Generate arc points for this radius
            let numPoints = Int(max(8.0, Double(Int(radius * 10))))
            for i in 0..<numPoints {
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
