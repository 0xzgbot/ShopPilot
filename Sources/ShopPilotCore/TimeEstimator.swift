import Foundation

// MARK: - Time Estimate Result

/// Result of a time estimation calculation.
public struct TimeEstimateResult {
    
    /// Estimated cutting time in seconds (actual material removal).
    public let cuttingTimeSeconds: Double
    
    /// Estimated rapid/travel time in seconds (non-cutting moves).
    public let travelTimeSeconds: Double
    
    /// Estimated total time including setup and tool changes.
    public let totalTimeSeconds: Double
    
    /// Number of depth passes required.
    public let passCount: Int
    
    /// Total distance to be traveled in mm.
    public let totalDistanceMm: Double
    
    /// Cutting distance in mm.
    public let cuttingDistanceMm: Double
    
    /// Travel distance in mm (rapid moves).
    public let travelDistanceMm: Double
    
    /// Estimated time in human-readable format.
    public var formattedCuttingTime: String {
        formatDuration(cuttingTimeSeconds)
    }
    
    public var formattedTravelTime: String {
        formatDuration(travelTimeSeconds)
    }
    
    public var formattedTotalTime: String {
        formatDuration(totalTimeSeconds)
    }
    
    /// Whether the estimate is rough (low confidence).
    public var isRough: Bool { true }
    
    private func formatDuration(_ seconds: Double) -> String {
        // Guard non-finite/negative inputs: feedRate 0 makes estimate() yield
        // inf, and Int(inf) traps (crash). Show "—" instead.
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Time Estimator

/// Rough time estimation for toolpath operations.
public struct TimeEstimator {
    
    /// Estimate time for a set of G-code lines.
    public static func estimate(gcodeLines: [String], feedRateMmPerMin: Double = 1000, rapidRateMmPerMin: Double = 5000) -> TimeEstimateResult {
        var cuttingDistance = 0.0
        var travelDistance = 0.0
        let totalDistance = gcodeLines.reduce(0.0) { $0 + Double($1.count) * 0.1 } // Rough approximation
        
        var lastX: Double?
        var lastY: Double?
        var isCutting = false
        var passCount = 0
        
        for line in gcodeLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.hasPrefix("(") || trimmed.isEmpty || trimmed.hasPrefix("%") || trimmed.hasPrefix("O=") {
                continue
            }
            
            var xCoord: Double?
            var yCoord: Double?
            var zCoord: Double?
            
            let components = trimmed.components(separatedBy: " ")
            
            for component in components {
                if component.hasPrefix("X") {
                    xCoord = Double(component.dropFirst())
                } else if component.hasPrefix("Y") {
                    yCoord = Double(component.dropFirst())
                } else if component.hasPrefix("Z") {
                    zCoord = Double(component.dropFirst())
                }
            }
            
            // Detect depth passes by Z changes
            if let z = zCoord, z < 0 {
                passCount += 1
            }
            
            // Determine if this is a cutting move or rapid travel
            if trimmed.hasPrefix("G1 ") {
                isCutting = true
            } else if trimmed.hasPrefix("G0 ") {
                isCutting = false
            }
            
            // Calculate distance moved
            if let x = xCoord, let y = yCoord {
                if let lastX = lastX, let lastY = lastY {
                    let dx = x - lastX
                    let dy = y - lastY
                    let distance = sqrt(dx * dx + dy * dy)
                    
                    if isCutting {
                        cuttingDistance += distance
                    } else {
                        travelDistance += distance
                    }
                }
                
                lastX = x
                lastY = y
            }
        }
        
        // Calculate times
        let cuttingTimeSeconds = cuttingDistance / feedRateMmPerMin * 60.0
        let travelTimeSeconds = travelDistance / rapidRateMmPerMin * 60.0
        
        // Add overhead for setup, tool changes, etc. (15% of total)
        let baseTime = cuttingTimeSeconds + travelTimeSeconds
        let totalTimeSeconds = baseTime * 1.15
        
        return TimeEstimateResult(
            cuttingTimeSeconds: cuttingTimeSeconds,
            travelTimeSeconds: travelTimeSeconds,
            totalTimeSeconds: totalTimeSeconds,
            passCount: max(passCount, 1),
            totalDistanceMm: cuttingDistance + travelDistance,
            cuttingDistanceMm: cuttingDistance,
            travelDistanceMm: travelDistance
        )
    }
    
    /// Estimate time for a toolpath result.
    public static func estimate(from result: any ToolpathCalculator) -> TimeEstimateResult {
        // This would require the actual G-code output from the calculator
        // For now, return a rough estimate based on estimated time
        let cuttingTime = result.estimatedTimeSeconds
        let travelTime = cuttingTime * 0.2 // Assume 20% travel overhead
        
        return TimeEstimateResult(
            cuttingTimeSeconds: cuttingTime,
            travelTimeSeconds: travelTime,
            totalTimeSeconds: cuttingTime + travelTime,
            passCount: 1,
            totalDistanceMm: 0.0,
            cuttingDistanceMm: 0.0,
            travelDistanceMm: 0.0
        )
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct TimeEstimator_Previews: PreviewProvider {
    static var previews: some View {
        Text("Time estimator is a non-visual component")
    }
}
#endif
