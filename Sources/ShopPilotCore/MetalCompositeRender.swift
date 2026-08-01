import Foundation

// MARK: - Metal Composite Render

// Material type for rendering.
public enum RenderMaterial: String, Codable, Sendable {
    case aluminum
    case steel
    case copper
    case brass
    case titanium
    case wood
    case plastic
    case glass
    case custom
}

// Surface finish for rendering.
public enum SurfaceFinish: String, Codable, Sendable {
    case matte
    case brushed
    case polished
    case mirrored
    case sandblasted
    case anodized
    case custom
}

// Lighting configuration for render.
public struct RenderLighting: Codable, Sendable {
    public var ambientIntensity: Double
    public var ambientColor: String
    public var directionalIntensity: Double
    public var directionalColor: String
    public var directionalAngle: Double
    public var useEnvironmentMap: Bool
    
    public init(
        ambientIntensity: Double = 0.3,
        ambientColor: String = "FFFFFF",
        directionalIntensity: Double = 1.0,
        directionalColor: String = "FFFFFF",
        directionalAngle: Double = 45.0,
        useEnvironmentMap: Bool = false
    ) {
        self.ambientIntensity = max(0.0, min(1.0, ambientIntensity))
        self.ambientColor = ambientColor
        self.directionalIntensity = max(0.0, directionalIntensity)
        self.directionalColor = directionalColor
        self.directionalAngle = directionalAngle
        self.useEnvironmentMap = useEnvironmentMap
    }
}

// Metal composite render configuration.
public struct MetalCompositeConfig: Codable, Sendable {
    public var material: RenderMaterial
    public var finish: SurfaceFinish
    public var lighting: RenderLighting
    public var reflectivity: Double
    public var roughness: Double
    public var metalness: Double
    public var componentID: UUID
    
    public init(
        material: RenderMaterial = .aluminum,
        finish: SurfaceFinish = .brushed,
        lighting: RenderLighting = RenderLighting(),
        reflectivity: Double = 0.5,
        roughness: Double = 0.3,
        metalness: Double = 0.8,
        componentID: UUID = UUID()
    ) {
        self.material = material
        self.finish = finish
        self.lighting = lighting
        self.reflectivity = max(0.0, min(1.0, reflectivity))
        self.roughness = max(0.0, min(1.0, roughness))
        self.metalness = max(0.0, min(1.0, metalness))
        self.componentID = componentID
    }
}

// Render output.
public struct RenderOutput: Codable, Sendable {
    public var config: MetalCompositeConfig
    public var imageUrl: String
    public var width: Int
    public var height: Int
    public var fileSize: Int64
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: MetalCompositeConfig,
        imageUrl: String,
        width: Int,
        height: Int,
        fileSize: Int64,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.imageUrl = imageUrl
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.success = success
        self.errorMessage = errorMessage
    }
}

// Material preset.
public struct MaterialPreset: Codable, Sendable {
    public let name: String
    public let material: RenderMaterial
    public let finish: SurfaceFinish
    public let reflectivity: Double
    public let roughness: Double
    public let metalness: Double
    
    public init(
        name: String,
        material: RenderMaterial,
        finish: SurfaceFinish,
        reflectivity: Double,
        roughness: Double,
        metalness: Double
    ) {
        self.name = name
        self.material = material
        self.finish = finish
        self.reflectivity = reflectivity
        self.roughness = roughness
        self.metalness = metalness
    }
}

// MARK: - MetalCompositeRenderEngine

// Manages metal composite rendering.
public final class MetalCompositeRenderEngine {
    
    // All available material presets.
    public static let presets: [MaterialPreset] = [
        MaterialPreset(name: "Brushed Aluminum", material: .aluminum, finish: .brushed, reflectivity: 0.5, roughness: 0.3, metalness: 0.9),
        MaterialPreset(name: "Polished Steel", material: .steel, finish: .polished, reflectivity: 0.8, roughness: 0.1, metalness: 1.0),
        MaterialPreset(name: "Anodized Aluminum", material: .aluminum, finish: .anodized, reflectivity: 0.2, roughness: 0.5, metalness: 0.7),
        MaterialPreset(name: "Brushed Brass", material: .brass, finish: .brushed, reflectivity: 0.6, roughness: 0.4, metalness: 0.8),
        MaterialPreset(name: "Mirror Chrome", material: .steel, finish: .mirrored, reflectivity: 1.0, roughness: 0.0, metalness: 1.0),
        MaterialPreset(name: "Sandblasted Titanium", material: .titanium, finish: .sandblasted, reflectivity: 0.3, roughness: 0.6, metalness: 0.8),
        MaterialPreset(name: "Copper Patina", material: .copper, finish: .matte, reflectivity: 0.2, roughness: 0.8, metalness: 0.6),
    ]
    
    // Returns preset by name.
    public static func getPreset(named name: String) -> MaterialPreset? {
        presets.first { $0.name == name }
    }
    
    // Creates a render config from a preset.
    public static func createConfig(preset: MaterialPreset, componentID: UUID) -> MetalCompositeConfig {
        MetalCompositeConfig(
            material: preset.material,
            finish: preset.finish,
            reflectivity: preset.reflectivity,
            roughness: preset.roughness,
            metalness: preset.metalness,
            componentID: componentID
        )
    }
    
    // Renders a component with the given config.
    public static func render(_ config: MetalCompositeConfig) -> RenderOutput {
        // Generate render output (simplified)
        let outputDir = NSTemporaryDirectory()
        let filename = "render_\(config.componentID.uuidString).png"
        let filePath = (outputDir as NSString).appendingPathComponent(filename)
        
        return RenderOutput(
            config: config,
            imageUrl: filePath,
            width: 1920,
            height: 1080,
            fileSize: 0,
            success: true
        )
    }
    
    // Validates render config.
    public static func validate(_ config: MetalCompositeConfig) -> (isValid: Bool, error: String?) {
        if config.reflectivity < 0.0 || config.reflectivity > 1.0 {
            return (false, "Reflectivity must be between 0.0 and 1.0")
        }
        if config.roughness < 0.0 || config.roughness > 1.0 {
            return (false, "Roughness must be between 0.0 and 1.0")
        }
        if config.metalness < 0.0 || config.metalness > 1.0 {
            return (false, "Metalness must be between 0.0 and 1.0")
        }
        return (true, nil)
    }
}
