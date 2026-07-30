import Foundation

// MARK: - Heightmap Data Structure

/// A 2D grid representing material heights for simulation.
public struct Heightmap {
    
    /// Width of the heightmap in cells.
    public let width: Int
    
    /// Height of the heightmap in cells.
    public let height: Int
    
    /// Cell size in mm.
    public let cellSizeMm: Double
    
    /// Height data (row-major order).
    var data: [Double]
    
    /// Minimum X coordinate of the heightmap area.
    public let minX: Double
    
    /// Minimum Y coordinate of the heightmap area.
    public let minY: Double
    
    init(width: Int, height: Int, cellSizeMm: Double, minX: Double, minY: Double, initialHeight: Double = 0.0) {
        self.width = width
        self.height = height
        self.cellSizeMm = cellSizeMm
        self.minX = minX
        self.minY = minY
        self.data = Array(repeating: initialHeight, count: width * height)
    }
    
    /// Get the height at a grid position.
    public func getHeight(_ x: Int, _ y: Int) -> Double {
        guard x >= 0 && x < width && y >= 0 && y < height else { return 0.0 }
        return data[y * width + x]
    }
    
    /// Set the height at a grid position.
    public mutating func setHeight(_ value: Double, _ x: Int, _ y: Int) {
        guard x >= 0 && x < width && y >= 0 && y < height else { return }
        data[y * width + x] = value
    }
    
    /// Get the world coordinates for a grid position.
    public func worldPosition(_ x: Int, _ y: Int) -> (x: Double, y: Double) {
        let wx = minX + Double(x) * cellSizeMm
        let wy = minY + Double(y) * cellSizeMm
        return (wx, wy)
    }
    
    /// Get the grid position for world coordinates.
    public func gridPosition(_ wx: Double, _ wy: Double) -> (x: Int, y: Int) {
        let gx = Int((wx - minX) / cellSizeMm)
        let gy = Int((wy - minY) / cellSizeMm)
        return (gx, gy)
    }
    
    /// Get the bounding box of this heightmap.
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let maxX = minX + Double(width - 1) * cellSizeMm
        let maxY = minY + Double(height - 1) * cellSizeMm
        return (minX, minY, maxX, maxY)
    }
}

// MARK: - Simulation Result

/// Result of a toolpath simulation.
public struct SimulationResult {
    
    /// The simulated heightmap after toolpath execution.
    public let finalHeightmap: Heightmap
    
    /// Maximum material removed in mm.
    public var maxRemovalMm: Double {
        // Approximation - would need initial vs final comparison
        return 0.0
    }
    
    /// Estimated simulation time in seconds.
    public let simulationTimeSeconds: Double
    
    /// Whether the simulation completed successfully.
    public var success: Bool { true }
}

// MARK: - Preview Mode

/// How to visualize toolpaths during preview.
public enum PreviewMode: String, Codable, Sendable {
    /// Show wireframe of toolpath lines only.
    case wireframe
    /// Show simulated material removal with heightmap.
    case heightfield
    /// Show both wireframe and heightfield overlay.
    case combined
    
    public var displayName: String {
        switch self {
        case .wireframe: return "Wireframe"
        case .heightfield: return "Heightfield"
        case .combined: return "Combined"
        }
    }
}

// MARK: - Toolpath Simulator

/// Simulates toolpath execution on a heightmap for preview purposes.
public final class ToolpathSimulator {
    
    private let initialHeightmap: Heightmap
    
    init(initialHeightmap: Heightmap) {
        self.initialHeightmap = initialHeightmap
    }
    
    /// Create a simulator with default dimensions and cell size.
    public static func createDefault(cellSizeMm: Double = 0.5, stockWidthMm: Double = 100.0, stockHeightMm: Double = 100.0) -> ToolpathSimulator {
        let width = Int(stockWidthMm / cellSizeMm)
        let height = Int(stockHeightMm / cellSizeMm)
        let heightmap = Heightmap(
            width: width,
            height: height,
            cellSizeMm: cellSizeMm,
            minX: 0.0,
            minY: 0.0,
            initialHeight: stockHeightMm // Stock is at Z=stockHeightMm
        )
        return ToolpathSimulator(initialHeightmap: heightmap)
    }
    
    /// Simulate a toolpath on the heightmap.
    public func simulate(toolpathGcode: [String]) -> SimulationResult {
        let startTime = Date()
        
        var workingHeightmap = initialHeightmap
        
        // Parse G-code and apply material removal simulation
        for line in toolpathGcode {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.hasPrefix("(") || trimmed.isEmpty || trimmed.hasPrefix("%") || trimmed.hasPrefix("O=") {
                continue
            }
            
            // Parse G0 (rapid move) - no material removal
            if trimmed.hasPrefix("G0 ") {
                continue
            }
            
            // Parse G1 (linear move) with Z depth changes
            if trimmed.hasPrefix("G1 ") {
                simulateCut(line: trimmed, heightmap: &workingHeightmap)
            }
        }
        
        let endTime = Date()
        let simulationTime = endTime.timeIntervalSince(startTime)
        
        return SimulationResult(
            finalHeightmap: workingHeightmap,
            simulationTimeSeconds: simulationTime
        )
    }
    
    /// Simulate a single cut operation on the heightmap.
    private func simulateCut(line: String, heightmap: inout Heightmap) {
        // Parse X, Y, Z coordinates from G-code line
        var xCoord: Double?
        var yCoord: Double?
        var zCoord: Double?
        
        let components = line.components(separatedBy: " ")
        
        for component in components {
            if component.hasPrefix("X") {
                xCoord = Double(component.dropFirst())
            } else if component.hasPrefix("Y") {
                yCoord = Double(component.dropFirst())
            } else if component.hasPrefix("Z") {
                zCoord = Double(component.dropFirst())
            }
        }
        
        // If we have a Z depth, update the heightmap at that position
        if let z = zCoord, let x = xCoord, let y = yCoord {
            let gridPos = heightmap.gridPosition(x, y)
            
            // Update height at this position (material removal)
            let currentHeight = heightmap.getHeight(gridPos.x, gridPos.y)
            if z < currentHeight {
                heightmap.setHeight(z, gridPos.x, gridPos.y)
            }
        }
    }
    
    /// Get the current heightmap state.
    public func getHeightmap() -> Heightmap {
        initialHeightmap
    }
}

// MARK: - Preview Renderer (Wireframe)

/// Renders toolpath wireframes for preview display.
public struct WireframeRenderer {
    
    /// Generate wireframe points from G-code lines.
    public static func generateWireframe(from gcodeLines: [String]) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        
        for line in gcodeLines {
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
    
    /// Generate colored segments based on move type (rapid vs cut).
    public static func generateSegments(from gcodeLines: [String]) -> [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] {
        var segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] = []
        var lastPoint: (x: Double, y: Double)?
        
        for line in gcodeLines {
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
                let currentPoint = (x, y)
                
                if let last = lastPoint {
                    let isRapid = trimmed.hasPrefix("G0 ")
                    segments.append((last, currentPoint, isRapid))
                }
                
                lastPoint = currentPoint
            }
        }
        
        return segments
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ToolpathSimulator_Previews: PreviewProvider {
    static var previews: some View {
        Text("Toolpath simulator is a non-visual component")
    }
}
#endif
