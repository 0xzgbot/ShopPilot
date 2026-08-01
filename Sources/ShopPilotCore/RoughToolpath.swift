import Foundation

// MARK: - 3D Rough Toolpath

// 3D rough toolpath strategy.
public enum RoughToolpathStrategy: String, Codable, Sendable {
    case zigzag
    case zigzagAlternate
    case offset
    case spiral
    case followProfile
    case adaptive
}

// 3D rough toolpath parameters.
public struct RoughToolpathParams: Codable, Sendable {
    public var strategy: RoughToolpathStrategy
    public var stepOverMm: Double
    public var stepDownMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var safetyHeightMm: Double
    public var clearanceHeightMm: Double
    public var topOffsetMm: Double
    public var bottomOffsetMm: Double
    public var useZigzag: Bool
    public var zigzagAngle: Double
    public var tabsEnabled: Bool
    public var tabWidthMm: Double
    public var tabSpacingMm: Double
    
    public init(
        strategy: RoughToolpathStrategy = .zigzag,
        stepOverMm: Double = 0.5,
        stepDownMm: Double = 0.25,
        feedRateMmPerMin: Double = 1000.0,
        plungeFeedRateMmPerMin: Double = 500.0,
        toolDiameterMm: Double = 6.0,
        safetyHeightMm: Double = 5.0,
        clearanceHeightMm: Double = 2.0,
        topOffsetMm: Double = 0.0,
        bottomOffsetMm: Double = 0.0,
        useZigzag: Bool = true,
        zigzagAngle: Double = 0.0,
        tabsEnabled: Bool = false,
        tabWidthMm: Double = 5.0,
        tabSpacingMm: Double = 50.0
    ) {
        self.strategy = strategy
        self.stepOverMm = max(0.01, stepOverMm)
        self.stepDownMm = max(0.01, stepDownMm)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.toolDiameterMm = max(0.1, toolDiameterMm)
        self.safetyHeightMm = max(0.0, safetyHeightMm)
        self.clearanceHeightMm = max(0.0, clearanceHeightMm)
        self.topOffsetMm = topOffsetMm
        self.bottomOffsetMm = bottomOffsetMm
        self.useZigzag = useZigzag
        self.zigzagAngle = zigzagAngle
        self.tabsEnabled = tabsEnabled
        self.tabWidthMm = max(1.0, tabWidthMm)
        self.tabSpacingMm = max(10.0, tabSpacingMm)
    }
}

// 3D rough toolpath result.
public struct RoughToolpathResult: Codable, Sendable {
    public var toolpathID: UUID
    public var componentID: UUID
    public var strategy: RoughToolpathStrategy
    public var totalPathLengthMm: Double
    public var estimatedTimeMinutes: Double
    public var toolChanges: Int
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        toolpathID: UUID,
        componentID: UUID,
        strategy: RoughToolpathStrategy,
        totalPathLengthMm: Double,
        estimatedTimeMinutes: Double,
        toolChanges: Int,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.toolpathID = toolpathID
        self.componentID = componentID
        self.strategy = strategy
        self.totalPathLengthMm = totalPathLengthMm
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.toolChanges = toolChanges
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - RoughToolpathEngine

// Generates 3D rough toolpaths.
public final class RoughToolpathEngine {
    
    // Generates a rough toolpath for a component.
    public static func generate(
        componentID: UUID,
        config: RoughToolpathParams,
        boundingBox: BoundingBox3D
    ) -> RoughToolpathResult {
        // Validate parameters
        if config.stepOverMm > config.toolDiameterMm {
            return RoughToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                toolChanges: 0,
                success: false,
                errorMessage: "Step over (\(config.stepOverMm)mm) exceeds tool diameter (\(config.toolDiameterMm)mm)"
            )
        }
        
        if config.stepDownMm <= 0 {
            return RoughToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                toolChanges: 0,
                success: false,
                errorMessage: "Step down must be positive"
            )
        }
        
        // Calculate depth
        let depth = boundingBox.maxZ - boundingBox.minZ
        guard depth > 0 else {
            return RoughToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                toolChanges: 0,
                success: false,
                errorMessage: "Component has zero depth"
            )
        }
        
        // Calculate number of passes
        let totalDepth = depth - config.bottomOffsetMm + config.topOffsetMm
        let passes = max(1, Int(ceil(totalDepth / config.stepDownMm)))
        
        // Estimate path length (simplified)
        let area = boundingBox.width * boundingBox.height
        let stepOverMm = config.stepOverMm
        let estimatedPaths = area / (stepOverMm * max(boundingBox.width, boundingBox.height))
        let avgPathLength = max(boundingBox.width, boundingBox.height)
        let totalPathLength = estimatedPaths * avgPathLength * Double(passes)
        
        // Estimate time
        let feedRateMmPerMin = config.feedRateMmPerMin
        let cuttingTimeMinutes = totalPathLength / feedRateMmPerMin
        let plungeTimeMinutes = Double(passes) * 0.5
        let totalTime = cuttingTimeMinutes + plungeTimeMinutes
        
        // Estimate tool changes (simplified)
        let toolChanges = max(1, Int(ceil(totalTime / 30.0)))
        
        return RoughToolpathResult(
            toolpathID: UUID(),
            componentID: componentID,
            strategy: config.strategy,
            totalPathLengthMm: totalPathLength,
            estimatedTimeMinutes: totalTime,
            toolChanges: toolChanges,
            success: true
        )
    }
    
    // Validates rough toolpath parameters.
    public static func validate(_ params: RoughToolpathParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if params.stepOverMm <= 0 {
            errors.append("Step over must be positive")
        }
        if params.stepDownMm <= 0 {
            errors.append("Step down must be positive")
        }
        if params.feedRateMmPerMin <= 0 {
            errors.append("Feed rate must be positive")
        }
        if params.plungeFeedRateMmPerMin <= 0 {
            errors.append("Plunge feed rate must be positive")
        }
        if params.toolDiameterMm <= 0 {
            errors.append("Tool diameter must be positive")
        }
        if params.safetyHeightMm < params.clearanceHeightMm {
            errors.append("Safety height must be >= clearance height")
        }
        
        return (errors.isEmpty, errors)
    }
}
