import Foundation

// MARK: - Bitmap to Component

/// Represents a bitmap image that can be converted to a 3D component.
public struct BitmapSource: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// Display name
    public var name: String
    
    /// Image data (base64 encoded)
    public var imageData: String
    
    /// Image width in pixels
    public var width: Int
    
    /// Image height in pixels
    
    public var height: Int
    
    /// Pixel data (array of grayscale values 0.0-1.0)
    public var pixels: [Double]
    
    /// Threshold for bitmap tracing
    public var threshold: Double
    
    /// Active
    public var active: Bool
    
    public init(
        id: UUID = UUID(),
        name: String = "Bitmap",
        imageData: String = "",
        width: Int = 256,
        height: Int = 256,
        pixels: [Double] = [],
        threshold: Double = 0.5,
        active: Bool = true
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.width = max(1, width)
        self.height = max(1, height)
        self.pixels = pixels
        self.threshold = max(0.0, min(1.0, threshold))
        self.active = active
    }
}

/// Configuration for bitmap-to-component conversion.
public struct BitmapComponentConfig: Codable, Sendable {
    /// Scale factor: how many mm per pixel
    public var scale: Double
    
    /// Max height of the resulting component
    public var maxHeight: Double
    
    /// Invert the height map (dark = high, light = low)
    public var invert: Bool
    
    /// Smoothing passes
    public var smoothing: Int
    
    /// Use edges for detail
    public var useEdges: Bool
    
    public init(
        scale: Double = 0.1,
        maxHeight: Double = 50.0,
        invert: Bool = false,
        smoothing: Int = 1,
        useEdges: Bool = false
    ) {
        self.scale = max(0.01, scale)
        self.maxHeight = max(0.0, maxHeight)
        self.invert = invert
        self.smoothing = max(0, min(10, smoothing))
        self.useEdges = useEdges
    }
}

/// Result of bitmap-to-component conversion.
public struct BitmapComponentResult: Codable, Sendable {
    /// The resulting component ID
    public var componentID: UUID
    
    /// Width in mm
    public var widthMM: Double
    
    /// Height in mm
    public var heightMM: Double
    
    /// Max depth in mm
    public var maxDepth: Double
    
    /// Number of pixels processed
    public var pixelCount: Int
    
    /// Success
    public var success: Bool
    
    /// Error message if failed
    public var errorMessage: String?
    
    public init(
        componentID: UUID,
        widthMM: Double,
        heightMM: Double,
        maxDepth: Double,
        pixelCount: Int,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.componentID = componentID
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.maxDepth = maxDepth
        self.pixelCount = pixelCount
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - BitmapComponentEngine

/// Converts bitmap images to 3D components.
public final class BitmapComponentEngine {
    
    /// Converts a bitmap source to a 3D component with the given config.
    /// - Parameters:
    ///   - source: The bitmap source to convert.
    ///   - config: Conversion configuration.
    ///   - componentID: The component this bitmap will create.
    /// - Returns: The conversion result.
    public static func convert(
        _ source: BitmapSource,
        config: BitmapComponentConfig,
        componentID: UUID
    ) -> BitmapComponentResult {
        guard !source.pixels.isEmpty else {
            return BitmapComponentResult(
                componentID: componentID,
                widthMM: 0,
                heightMM: 0,
                maxDepth: 0,
                pixelCount: 0,
                success: false,
                errorMessage: "No pixel data"
            )
        }
        
        let widthMM = Double(source.width) * config.scale
        let heightMM = Double(source.height) * config.scale
        
        // Calculate max depth from pixel data
        var maxPixel: Double = 0.0
        for pixel in source.pixels {
            let adjusted = config.invert ? (1.0 - pixel) : pixel
            maxPixel = max(maxPixel, adjusted)
        }
        let maxDepth = maxPixel * config.maxHeight
        
        // Apply smoothing
        let smoothedPixels = applySmoothing(source.pixels, passes: config.smoothing)
        
        return BitmapComponentResult(
            componentID: componentID,
            widthMM: widthMM,
            heightMM: heightMM,
            maxDepth: maxDepth,
            pixelCount: smoothedPixels.count,
            success: true
        )
    }
    
    /// Applies Gaussian-like smoothing to pixel data.
    private static func applySmoothing(_ pixels: [Double], passes: Int) -> [Double] {
        var result = pixels
        for _ in 0..<passes {
            result = smoothOnce(result)
        }
        return result
    }
    
    /// Applies one pass of smoothing.
    private static func smoothOnce(_ pixels: [Double]) -> [Double] {
        guard pixels.count > 2 else { return pixels }
        var result = pixels
        for i in 1..<pixels.count - 1 {
            result[i] = (pixels[i-1] + pixels[i] * 2 + pixels[i+1]) / 4.0
        }
        return result
    }
    
    /// Validates bitmap source data.
    public static func validate(_ source: BitmapSource) -> (isValid: Bool, error: String?) {
        if source.width <= 0 || source.height <= 0 {
            return (false, "Invalid dimensions: \(source.width)x\(source.height)")
        }
        if source.pixels.isEmpty {
            return (false, "No pixel data")
        }
        if source.pixels.count != source.width * source.height {
            return (false, "Pixel count (\(source.pixels.count)) does not match dimensions (\(source.width)x\(source.height) = \(source.width * source.height))")
        }
        for pixel in source.pixels {
            if pixel < 0.0 || pixel > 1.0 {
                return (false, "Pixel value out of range: \(pixel)")
            }
        }
        return (true, nil)
    }
}
