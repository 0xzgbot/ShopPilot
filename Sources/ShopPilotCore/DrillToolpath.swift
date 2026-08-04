import Foundation

// MARK: - Drill Cycle Type

/// Types of drilling operations supported by ShopPilot.
public enum DrillCycleType: String, Codable, Sendable {
    /// Simple peck drill with retract.
    case peckDrill
    /// Deep hole drilling with multiple pecks and full retract at bottom.
    case deepHolePeck
    /// Spot drilling for center punch location.
    case spotDrill
    /// Counterboring for flat-bottomed holes.
    case counterbore
    /// Countersinking for conical holes.
    case countersink
    
    public var displayName: String {
        switch self {
        case .peckDrill: return "Peck Drill"
        case .deepHolePeck: return "Deep Hole Peck"
        case .spotDrill: return "Spot Drill"
        case .counterbore: return "Counterbore"
        case .countersink: return "Countersink"
        }
    }
}

// MARK: - Drill Point

/// A single drill point with position and depth.
public struct DrillPoint: Codable, Sendable {
    
    /// X coordinate in mm.
    public var x: Double
    
    /// Y coordinate in mm.
    public var y: Double
    
    /// Z depth to drill to (negative value).
    public var zDepthMm: Double
    
    /// Number of dwell seconds at bottom of hole.
    public var dwellSeconds: Double
    
    /// Override feed rate for this point (0 = use default).
    public var overrideFeedRate: Double
    
    public init(
        x: Double,
        y: Double,
        zDepthMm: Double,
        dwellSeconds: Double = 0.0,
        overrideFeedRate: Double = 0.0
    ) {
        self.x = x
        self.y = y
        self.zDepthMm = zDepthMm
        self.dwellSeconds = dwellSeconds
        self.overrideFeedRate = overrideFeedRate
    }
}

// MARK: - Drill Toolpath Parameters

/// Configuration for a drill toolpath operation.
public struct DrillToolpathParams: Codable, Sendable {
    
    public var cycleType: DrillCycleType
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var retractHeightMm: Double
    public var peckDepthMm: Double
    public var toolDiameterMm: Double
    
    /// Safety height above workpiece.
    public var safetyHeightMm: Double
    
    public init(
        cycleType: DrillCycleType = .peckDrill,
        feedRateMmPerMin: Double = 1000,
        plungeFeedRateMmPerMin: Double = 300,
        retractHeightMm: Double = 5.0,
        peckDepthMm: Double = 2.0,
        toolDiameterMm: Double = 6.0,
        safetyHeightMm: Double = 10.0
    ) {
        self.cycleType = cycleType
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.retractHeightMm = retractHeightMm
        self.peckDepthMm = peckDepthMm
        self.toolDiameterMm = toolDiameterMm
        self.safetyHeightMm = safetyHeightMm
    }
    
    /// Create params from material defaults.
    public static func fromMaterial(_ material: Material, toolDiameter: Double) -> DrillToolpathParams {
        return DrillToolpathParams(
            cycleType: .peckDrill,
            feedRateMmPerMin: material.maxFeedRateMmPerMin * 0.5, // Drills slower than milling
            plungeFeedRateMmPerMin: material.maxFeedRateMmPerMin * 0.2,
            retractHeightMm: 5.0,
            peckDepthMm: min(toolDiameter, 3.0),
            toolDiameterMm: toolDiameter,
            safetyHeightMm: 10.0
        )
    }
}

// MARK: - Drill Toolpath Result

/// Represents the computed drill toolpath with G-code segments and metadata.
public struct DrillToolpathResult: Codable, Sendable {
    
    public let params: DrillToolpathParams
    public let material: Material?
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let pointCount: Int
    
    /// Total drilling depth across all points.
    public var totalDrillDepthMm: Double {
        // Approximation based on deepest point
        return 0.0 // Will be calculated during generation
    }
}

// MARK: - Drill Toolpath Engine

/// Computes drill toolpaths from a set of drill points with configurable cycle types.
public struct DrillToolpathEngine {
    
    /// Compute a drill toolpath for the given points and parameters.
    public static func compute(
        points: [DrillPoint],
        params: DrillToolpathParams,
        material: Material? = nil,
        stockHeightMm: Double = 25.0
    ) -> DrillToolpathResult {
        
        var allGcodeLines: [String] = []
        let feedRate = params.feedRateMmPerMin
        let plungeFeed = params.plungeFeedRateMmPerMin
        
        // Generate G-code header
        allGcodeLines.append("%")
        allGcodeLines.append("O=DRILL_TOOLPATH")
        allGcodeLines.append("(Tool: \(Int(params.toolDiameterMm * 10))mm)")
        allGcodeLines.append("(Cycle: \(params.cycleType.displayName))")
        
        var totalDrillDepth = 0.0
        
        for (index, point) in points.enumerated() {
            // Rapid to safe height
            allGcodeLines.append("")
            allGcodeLines.append("(Point \(index + 1)/\(points.count): X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y)))")
            
            // Move to position with rapid
            allGcodeLines.append("G0 X\(String(format: "%.3f", point.x)) Y\(String(format: "%.3f", point.y))")
            
            // Rapid to safety height
            allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
            
            switch params.cycleType {
            case .peckDrill:
                let peckPath = generatePeckDrill(
                    point: point,
                    params: params,
                    plungeFeed: plungeFeed,
                    feedRate: feedRate
                )
                allGcodeLines.append(contentsOf: peckPath)
                
            case .deepHolePeck:
                let deepPath = generateDeepHolePeck(
                    point: point,
                    params: params,
                    plungeFeed: plungeFeed,
                    feedRate: feedRate
                )
                allGcodeLines.append(contentsOf: deepPath)
                
            case .spotDrill:
                let spotPath = generateSpotDrill(
                    point: point,
                    params: params,
                    plungeFeed: plungeFeed,
                    feedRate: feedRate
                )
                allGcodeLines.append(contentsOf: spotPath)
                
            case .counterbore:
                let counterPath = generateCounterbore(
                    point: point,
                    params: params,
                    plungeFeed: plungeFeed,
                    feedRate: feedRate
                )
                allGcodeLines.append(contentsOf: counterPath)
                
            case .countersink:
                let counterSinkPath = generateCountersink(
                    point: point,
                    params: params,
                    plungeFeed: plungeFeed,
                    feedRate: feedRate
                )
                allGcodeLines.append(contentsOf: counterSinkPath)
            }
            
            // Rapid to safe height after each hole
            allGcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
            
            totalDrillDepth += abs(point.zDepthMm)
        }
        
        // Add G-code footer
        allGcodeLines.append("")
        allGcodeLines.append("M30")
        allGcodeLines.append("%")
        
        return DrillToolpathResult(
            params: params,
            material: material,
            gcodeLines: allGcodeLines,
            estimatedTimeSeconds: totalDrillDepth / plungeFeed * 60.0 + Double(points.count) * 2.0, // Add 2s per hole for positioning
            pointCount: points.count
        )
    }
    
    /// Generate peck drill cycle G-code.
    private static func generatePeckDrill(
        point: DrillPoint,
        params: DrillToolpathParams,
        plungeFeed: Double,
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        let peckDepth = params.peckDepthMm
        let totalDepth = abs(point.zDepthMm)
        let retractHeight = params.retractHeightMm
        
        // Zero/negative peck depth would divide by zero below — fall back to a
        // single exact plunge (SPK-1102i Test 5).
        guard peckDepth > 0 else {
            gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
            if point.dwellSeconds > 0 {
                gcodeLines.append("G4 P\(point.dwellSeconds)")
            }
            return gcodeLines
        }
        
        // Calculate number of pecks needed
        let numPecks = Int(ceil(totalDepth / peckDepth))
        
        for peck in 1...numPecks {
            let currentDepth = -Double(peck) * peckDepth
            
            if abs(currentDepth) >= totalDepth {
                // Final pass to full depth
                gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
                
                // Dwell at bottom if specified
                if point.dwellSeconds > 0 {
                    gcodeLines.append("G4 P\(point.dwellSeconds)")
                }
            } else {
                // Peck to this depth and retract
                gcodeLines.append("G1 Z\(String(format: "%.3f", currentDepth)) F\(Int(plungeFeed))")
                gcodeLines.append("G0 Z\(String(format: "%.1f", retractHeight))")
            }
        }
        
        return gcodeLines
    }
    
    /// Generate deep hole peck cycle G-code with full retract at bottom.
    private static func generateDeepHolePeck(
        point: DrillPoint,
        params: DrillToolpathParams,
        plungeFeed: Double,
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        let peckDepth = params.peckDepthMm
        let totalDepth = abs(point.zDepthMm)
        let retractHeight = params.retractHeightMm
        
        // Zero/negative peck depth would divide by zero below — fall back to a
        // single exact plunge (SPK-1102i Test 5).
        guard peckDepth > 0 else {
            gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
            if point.dwellSeconds > 0 {
                gcodeLines.append("G4 P\(point.dwellSeconds)")
            }
            return gcodeLines
        }
        
        // Calculate number of pecks needed
        let numPecks = Int(ceil(totalDepth / peckDepth))
        
        for peck in 1...numPecks {
            let currentDepth = -Double(peck) * peckDepth
            
            if abs(currentDepth) >= totalDepth {
                // Final pass to full depth with dwell
                gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
                
                if point.dwellSeconds > 0 {
                    gcodeLines.append("G4 P\(point.dwellSeconds)")
                }
            } else {
                // Peck to this depth and fully retract
                gcodeLines.append("G1 Z\(String(format: "%.3f", currentDepth)) F\(Int(plungeFeed))")
                gcodeLines.append("G0 Z\(String(format: "%.1f", params.safetyHeightMm))")
            }
        }
        
        return gcodeLines
    }
    
    /// Generate spot drill cycle G-code.
    private static func generateSpotDrill(
        point: DrillPoint,
        params: DrillToolpathParams,
        plungeFeed: Double,
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        
        // Spot drill only needs to go shallow (typically 10-20% of full depth)
        let spotDepth = point.zDepthMm * 0.15
        
        gcodeLines.append("G1 Z\(String(format: "%.3f", spotDepth)) F\(Int(plungeFeed))")
        
        // Brief dwell to create center punch
        if point.dwellSeconds > 0 {
            gcodeLines.append("G4 P\(point.dwellSeconds)")
        } else {
            gcodeLines.append("G4 P0.5") // Default 0.5s dwell for spot drilling
        }
        
        return gcodeLines
    }
    
    /// Generate counterbore cycle G-code.
    private static func generateCounterbore(
        point: DrillPoint,
        params: DrillToolpathParams,
        plungeFeed: Double,
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        
        // Counterbore goes to full depth with dwell at bottom for flat surface
        gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
        
        if point.dwellSeconds > 0 {
            gcodeLines.append("G4 P\(point.dwellSeconds)")
        } else {
            gcodeLines.append("G4 P1.0") // Default 1s dwell for counterboring
        }
        
        return gcodeLines
    }
    
    /// Generate countersink cycle G-code.
    private static func generateCountersink(
        point: DrillPoint,
        params: DrillToolpathParams,
        plungeFeed: Double,
        feedRate: Double
    ) -> [String] {
        
        var gcodeLines: [String] = []
        
        // Countersink goes to full depth with dwell at bottom
        gcodeLines.append("G1 Z\(String(format: "%.3f", point.zDepthMm)) F\(Int(plungeFeed))")
        
        if point.dwellSeconds > 0 {
            gcodeLines.append("G4 P\(point.dwellSeconds)")
        } else {
            gcodeLines.append("G4 P0.5") // Default 0.5s dwell for countersinking
        }
        
        return gcodeLines
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct DrillToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Drill toolpath is a non-visual component")
    }
}
#endif
