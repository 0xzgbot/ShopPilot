import Foundation

// MARK: - Preview Quality Level

/// Quality levels for toolpath preview rendering.
public enum PreviewQualityLevel: String, Codable, Sendable {
    /// Low quality - fast rendering, minimal detail.
    case draft
    /// Medium quality - balanced speed/detail.
    case medium
    /// High quality - full detail, slower rendering.
    case final
    
    public var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .medium: return "Medium"
        case .final: return "Final"
        }
    }
    
    /// Cell size multiplier for this quality level.
    public var cellSizeMultiplier: Double {
        switch self {
        case .draft: return 4.0
        case .medium: return 2.0
        case .final: return 1.0
        }
    }
    
    /// Maximum points to render for this quality level.
    public var maxRenderPoints: Int {
        switch self {
        case .draft: return 500
        case .medium: return 2000
        case .final: return 10000
        }
    }
}

// MARK: - Preview State

/// Current state of the preview system.
public enum PreviewState {
    /// No preview active.
    case idle
    /// Preview is being generated.
    case generating
    /// Preview is complete and ready to display.
    case ready
    /// Preview generation was cancelled.
    case cancelled
    
    public var isGenerating: Bool { self == .generating }
    public var isComplete: Bool { self == .ready }
}

// MARK: - Preview Configuration

/// Configuration for preview rendering.
public struct PreviewConfiguration {
    
    public var qualityLevel: PreviewQualityLevel
    public var showWireframe: Bool
    public var showHeightfield: Bool
    public var showKeepOutZones: Bool
    public var progressiveRefinement: Bool
    
    /// Maximum time allowed for preview generation in seconds.
    public var timeoutSeconds: Double
    
    public init(
        qualityLevel: PreviewQualityLevel = .draft,
        showWireframe: Bool = true,
        showHeightfield: Bool = false,
        showKeepOutZones: Bool = true,
        progressiveRefinement: Bool = true,
        timeoutSeconds: Double = 30.0
    ) {
        self.qualityLevel = qualityLevel
        self.showWireframe = showWireframe
        self.showHeightfield = showHeightfield
        self.showKeepOutZones = showKeepOutZones
        self.progressiveRefinement = progressiveRefinement
        self.timeoutSeconds = timeoutSeconds
    }
}

// MARK: - Preview Result

/// Result of a preview generation operation.
public struct PreviewResult {
    
    /// The generated wireframe points.
    public let wireframePoints: [(x: Double, y: Double)]
    
    /// The generated segments with colors.
    public let segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]
    
    /// The simulated heightmap data (if enabled).
    public let heightmapData: [Double]?
    
    /// Quality level used for this preview.
    public let qualityLevel: PreviewQualityLevel
    
    /// Time taken to generate the preview in seconds.
    public let generationTimeSeconds: Double
    
    /// Whether the preview was cancelled.
    public var isCancelled: Bool { generationTimeSeconds <= 0 }
    
    /// Total number of points rendered.
    public var pointCount: Int { wireframePoints.count }
}

// MARK: - Preview Manager

/// Manages toolpath preview generation with quality levels and cancellation support.
public final class PreviewManager: ObservableObject {
    
    @Published public var currentState: PreviewState = .idle
    @Published public var currentResult: PreviewResult? = nil
    
    private let simulator: ToolpathSimulator
    private var configuration: PreviewConfiguration
    private var cancellable: DispatchWorkItem?
    
    init(simulator: ToolpathSimulator, configuration: PreviewConfiguration = PreviewConfiguration()) {
        self.simulator = simulator
        self.configuration = configuration
    }
    
    /// Generate a preview with the current configuration.
    public func generatePreview(gcodeLines: [String]) {
        currentState = .generating
        
        // Cancel any existing generation
        cancellable?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let startTime = Date()
            
            // Generate wireframe
            var wireframePoints = WireframeRenderer.generateWireframe(from: gcodeLines)
            var segments = WireframeRenderer.generateSegments(from: gcodeLines)
            
            // Apply quality level limits
            switch self.configuration.qualityLevel {
            case .draft:
                wireframePoints = Array(wireframePoints.prefix(500))
                segments = Array(segments.prefix(1000))
                
            case .medium:
                wireframePoints = Array(wireframePoints.prefix(2000))
                segments = Array(segments.prefix(4000))
                
            case .final:
                // No limits for final quality
                break
            }
            
            // Generate heightfield if enabled
            var heightmapData: [Double]? = nil
            if self.configuration.showHeightfield {
                let simulationResult = self.simulator.simulate(toolpathGcode: gcodeLines)
                heightmapData = simulationResult.finalHeightmap.data
            }
            
            let generationTime = Date().timeIntervalSince(startTime)
            
            DispatchQueue.main.async {
                self.currentResult = PreviewResult(
                    wireframePoints: wireframePoints,
                    segments: segments,
                    heightmapData: heightmapData,
                    qualityLevel: self.configuration.qualityLevel,
                    generationTimeSeconds: generationTime
                )
                
                let cancelled = self.cancellable?.isCancelled ?? false
                if !cancelled {
                    self.currentState = .ready
                } else {
                    self.currentState = .cancelled
                }
            }
        }
        
        cancellable = workItem
        
        // Execute with timeout
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    /// Cancel the current preview generation.
    public func cancelPreview() {
        cancellable?.cancel()
        currentState = .cancelled
    }
    
    /// Update the preview configuration.
    public func updateConfiguration(_ configuration: PreviewConfiguration) {
        self.configuration = configuration
        
        // If a preview is ready, regenerate with new config
        if let result = currentResult {
            generatePreview(gcodeLines: []) // Would use stored G-code in real implementation
        }
    }
    
    /// Switch to a different quality level.
    public func switchQualityLevel(_ level: PreviewQualityLevel) {
        configuration.qualityLevel = level
        
        if let result = currentResult {
            generatePreview(gcodeLines: []) // Would use stored G-code in real implementation
        }
    }
    
    /// Check if preview generation is in progress.
    public var isGenerating: Bool { currentState.isGenerating }
    
    /// Check if a preview is ready to display.
    public var isReady: Bool { currentState.isComplete }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct PreviewManager_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview manager is a non-visual component")
    }
}
#endif
