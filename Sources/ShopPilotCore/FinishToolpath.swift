import Foundation

// MARK: - 3D Finish Toolpath

// 3D finish toolpath strategy.
public enum FinishToolpathStrategy: String, Codable, Sendable {
    case parallel
    case radial
    case spiral
    case followContour
    case zigzag
    case multiAxis
}

// Pass type for finish toolpath.
public enum FinishPassType: String, Codable, Sendable {
    case rough
    case semiFinish
    case finish
    case skim
}

// 3D finish toolpath parameters.
public struct FinishToolpathParams: Codable, Sendable {
    public var strategy: FinishToolpathStrategy
    public var stepOverMm: Double
    public var stepDownMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var toolDiameterMm: Double
    public var safetyHeightMm: Double
    public var clearanceHeightMm: Double
    public var topOffsetMm: Double
    public var bottomOffsetMm: Double
    public var skipZones: Double
    public var scallopHeightMm: Double
    public var useZigzag: Bool
    public var zigzagAngle: Double
    public var tabsEnabled: Bool
    public var tabWidthMm: Double
    public var tabSpacingMm: Double
    
    public init(
        strategy: FinishToolpathStrategy = .parallel,
        stepOverMm: Double = 0.05,
        stepDownMm: Double = 0.01,
        feedRateMmPerMin: Double = 2000.0,
        plungeFeedRateMmPerMin: Double = 200.0,
        toolDiameterMm: Double = 3.0,
        safetyHeightMm: Double = 5.0,
        clearanceHeightMm: Double = 2.0,
        topOffsetMm: Double = 0.0,
        bottomOffsetMm: Double = 0.0,
        skipZones: Double = 0.0,
        scallopHeightMm: Double = 0.01,
        useZigzag: Bool = false,
        zigzagAngle: Double = 0.0,
        tabsEnabled: Bool = false,
        tabWidthMm: Double = 5.0,
        tabSpacingMm: Double = 50.0
    ) {
        self.strategy = strategy
        self.stepOverMm = max(0.001, stepOverMm)
        self.stepDownMm = max(0.001, stepDownMm)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.toolDiameterMm = max(0.1, toolDiameterMm)
        self.safetyHeightMm = max(0.0, safetyHeightMm)
        self.clearanceHeightMm = max(0.0, clearanceHeightMm)
        self.topOffsetMm = topOffsetMm
        self.bottomOffsetMm = bottomOffsetMm
        self.skipZones = max(0.0, skipZones)
        self.scallopHeightMm = max(0.001, scallopHeightMm)
        self.useZigzag = useZigzag
        self.zigzagAngle = zigzagAngle
        self.tabsEnabled = tabsEnabled
        self.tabWidthMm = max(1.0, tabWidthMm)
        self.tabSpacingMm = max(10.0, tabSpacingMm)
    }
}

// 3D finish toolpath result.
public struct FinishToolpathResult: Codable, Sendable {
    public var toolpathID: UUID
    public var componentID: UUID
    public var strategy: FinishToolpathStrategy
    public var passType: FinishPassType
    public var totalPathLengthMm: Double
    public var estimatedTimeMinutes: Double
    public var surfaceQuality: String
    public var toolChanges: Int
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        toolpathID: UUID,
        componentID: UUID,
        strategy: FinishToolpathStrategy,
        passType: FinishPassType,
        totalPathLengthMm: Double,
        estimatedTimeMinutes: Double,
        surfaceQuality: String,
        toolChanges: Int,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.toolpathID = toolpathID
        self.componentID = componentID
        self.strategy = strategy
        self.passType = passType
        self.totalPathLengthMm = totalPathLengthMm
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.surfaceQuality = surfaceQuality
        self.toolChanges = toolChanges
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - FinishToolpathEngine

// Generates 3D finish toolpaths.
public final class FinishToolpathEngine {
    
    // Generates a finish toolpath for a component.
    public static func generate(
        componentID: UUID,
        config: FinishToolpathParams,
        boundingBox: BoundingBox3D
    ) -> FinishToolpathResult {
        // Validate parameters
        if config.stepOverMm > config.toolDiameterMm {
            return FinishToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                passType: .finish,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                surfaceQuality: "N/A",
                toolChanges: 0,
                success: false,
                errorMessage: "Step over (\(config.stepOverMm)mm) exceeds tool diameter (\(config.toolDiameterMm)mm)"
            )
        }
        
        if config.stepDownMm <= 0 {
            return FinishToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                passType: .finish,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                surfaceQuality: "N/A",
                toolChanges: 0,
                success: false,
                errorMessage: "Step down must be positive"
            )
        }
        
        // Calculate depth
        let depth = boundingBox.maxZ - boundingBox.minZ
        guard depth > 0 else {
            return FinishToolpathResult(
                toolpathID: UUID(),
                componentID: componentID,
                strategy: config.strategy,
                passType: .finish,
                totalPathLengthMm: 0,
                estimatedTimeMinutes: 0,
                surfaceQuality: "N/A",
                toolChanges: 0,
                success: false,
                errorMessage: "Component has zero depth"
            )
        }
        
        // Determine pass type based on scallop height
        let passType: FinishPassType
        if config.scallopHeightMm < 0.005 {
            passType = .skim
        } else if config.scallopHeightMm < 0.02 {
            passType = .finish
        } else {
            passType = .semiFinish
        }
        
        // Calculate passes
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
        let plungeTimeMinutes = Double(passes) * 0.25
        let totalTime = cuttingTimeMinutes + plungeTimeMinutes
        
        // Estimate tool changes
        let toolChanges = max(1, Int(ceil(totalTime / 45.0)))
        
        // Surface quality label
        let surfaceQuality: String
        if config.scallopHeightMm < 0.005 {
            surfaceQuality = "Mirror finish"
        } else if config.scallopHeightMm < 0.01 {
            surfaceQuality = "Fine finish"
        } else if config.scallopHeightMm < 0.025 {
            surfaceQuality = "Good finish"
        } else {
            surfaceQuality = "Standard finish"
        }
        
        return FinishToolpathResult(
            toolpathID: UUID(),
            componentID: componentID,
            strategy: config.strategy,
            passType: passType,
            totalPathLengthMm: totalPathLength,
            estimatedTimeMinutes: totalTime,
            surfaceQuality: surfaceQuality,
            toolChanges: toolChanges,
            success: true
        )
    }
    
    // Validates finish toolpath parameters.
    public static func validate(_ params: FinishToolpathParams) -> (isValid: Bool, errors: [String]) {
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
        if params.scallopHeightMm <= 0 {
            errors.append("Scallop height must be positive")
        }
        
        return (errors.isEmpty, errors)
    }
}
