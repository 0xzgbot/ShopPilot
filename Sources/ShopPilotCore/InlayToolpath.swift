import Foundation

// MARK: - Inlay Pocket/Plug + VCarve Inlay Recipes

// Inlay type.
public enum InlayType: String, Codable, Sendable {
    case pocket
    case plug
    case fullInlay
    case vCarve
}

// Plug shape.
public enum PlugShape: String, Codable, Sendable {
    case round
    case square
    case hexagonal
    case custom
}

// V-carve angle.
public enum VCaveAngle: String, Codable, Sendable {
    case angle30 = "30 degree"
    case angle45 = "45 degree"
    case angle60 = "60 degree"
    case angle90 = "90 degree"
}

// Inlay material type.
public enum InlayMaterial: String, Codable, Sendable {
    case sameAsBase
    case contrastingWood
    case metal
    case resin
    case plastic
    case custom
}

// Inlay pocket parameters.
public struct InlayPocketParams: Codable, Sendable {
    public var inlayType: InlayType
    public var shape: PlugShape
    public var diameter: Double
    public var depth: Double
    public var pocketClearance: Double
    public var plugClearance: Double
    public var toolDiameter: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var vCarveAngle: VCaveAngle?
    public var vCarveDepth: Double
    public var material: InlayMaterial
    public var customShapePoints: [PolygonPoint]
    
    public init(
        inlayType: InlayType = .pocket,
        shape: PlugShape = .round,
        diameter: Double = 10.0,
        depth: Double = 3.0,
        pocketClearance: Double = 0.02,
        plugClearance: Double = 0.05,
        toolDiameter: Double = 3.175,
        feedRateMmPerMin: Double = 800.0,
        plungeFeedRateMmPerMin: Double = 200.0,
        vCarveAngle: VCaveAngle? = nil,
        vCarveDepth: Double = 2.0,
        material: InlayMaterial = .contrastingWood,
        customShapePoints: [PolygonPoint] = []
    ) {
        self.inlayType = inlayType
        self.shape = shape
        self.diameter = max(0.1, diameter)
        self.depth = max(0.01, depth)
        self.pocketClearance = max(0.0, pocketClearance)
        self.plugClearance = max(0.0, plugClearance)
        self.toolDiameter = max(0.1, toolDiameter)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.vCarveAngle = vCarveAngle
        self.vCarveDepth = max(0.0, vCarveDepth)
        self.material = material
        self.customShapePoints = customShapePoints
    }
}

// VCarve inlay recipe.
public struct VCarveRecipe: Codable, Sendable {
    public var name: String
    public var description: String
    public var vCarveAngle: VCaveAngle
    public var toolDiameter: Double
    public var stepOverMm: Double
    public var feedRateMmPerMin: Double
    public var plungeFeedRateMmPerMin: Double
    public var depthPerPassMm: Double
    public var maxDepthMm: Double
    public var material: InlayMaterial
    public var estimatedTimeMinutes: Double
    
    public init(
        name: String,
        description: String,
        vCarveAngle: VCaveAngle,
        toolDiameter: Double = 3.175,
        stepOverMm: Double = 0.5,
        feedRateMmPerMin: Double = 800.0,
        plungeFeedRateMmPerMin: Double = 200.0,
        depthPerPassMm: Double = 0.5,
        maxDepthMm: Double = 3.0,
        material: InlayMaterial = .contrastingWood,
        estimatedTimeMinutes: Double = 5.0
    ) {
        self.name = name
        self.description = description
        self.vCarveAngle = vCarveAngle
        self.toolDiameter = max(0.1, toolDiameter)
        self.stepOverMm = max(0.01, stepOverMm)
        self.feedRateMmPerMin = max(1.0, feedRateMmPerMin)
        self.plungeFeedRateMmPerMin = max(1.0, plungeFeedRateMmPerMin)
        self.depthPerPassMm = max(0.01, depthPerPassMm)
        self.maxDepthMm = max(0.01, maxDepthMm)
        self.material = material
        self.estimatedTimeMinutes = max(0.1, estimatedTimeMinutes)
    }
}

// Inlay result.
public struct InlayResult: Codable, Sendable {
    public var inlayType: InlayType
    public var pocketID: UUID?
    public var plugID: UUID?
    public var toolpathLengthMm: Double
    public var estimatedTimeMinutes: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        inlayType: InlayType,
        pocketID: UUID? = nil,
        plugID: UUID? = nil,
        toolpathLengthMm: Double,
        estimatedTimeMinutes: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.inlayType = inlayType
        self.pocketID = pocketID
        self.plugID = plugID
        self.toolpathLengthMm = toolpathLengthMm
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - InlayEngine

// Generates inlay pocket/plug toolpaths and manages VCarve recipes.
public final class InlayEngine {
    
    // Preset VCarve recipes.
    public static let presetRecipes: [VCarveRecipe] = [
        VCarveRecipe(
            name: "Standard 30-Degree Inlay",
            description: "Fine detail V-carve with 30-degree bit. Best for detailed lettering and small graphics.",
            vCarveAngle: .angle30,
            toolDiameter: 3.175,
            stepOverMm: 0.3,
            feedRateMmPerMin: 600.0,
            plungeFeedRateMmPerMin: 150.0,
            depthPerPassMm: 0.25,
            maxDepthMm: 2.5,
            estimatedTimeMinutes: 8.0
        ),
        VCarveRecipe(
            name: "Medium 45-Degree Inlay",
            description: "Balanced detail and speed with 45-degree bit. Good for medium complexity designs.",
            vCarveAngle: .angle45,
            toolDiameter: 3.175,
            stepOverMm: 0.5,
            feedRateMmPerMin: 800.0,
            plungeFeedRateMmPerMin: 200.0,
            depthPerPassMm: 0.5,
            maxDepthMm: 3.0,
            estimatedTimeMinutes: 5.0
        ),
        VCarveRecipe(
            name: "Bold 60-Degree Inlay",
            description: "Fast, bold V-carve with 60-degree bit. Ideal for large text and simple graphics.",
            vCarveAngle: .angle60,
            toolDiameter: 6.35,
            stepOverMm: 0.8,
            feedRateMmPerMin: 1000.0,
            plungeFeedRateMmPerMin: 300.0,
            depthPerPassMm: 0.75,
            maxDepthMm: 4.0,
            estimatedTimeMinutes: 3.5
        ),
        VCarveRecipe(
            name: "Deep 90-Degree Inlay",
            description: "Maximum depth V-carve with 90-degree bit. For deep, dramatic shadows.",
            vCarveAngle: .angle90,
            toolDiameter: 6.35,
            stepOverMm: 1.0,
            feedRateMmPerMin: 1200.0,
            plungeFeedRateMmPerMin: 400.0,
            depthPerPassMm: 1.0,
            maxDepthMm: 5.0,
            estimatedTimeMinutes: 2.5
        )
    ]
    
    // Generates an inlay pocket or plug toolpath.
    public static func generateInlay(
        params: InlayPocketParams,
        boundingBox: BoundingBox3D
    ) -> InlayResult {
        if params.diameter <= 0 {
            return InlayResult(
                inlayType: params.inlayType,
                toolpathLengthMm: 0,
                estimatedTimeMinutes: 0,
                success: false,
                errorMessage: "Diameter must be positive"
            )
        }
        
        if params.depth <= 0 {
            return InlayResult(
                inlayType: params.inlayType,
                toolpathLengthMm: 0,
                estimatedTimeMinutes: 0,
                success: false,
                errorMessage: "Depth must be positive"
            )
        }
        
        // Calculate toolpath length based on shape
        let perimeter: Double
        switch params.shape {
        case .round:
            perimeter = .pi * params.diameter
        case .square:
            perimeter = 4 * params.diameter
        case .hexagonal:
            perimeter = 6 * params.diameter
        case .custom:
            perimeter = 2 * .pi * params.diameter / 3
        }
        
        // Add clearance cuts
        let clearanceFactor = 1.0 + params.pocketClearance + params.plugClearance
        let totalPathLength = perimeter * clearanceFactor
        
        // Estimate time
        let cuttingTime = totalPathLength / params.feedRateMmPerMin * 60.0
        let plungeTime = 3.0
        let totalTime = cuttingTime + plungeTime
        
        // Determine which IDs to create
        let pocketID: UUID?
        let plugID: UUID?
        switch params.inlayType {
        case .pocket:
            pocketID = UUID()
            plugID = nil
        case .plug:
            pocketID = nil
            plugID = UUID()
        case .fullInlay:
            pocketID = UUID()
            plugID = UUID()
        case .vCarve:
            pocketID = UUID()
            plugID = nil
        }
        
        return InlayResult(
            inlayType: params.inlayType,
            pocketID: pocketID,
            plugID: plugID,
            toolpathLengthMm: totalPathLength,
            estimatedTimeMinutes: totalTime,
            success: true
        )
    }
    
    // Gets a preset recipe by name.
    public static func getRecipe(named name: String) -> VCarveRecipe? {
        presetRecipes.first { $0.name == name }
    }
    
    // Gets all preset recipes.
    public static func getAllRecipes() -> [VCarveRecipe] {
        presetRecipes
    }
    
    // Creates a custom recipe.
    public static func createRecipe(
        name: String,
        description: String,
        vCarveAngle: VCaveAngle,
        toolDiameter: Double,
        stepOverMm: Double,
        feedRateMmPerMin: Double,
        plungeFeedRateMmPerMin: Double,
        depthPerPassMm: Double,
        maxDepthMm: Double,
        material: InlayMaterial
    ) -> VCarveRecipe {
        VCarveRecipe(
            name: name,
            description: description,
            vCarveAngle: vCarveAngle,
            toolDiameter: toolDiameter,
            stepOverMm: stepOverMm,
            feedRateMmPerMin: feedRateMmPerMin,
            plungeFeedRateMmPerMin: plungeFeedRateMmPerMin,
            depthPerPassMm: depthPerPassMm,
            maxDepthMm: maxDepthMm,
            material: material
        )
    }
    
    // Validates inlay parameters.
    public static func validate(_ params: InlayPocketParams) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if params.diameter <= 0 { errors.append("Diameter must be positive") }
        if params.depth <= 0 { errors.append("Depth must be positive") }
        if params.toolDiameter <= 0 { errors.append("Tool diameter must be positive") }
        if params.feedRateMmPerMin <= 0 { errors.append("Feed rate must be positive") }
        if params.plungeFeedRateMmPerMin <= 0 { errors.append("Plunge feed rate must be positive") }
        if params.pocketClearance < 0 { errors.append("Pocket clearance cannot be negative") }
        if params.plugClearance < 0 { errors.append("Plug clearance cannot be negative") }
        
        if case .custom = params.shape, params.customShapePoints.count < 3 {
            errors.append("Custom shape requires at least 3 points")
        }
        
        return (errors.isEmpty, errors)
    }
}
