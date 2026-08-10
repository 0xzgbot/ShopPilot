import Foundation
import CoreGraphics
import ImageIO

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
    
    // Renders a component with the given config — generates a real PNG image
    // using Core Graphics. The image is a 512×512 procedural texture that
    // simulates the material appearance with finish-based noise/grain.
    public static func render(_ config: MetalCompositeConfig) -> RenderOutput {
        do {
            let width = 512
            let height = 512
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            
            // Base color from material
            let baseColor = materialColor(for: config.material)
            let finishMultiplier = finishMultiplier(for: config.finish)
            let ambient = config.lighting.ambientIntensity
            let directional = config.lighting.directionalIntensity
            
            for y in 0..<height {
                for x in 0..<width {
                    let idx = (y * width + x) * 4
                    
                    // Procedural finish noise
                    let noise = finishNoise(x: x, y: y, finish: config.finish)
                    
                    // Simple directional lighting (top-left)
                    let dx = Double(x) / Double(width)
                    let dy = Double(y) / Double(height)
                    let light = 1.0 - ((1.0 - dx) * 0.6 + (1.0 - dy) * 0.4)
                    
                    let r = baseColor.r * finishMultiplier * (ambient + directional * light) + noise
                    let g = baseColor.g * finishMultiplier * (ambient + directional * light) + noise
                    let b = baseColor.b * finishMultiplier * (ambient + directional * light) + noise
                    
                    // Clamp to [0,255] as Double BEFORE converting: UInt8(x)
                    // traps when x is out of range, and the directional slider
                    // goes up to 3.0 (ambient+directional·light ≈ 3.8) which
                    // yields ~970 — a plain `min(255, UInt8(r*255))` crashes.
                    pixels[idx]     = UInt8(max(0, min(255, r * 255)))
                    pixels[idx + 1] = UInt8(max(0, min(255, g * 255)))
                    pixels[idx + 2] = UInt8(max(0, min(255, b * 255)))
                    pixels[idx + 3] = 255 // alpha
                }
            }
            
            // Write PNG via Core Graphics — bitmap context + image destination.
            let outputDir = NSTemporaryDirectory()
            let filename = "render_\(config.componentID.uuidString).png"
            let filePath = (outputDir as NSString).appendingPathComponent(filename)
            
            // Create a bitmap context over our pixel buffer (row-major RGBA).
            var pixelBuffer = pixels
            guard let ctx = pixelBuffer.withUnsafeMutableBytes({ bytes -> CGContext? in
                guard let base = bytes.baseAddress else { return nil }
                return CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }),
            let cgImage = ctx.makeImage() else {
                return RenderOutput(
                    config: config,
                    imageUrl: filePath,
                    width: width,
                    height: height,
                    fileSize: 0,
                    success: false,
                    errorMessage: "Core Graphics PNG generation failed"
                )
            }
            
            guard let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: filePath) as CFURL,
                kUTTypePNG,
                1,
                nil
            ) else {
                return RenderOutput(
                    config: config,
                    imageUrl: filePath,
                    width: width,
                    height: height,
                    fileSize: 0,
                    success: false,
                    errorMessage: "CGImageDestination creation failed"
                )
            }
            
            CGImageDestinationAddImage(destination, cgImage, nil as CFDictionary?)
            
            guard CGImageDestinationFinalize(destination) else {
                return RenderOutput(
                    config: config,
                    imageUrl: filePath,
                    width: width,
                    height: height,
                    fileSize: 0,
                    success: false,
                    errorMessage: "CGImageDestination finalize failed"
                )
            }
            
            // Get file size
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64) ?? 0
            
            return RenderOutput(
                config: config,
                imageUrl: filePath,
                width: width,
                height: height,
                fileSize: fileSize,
                success: true
            )
        } catch {
            return RenderOutput(
                config: config,
                imageUrl: "",
                width: 0,
                height: 0,
                fileSize: 0,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
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
    
    // MARK: - Private helpers
    
    private struct Color3 {
        let r: Double, g: Double, b: Double
    }
    
    /// Returns the base RGB color for a material (normalized 0-1).
    private static func materialColor(for material: RenderMaterial) -> Color3 {
        switch material {
        case .aluminum:
            return Color3(r: 0.82, g: 0.84, b: 0.86)
        case .steel:
            return Color3(r: 0.55, g: 0.57, b: 0.60)
        case .copper:
            return Color3(r: 0.90, g: 0.65, b: 0.45)
        case .brass:
            return Color3(r: 0.95, g: 0.85, b: 0.45)
        case .titanium:
            return Color3(r: 0.50, g: 0.50, b: 0.55)
        case .wood:
            return Color3(r: 0.45, g: 0.30, b: 0.18)
        case .plastic:
            return Color3(r: 0.90, g: 0.90, b: 0.90)
        case .glass:
            return Color3(r: 0.95, g: 0.97, b: 0.98)
        case .custom:
            return Color3(r: 0.50, g: 0.50, b: 0.50)
        }
    }
    
    /// Returns a finish multiplier (brushed reduces specular, matte diffuses, etc.).
    private static func finishMultiplier(for finish: SurfaceFinish) -> Double {
        switch finish {
        case .matte: return 0.7
        case .brushed: return 0.8
        case .polished: return 1.0
        case .mirrored: return 1.0
        case .sandblasted: return 0.6
        case .anodized: return 0.75
        case .custom: return 0.8
        }
    }
    
    /// Procedural noise based on position and finish type.
    private static func finishNoise(x: Int, y: Int, finish: SurfaceFinish) -> Double {
        switch finish {
        case .matte:
            // High noise for diffuse surface
            return Double((x * 7 + y * 13) % 30) / 255.0 * 0.3
        case .brushed:
            // Directional streaks
            let streak = Double((x * 3) % 20) / 255.0
            return streak * 0.15
        case .polished:
            // Low noise
            return Double((x * 11 + y * 7) % 10) / 255.0 * 0.05
        case .mirrored:
            // Almost zero noise
            return Double((x * 17 + y * 31) % 5) / 255.0 * 0.02
        case .sandblasted:
            // Medium noise
            return Double((x * 13 + y * 17) % 40) / 255.0 * 0.25
        case .anodized:
            // Subtle variation
            return Double((x * 5 + y * 11) % 20) / 255.0 * 0.15
        case .custom:
            return Double((x * 7 + y * 13) % 25) / 255.0 * 0.2
        }
    }
}
