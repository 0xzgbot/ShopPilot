import Foundation

// MARK: - Viewport State

/// Stable viewport state for metal-backed preview rendering.
public struct ViewportState {
    
    /// Center X coordinate in world space.
    public var centerX: Double
    
    /// Center Y coordinate in world space.
    public var centerY: Double
    
    /// Zoom level (units per point).
    public var zoom: Double
    
    /// Rotation angle in radians.
    public var rotation: Double
    
    /// Aspect ratio of the viewport.
    public var aspectRatio: Double
    
    init(centerX: Double, centerY: Double, zoom: Double, rotation: Double = 0.0, aspectRatio: Double = 1.0) {
        self.centerX = centerX
        self.centerY = centerY
        self.zoom = zoom
        self.rotation = rotation
        self.aspectRatio = aspectRatio
    }
    
    /// Create viewport centered on a bounding box with appropriate zoom.
    public static func fitToBounds(_ bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double), viewportWidth: Double, viewportHeight: Double, padding: Double = 10.0) -> ViewportState {
        let width = bounds.maxX - bounds.minX + padding * 2
        let height = bounds.maxY - bounds.minY + padding * 2
        
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2
        
        let aspectRatio = viewportWidth / viewportHeight
        let zoom: Double
        
        if width > height * aspectRatio {
            zoom = width / viewportWidth
        } else {
            zoom = height / viewportHeight
        }
        
        return ViewportState(centerX: centerX, centerY: centerY, zoom: zoom, aspectRatio: aspectRatio)
    }
}

// MARK: - Metal Preview Configuration

/// Configuration for metal-backed preview rendering.
public struct MetalPreviewConfiguration {
    
    /// Whether to use metal acceleration.
    public var enableMetal: Bool
    
    /// Maximum frame rate for preview updates.
    public var maxFrameRate: Int
    
    /// Anti-aliasing quality level.
    public enum AntialiasingQuality: String, Codable, Sendable {
        case none
        case low
        case high
        
        public var samples: Int {
            switch self {
            case .none: return 1
            case .low: return 4
            case .high: return 8
            }
        }
    }
    
    public var antialiasingQuality: AntialiasingQuality
    
    /// Whether to enable depth testing for heightfield rendering.
    public var enableDepthTesting: Bool
    
    /// Maximum number of draw calls per frame.
    public var maxDrawCallsPerFrame: Int
    
    public init(
        enableMetal: Bool = true,
        maxFrameRate: Int = 60,
        antialiasingQuality: AntialiasingQuality = .low,
        enableDepthTesting: Bool = true,
        maxDrawCallsPerFrame: Int = 1000
    ) {
        self.enableMetal = enableMetal
        self.maxFrameRate = maxFrameRate
        self.antialiasingQuality = antialiasingQuality
        self.enableDepthTesting = enableDepthTesting
        self.maxDrawCallsPerFrame = maxDrawCallsPerFrame
    }
}

// MARK: - Preview Render Command

/// A render command for the metal preview pipeline.
public struct PreviewRenderCommand {
    
    /// Type of rendering operation.
    public enum CommandType {
        case clear
        case drawWireframe([(x: Double, y: Double)])
        case drawSegments([(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)])
        case drawHeightmap([Double], width: Int, height: Int)
        case drawKeepOutZones
    }
    
    public let commandType: CommandType
    
    /// Viewport state for this render command.
    public let viewportState: ViewportState
    
    init(commandType: CommandType, viewportState: ViewportState) {
        self.commandType = commandType
        self.viewportState = viewportState
    }
}

// MARK: - Metal Preview Renderer

/// Manages metal-backed preview rendering with stable viewport state.
public final class MetalPreviewRenderer {
    
    private let configuration: MetalPreviewConfiguration
    @Published public var currentViewport: ViewportState
    @Published public var renderCommands: [PreviewRenderCommand] = []
    
    /// Whether metal rendering is available and enabled.
    public var isMetalAvailable: Bool
    
    init(configuration: MetalPreviewConfiguration, initialViewport: ViewportState) {
        self.configuration = configuration
        self.currentViewport = initialViewport
        self.isMetalAvailable = configuration.enableMetal && Self.checkMetalAvailability()
    }
    
    /// Check if metal rendering is available on this device.
    private static func checkMetalAvailability() -> Bool {
        // In a real implementation, this would query the MTLDevice
        return true
    }
    
    /// Update the viewport state (pan/zoom/rotate).
    public func updateViewport(_ viewport: ViewportState) {
        currentViewport = viewport
        
        // Regenerate render commands with new viewport
        regenerateRenderCommands()
    }
    
    /// Fit the viewport to a bounding box.
    public func fitToBounds(_ bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double), viewportWidth: Double, viewportHeight: Double) {
        let newViewport = ViewportState.fitToBounds(bounds, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        updateViewport(newViewport)
    }
    
    /// Generate render commands from toolpath data.
    public func generateRenderCommands(
        wireframePoints: [(x: Double, y: Double)],
        segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)],
        heightmapData: [Double]? = nil,
        keepOutZones: Bool = false
    ) {
        renderCommands = []
        
        // Clear command
        renderCommands.append(PreviewRenderCommand(commandType: .clear, viewportState: currentViewport))
        
        // Wireframe points
        if !wireframePoints.isEmpty {
            renderCommands.append(PreviewRenderCommand(commandType: .drawWireframe(wireframePoints), viewportState: currentViewport))
        }
        
        // Segments
        if !segments.isEmpty {
            renderCommands.append(PreviewRenderCommand(commandType: .drawSegments(segments), viewportState: currentViewport))
        }
        
        // Heightmap data
        if let heightmap = heightmapData, !heightmap.isEmpty {
            let width = Int(sqrt(Double(heightmap.count)))
            let height = heightmap.count / width
            renderCommands.append(PreviewRenderCommand(commandType: .drawHeightmap(heightmap, width: width, height: height), viewportState: currentViewport))
        }
        
        // Keep-out zones (would need zone data in real implementation)
        if keepOutZones {
            renderCommands.append(PreviewRenderCommand(commandType: .drawKeepOutZones, viewportState: currentViewport))
        }
    }
    
    /// Regenerate render commands with current viewport state.
    private func regenerateRenderCommands() {
        // In a real implementation, this would reproject all geometry to the new viewport
        // For now, we just mark that regeneration is needed
        if !renderCommands.isEmpty {
            let firstCommand = renderCommands.first!
            renderCommands = [PreviewRenderCommand(commandType: firstCommand.commandType, viewportState: currentViewport)]
        }
    }
    
    /// Get the number of render commands queued.
    public var commandCount: Int { renderCommands.count }
    
    /// Check if metal rendering is being used.
    public var usingMetal: Bool { isMetalAvailable && configuration.enableMetal }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct MetalPreviewRenderer_Previews: PreviewProvider {
    static var previews: some View {
        Text("Metal preview renderer is a non-visual component")
    }
}
#endif
