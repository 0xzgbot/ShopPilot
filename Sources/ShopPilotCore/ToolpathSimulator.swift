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
    
    public init(width: Int, height: Int, cellSizeMm: Double, minX: Double, minY: Double, initialHeight: Double = 0.0) {
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
    
    /// Whether the simulation was aborted by a cancellation probe
    /// (SPK-0310a) before processing every line.
    public var isCancelled: Bool = false
    
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
    
    /// The stock surface Z (top of material) before any cutting.
    public var stockTopHeight: Double {
        initialHeightmap.data.first ?? 0.0
    }
    
    public init(initialHeightmap: Heightmap) {
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
    public func simulate(
        toolpathGcode: [String],
        zeroPlane: ZeroPlane? = nil
    ) -> SimulationResult {
        simulate(toolpathGcode: toolpathGcode, zeroPlane: zeroPlane, shouldCancel: { false })
    }

    /// Simulate a toolpath on the heightmap, polling `shouldCancel` before
    /// every line so an in-flight draft preview can abort promptly (SPK-0310a).
    /// A cancelled run returns the partial heightmap with `isCancelled` set.
    public func simulate(
        toolpathGcode: [String],
        zeroPlane: ZeroPlane? = nil,
        shouldCancel: () -> Bool
    ) -> SimulationResult {
        let startTime = Date()
        
        var workingHeightmap = initialHeightmap
        
        // Apply zero plane Z offset to initial height if provided
        if let zp = zeroPlane {
            let adjustedInitial = zp.z + zp.offsetZ
            // Shift the heightmap so the zero plane Z aligns with the stock surface
            var shiftedData = workingHeightmap.data
            for i in shiftedData.indices {
                shiftedData[i] += adjustedInitial - workingHeightmap.minY
            }
            workingHeightmap.data = shiftedData
        }
        
        // Parse G-code and apply material removal simulation
        var currentZ: Double = stockTopHeight
        var lastX: Double?
        var lastY: Double?
        for line in toolpathGcode {
            if shouldCancel() {
                return SimulationResult(
                    finalHeightmap: workingHeightmap,
                    simulationTimeSeconds: Date().timeIntervalSince(startTime),
                    isCancelled: true
                )
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.hasPrefix("(") || trimmed.isEmpty || trimmed.hasPrefix("%") || trimmed.hasPrefix("O=") {
                continue
            }
            
            // Parse G0 (rapid move) - track XY but no material removal.
            if trimmed.hasPrefix("G0 ") || trimmed.hasPrefix("G00") {
                let components = trimmed.components(separatedBy: " ")
                for component in components {
                    if component.hasPrefix("X"), let v = Double(component.dropFirst()) { lastX = v }
                    else if component.hasPrefix("Y"), let v = Double(component.dropFirst()) { lastY = v }
                    else if component.hasPrefix("Z"), let v = Double(component.dropFirst()) { currentZ = v }
                }
                continue
            }
            
            // Parse G1 (linear move) with Z depth changes.
            // G-code from ShopPilot emits plunge (Z-only) and move (XY-only) on
            // separate lines, so Z depth is tracked across lines. Material is
            // removed along the whole segment (not just the endpoint) so a
            // raster pocket carves a continuous trench for preview.
            if trimmed.hasPrefix("G1 ") || trimmed.hasPrefix("G01") {
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
                
                if let z = zCoord {
                    currentZ = z
                }

                let endX = xCoord ?? lastX
                let endY = yCoord ?? lastY
                defer {
                    if let x = endX { lastX = x }
                    if let y = endY { lastY = y }
                }

                guard currentZ < stockTopHeight, let ex = endX, let ey = endY else { continue }

                let startX = lastX ?? ex
                let startY = lastY ?? ey
                let dx = ex - startX
                let dy = ey - startY
                let dist = (dx * dx + dy * dy).squareRoot()
                let steps = max(1, Int(ceil(dist / workingHeightmap.cellSizeMm)))
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let wx = startX + dx * t
                    let wy = startY + dy * t
                    let gridPos = workingHeightmap.gridPosition(wx, wy)
                    let currentHeight = workingHeightmap.getHeight(gridPos.x, gridPos.y)
                    if currentZ < currentHeight {
                        workingHeightmap.setHeight(currentZ, gridPos.x, gridPos.y)
                    }
                }
            }
        }
        
        let endTime = Date()
        let simulationTime = endTime.timeIntervalSince(startTime)
        
        return SimulationResult(
            finalHeightmap: workingHeightmap,
            simulationTimeSeconds: simulationTime
        )
    }
    
    /// Get the current heightmap state.
    public func getHeightmap() -> Heightmap {
        initialHeightmap
    }

    /// Coarse height samples for draft preview (Sendable-friendly; no UI).
    public static func draftHeightSamples(
        from gcodeLines: [String],
        cellSizeMm: Double = 2.0,
        stockMm: Double = 120,
        sampleStride: Int = 0
    ) -> (samples: [(x: Double, y: Double, z: Double)], seconds: Double) {
        let sim = createDefault(cellSizeMm: cellSizeMm, stockWidthMm: stockMm, stockHeightMm: stockMm)
        let result = sim.simulate(toolpathGcode: gcodeLines)
        let hm = result.finalHeightmap
        let step = sampleStride > 0 ? sampleStride : max(1, hm.width / 40)
        var samples: [(x: Double, y: Double, z: Double)] = []
        for gy in stride(from: 0, to: hm.height, by: step) {
            for gx in stride(from: 0, to: hm.width, by: step) {
                let world = hm.worldPosition(gx, gy)
                samples.append((world.x, world.y, hm.getHeight(gx, gy)))
            }
        }
        return (samples, result.simulationTimeSeconds)
    }

    /// SPK-1103e — sheet-aware material simulation of the FULL toolpath tree.
    /// Sizes the stock grid from the job sheet (width/depth/thickness), runs the
    /// cancellable material-removal sim, and returns coarse samples for the
    /// preview canvas. Polls `shouldCancel` before every G-code line; a
    /// cancelled run returns the partial heightmap with `isCancelled` set, so
    /// the UI stays responsive and can abort a long sim mid-flight.
    public static func materialSimulation(
        from gcodeLines: [String],
        sheetWidthMm: Double,
        sheetDepthMm: Double,
        stockTopMm: Double,
        cellSizeMm: Double = 1.0,
        sampleStride: Int = 0,
        zeroPlane: ZeroPlane? = nil,
        shouldCancel: () -> Bool = { false }
    ) -> (samples: [(x: Double, y: Double, z: Double)], seconds: Double, isCancelled: Bool) {
        let width = max(1, Int(sheetWidthMm / cellSizeMm))
        let depth = max(1, Int(sheetDepthMm / cellSizeMm))
        let heightmap = Heightmap(
            width: width,
            height: depth,
            cellSizeMm: cellSizeMm,
            minX: 0.0,
            minY: 0.0,
            initialHeight: stockTopMm
        )
        let sim = ToolpathSimulator(initialHeightmap: heightmap)
        let result = sim.simulate(toolpathGcode: gcodeLines, zeroPlane: zeroPlane, shouldCancel: shouldCancel)
        let hm = result.finalHeightmap
        let step = sampleStride > 0 ? sampleStride : max(1, hm.width / 40)
        var samples: [(x: Double, y: Double, z: Double)] = []
        for gy in stride(from: 0, to: hm.height, by: step) {
            for gx in stride(from: 0, to: hm.width, by: step) {
                let world = hm.worldPosition(gx, gy)
                samples.append((world.x, world.y, hm.getHeight(gx, gy)))
            }
        }
        return (samples, result.simulationTimeSeconds, result.isCancelled)
    }
}

// MARK: - Preview Renderer (Wireframe)

/// Renders toolpath wireframes for preview display.
public struct WireframeRenderer {

    /// Parse a modal XY position from a motion line (supports `G0 X10 Y20` and `G0X10Y20`).
    public static func parseXY(from line: String, previousX: Double?, previousY: Double?) -> (x: Double, y: Double, isRapid: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("G0") || trimmed.hasPrefix("G1") || trimmed.hasPrefix("G00") || trimmed.hasPrefix("G01") else {
            return nil
        }
        // Reject G2/G3 arcs for this thin preview slice.
        if trimmed.hasPrefix("G2") || trimmed.hasPrefix("G3") || trimmed.hasPrefix("G02") || trimmed.hasPrefix("G03") {
            return nil
        }
        let isRapid = trimmed.hasPrefix("G0") && !trimmed.hasPrefix("G01") && !trimmed.hasPrefix("G1")

        var x = previousX
        var y = previousY
        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            let ch = trimmed[i]
            if ch == "X" || ch == "Y" {
                let axis = ch
                i = trimmed.index(after: i)
                let start = i
                while i < trimmed.endIndex {
                    let c = trimmed[i]
                    if c == "-" || c == "+" || c == "." || c.isNumber { i = trimmed.index(after: i) } else { break }
                }
                if let val = Double(trimmed[start..<i]) {
                    if axis == "X" { x = val } else { y = val }
                }
                continue
            }
            i = trimmed.index(after: i)
        }
        guard let xx = x, let yy = y else { return nil }
        return (xx, yy, isRapid)
    }

    /// Generate wireframe points from G-code lines.
    public static func generateWireframe(from gcodeLines: [String]) -> [(x: Double, y: Double)] {
        generateSegments(from: gcodeLines).flatMap { [$0.start, $0.end] }
    }

    /// Generate colored segments based on move type (rapid vs cut). Modal XYZ aware.
    public static func generateSegments(from gcodeLines: [String]) -> [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] {
        generateSegmentsCancellable(from: gcodeLines).segments
    }

    /// Chunked segment generation that polls `shouldCancel` before every line,
    /// so a draft wireframe pass can abort mid-flight (SPK-0310a). The full
    /// pass (no probe) produces exactly the same output as `generateSegments`.
    public static func generateSegmentsCancellable(
        from gcodeLines: [String],
        shouldCancel: () -> Bool = { false }
    ) -> (segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)], isCancelled: Bool) {
        var segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] = []
        var lastX: Double?
        var lastY: Double?

        for line in gcodeLines {
            if shouldCancel() {
                return (segments, true)
            }
            guard let parsed = parseXY(from: line, previousX: lastX, previousY: lastY) else { continue }
            let current = (parsed.x, parsed.y)
            if let lx = lastX, let ly = lastY {
                segments.append((start: (lx, ly), end: current, isRapid: parsed.isRapid))
            }
            lastX = parsed.x
            lastY = parsed.y
        }

        return (segments, false)
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
