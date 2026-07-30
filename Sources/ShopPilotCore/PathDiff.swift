import Foundation

// MARK: - Path Diff Result

/// Result of comparing two toolpaths for visual diffing.
public struct PathDiffResult {
    
    /// Points that are new in the updated path.
    public let addedPoints: [(x: Double, y: Double)]
    
    /// Points that were removed from the original path.
    public let removedPoints: [(x: Double, y: Double)]
    
    /// Points that moved between paths.
    public let movedPoints: [(original: (x: Double, y: Double), updated: (x: Double, y: Double))]
    
    /// Points that are unchanged.
    public let unchangedPointCount: Int
    
    /// Total number of points in the original path.
    public let originalPointCount: Int
    
    /// Total number of points in the updated path.
    public let updatedPointCount: Int
    
    /// Whether there are any differences.
    public var hasDifferences: Bool {
        !addedPoints.isEmpty || !removedPoints.isEmpty || !movedPoints.isEmpty
    }
    
    /// Summary string for UI display.
    public var summary: String {
        var parts: [String] = []
        if !addedPoints.isEmpty { parts.append("+\(addedPoints.count)") }
        if !removedPoints.isEmpty { parts.append("-\(removedPoints.count)") }
        if !movedPoints.isEmpty { parts.append("~\(movedPoints.count) moved") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Ghost Path Style

/// Visual style for ghost diff rendering.
public struct GhostPathStyle {
    
    /// Color for added points/paths.
    public var addedColor: Color
    
    /// Color for removed points/paths.
    public var removedColor: Color
    
    /// Color for moved points/paths.
    public var movedColor: Color
    
    /// Opacity of the ghost (original) path.
    public var ghostOpacity: Double
    
    /// Line width for diff visualization.
    public var lineWidth: Double
    
    public init(
        addedColor: Color = .green,
        removedColor: Color = .red,
        movedColor: Color = .yellow,
        ghostOpacity: Double = 0.3,
        lineWidth: Double = 2.0
    ) {
        self.addedColor = addedColor
        self.removedColor = removedColor
        self.movedColor = movedColor
        self.ghostOpacity = ghostOpacity
        self.lineWidth = lineWidth
    }
}

// MARK: - Path Diff Engine

/// Compares two toolpaths and generates a visual diff for ghost rendering.
public struct PathDiffEngine {
    
    /// Compare two sets of path points and return the diff result.
    public static func comparePaths(
        original: [(x: Double, y: Double)],
        updated: [(x: Double, y: Double)]
    ) -> PathDiffResult {
        
        let originalPointCount = original.count
        let updatedPointCount = updated.count
        
        var addedPoints: [(x: Double, y: Double)] = []
        var removedPoints: [(x: Double, y: Double)] = []
        var movedPoints: [(original: (x: Double, y: Double), updated: (x: Double, y: Double))] = []
        
        // Simple point-by-point comparison with tolerance for movement detection
        let tolerance: Double = 0.1 // mm
        
        for i in 0..<min(originalPointCount, updatedPointCount) {
            let orig = original[i]
            let upd = updated[i]
            
            let dx = abs(orig.x - upd.x)
            let dy = abs(orig.y - upd.y)
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance < tolerance {
                // Points are essentially the same (unchanged)
                continue
            } else if distance > 0 {
                // Point moved
                movedPoints.append((orig, upd))
            }
        }
        
        // Extra points in updated path = added
        if updatedPointCount > originalPointCount {
            for i in originalPointCount..<updatedPointCount {
                addedPoints.append(updated[i])
            }
        }
        
        // Missing points in updated path = removed
        if originalPointCount > updatedPointCount {
            for i in updatedPointCount..<originalPointCount {
                removedPoints.append(original[i])
            }
        }
        
        let unchangedPointCount = min(originalPointCount, updatedPointCount) - movedPoints.count
        
        return PathDiffResult(
            addedPoints: addedPoints,
            removedPoints: removedPoints,
            movedPoints: movedPoints,
            unchangedPointCount: max(unchangedPointCount, 0),
            originalPointCount: originalPointCount,
            updatedPointCount: updatedPointCount
        )
    }
    
    /// Generate ghost rendering data from a diff result.
    public static func generateGhostData(from diff: PathDiffResult) -> (
        addedPoints: [(x: Double, y: Double)],
        removedPoints: [(x: Double, y: Double)],
        movedLines: [(start: (x: Double, y: Double), end: (x: Double, y: Double))]
    ) {
        
        var movedLines: [(start: (x: Double, y: Double), end: (x: Double, y: Double))] = []
        
        for move in diff.movedPoints {
            movedLines.append((move.original, move.updated))
        }
        
        return (diff.addedPoints, diff.removedPoints, movedLines)
    }
    
    /// Compare two toolpath results by their G-code output.
    public static func compareGCode(_ original: String, _ updated: String) -> PathDiffResult {
        // Parse X,Y coordinates from both G-code strings
        let origPoints = parseCoordinates(from: original)
        let updPoints = parseCoordinates(from: updated)
        
        return comparePaths(original: origPoints, updated: updPoints)
    }
    
    /// Extract X,Y coordinates from G-code lines.
    private static func parseCoordinates(from gcode: String) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        
        let lines = gcode.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip non-movement lines
            if !trimmed.hasPrefix("G0 ") && !trimmed.hasPrefix("G1 ") {
                continue
            }
            
            var xCoord: Double?
            var yCoord: Double?
            
            let components = trimmed.components(separatedBy: " ")
            
            for component in components {
                if component.hasPrefix("X") {
                    xCoord = Double(component.dropFirst())
                } else if component.hasPrefix("Y") {
                    yCoord = Double(component.dropFirst())
                }
            }
            
            if let x = xCoord, let y = yCoord {
                points.append((x, y))
            }
        }
        
        return points
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct PathDiffEngine_Previews: PreviewProvider {
    static var previews: some View {
        Text("Path diff engine is a non-visual component")
    }
}
#endif
