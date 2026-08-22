import Foundation
import CoreGraphics
import ImageIO

// MARK: - Bitmap → Heightfield (SPK-0706 lean slice)

/// Configuration for converting an image's brightness into a heightmap.
///
/// Semantics match the standard "Component from bitmap" convention: white = peak, black =
/// floor; `maxHeightMm` is the tallest relief point. `mmPerPixel` scales the
/// image's pixel grid into world millimeters; `invert` flips the mapping so
/// dark = peak (useful for photographs scanned dark-on-light).
public struct BitmapHeightfieldConfig: Codable, Sendable {
    public var mmPerPixel: Double
    public var maxHeightMm: Double
    public var invert: Bool
    public var smoothingPasses: Int
    public var maxCells: Int

    public init(
        mmPerPixel: Double = 1.0,
        maxHeightMm: Double = 10.0,
        invert: Bool = false,
        smoothingPasses: Int = 1,
        maxCells: Int = 600
    ) {
        self.mmPerPixel = max(0.01, mmPerPixel)
        self.maxHeightMm = max(0.0, maxHeightMm)
        self.invert = invert
        self.smoothingPasses = min(10, max(0, smoothingPasses))
        self.maxCells = min(1200, max(16, maxCells))
    }
}

public struct BitmapHeightfieldResult: Sendable {
    public let heightfield: HeightfieldData?
    public let widthPx: Int
    public let heightPx: Int
    public let success: Bool
    public let errorMessage: String?
}

public enum BitmapHeightfieldError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case noImage(String)
    case noPixels(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "Image file not found: \(p)"
        case .unreadable(let m): return "Image unreadable: \(m)"
        case .noImage(let m): return "No image data found: \(m)"
        case .noPixels(let m): return "No pixel data: \(m)"
        }
    }
}

/// Converts grayscale pixel grids and image files into `HeightfieldData`
/// reliefs. The output reuses the STL relief slot, so the Model stage and the
/// 3D rough/finish engines consume bitmap reliefs with zero extra work.
public enum BitmapHeightfieldImporter {

    // MARK: - Build from raw grayscale pixels

    /// Convert a row-major grayscale pixel grid (0.0 = black … 1.0 = white)
    /// into a `HeightfieldData` relief. World origin at (0, 0); each grid cell
    /// is `mmPerPixel × downscaleFactor` mm square; height = pixel × maxHeight.
    public static func build(
        fromPixels pixels: [Double],
        width: Int,
        height: Int,
        config: BitmapHeightfieldConfig
    ) -> BitmapHeightfieldResult {
        guard width >= 1, height >= 1, pixels.count == width * height else {
            return BitmapHeightfieldResult(
                heightfield: nil, widthPx: width, heightPx: height,
                success: false,
                errorMessage: "Pixel data (\(pixels.count)) does not match \(width)×\(height)"
            )
        }
        var work = pixels
        if config.smoothingPasses > 0 {
            work = smooth2D(work, width: width, height: height, passes: config.smoothingPasses)
        }
        // Downsample to fit maxCells (box average keeps total brightness).
        let (grid, gw, gh) = downsampleBoxAverage(
            work, width: width, height: height, maxCells: config.maxCells
        )
        var heights = [Double](repeating: 0, count: gw * gh)
        for i in 0..<(gw * gh) {
            let mapped = config.invert ? (1.0 - grid[i]) : grid[i]
            heights[i] = mapped * config.maxHeightMm
        }
        // Square cell must cover the aggregated source area in BOTH axes.
        let cell = max(Double(width) / Double(gw), Double(height) / Double(gh)) * config.mmPerPixel
        let hf = HeightfieldData(
            width: gw, height: gh,
            cellSizeMm: cell,
            minX: 0, minY: 0,
            heights: heights
        )
        return BitmapHeightfieldResult(
            heightfield: hf, widthPx: width, heightPx: height,
            success: true, errorMessage: nil
        )
    }

    // MARK: - Decode from an image file

    /// Load an image file (PNG/JPEG/TIFF/BMP… via ImageIO), convert it to a
    /// row-major top-down grayscale grid, then build the heightfield. Large
    /// images are downscaled WHILE decoding (thumbnail ≤ `maxCells` px).
    public static func decodeImage(
        at url: URL,
        config: BitmapHeightfieldConfig
    ) -> BitmapHeightfieldResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BitmapHeightfieldResult(
                heightfield: nil, widthPx: 0, heightPx: 0, success: false,
                errorMessage: BitmapHeightfieldError.fileNotFound(url.path).localizedDescription
            )
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return BitmapHeightfieldResult(
                heightfield: nil, widthPx: 0, heightPx: 0, success: false,
                errorMessage: BitmapHeightfieldError.unreadable(url.lastPathComponent).localizedDescription
            )
        }
        let image: CGImage?
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: config.maxCells,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) {
            image = thumb
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let cg = image else {
            return BitmapHeightfieldResult(
                heightfield: nil, widthPx: 0, heightPx: 0, success: false,
                errorMessage: BitmapHeightfieldError.noImage(url.lastPathComponent).localizedDescription
            )
        }
        let grayscale = grayscalePixels(from: cg)
        guard !grayscale.isEmpty else {
            return BitmapHeightfieldResult(
                heightfield: nil, widthPx: 0, heightPx: 0, success: false,
                errorMessage: BitmapHeightfieldError.noPixels(url.lastPathComponent).localizedDescription
            )
        }
        return build(fromPixels: grayscale, width: cg.width, height: cg.height, config: config)
    }

    // MARK: - 2D smoothing

    /// 2D box blur with a [1,2,1;2,4,2;1,2,1]/16 kernel, edges replicated.
    /// Genuinely 2D: a value is diluted by its 2D neighborhood (a horizontal
    /// neighbor dilutes a vertical line), unlike a naive 1D pass.
    static func smooth2D(_ pixels: [Double], width: Int, height: Int, passes: Int) -> [Double] {
        var src = pixels
        var dst = pixels
        let kx = [1, 2, 1]
        let ky = [1, 2, 1]
        for _ in 0..<passes {
            for y in 0..<height {
                for x in 0..<width {
                    var acc = 0.0
                    var wSum = 0.0
                    for dy in -1...1 {
                        let yy = min(height - 1, max(0, y + dy))
                        for dx in -1...1 {
                            let xx = min(width - 1, max(0, x + dx))
                            let k = kx[dx + 1] * ky[dy + 1]
                            acc += src[yy * width + xx] * Double(k)
                            wSum += Double(k)
                        }
                    }
                    dst[y * width + x] = acc / wSum
                }
            }
            swap(&src, &dst)
        }
        return src
    }

    // MARK: - Downsampling

    /// Box-average downsample so both dims fit `maxCells`. No-op when already
    /// within limits. A uniform field survives with the same value.
    static func downsampleBoxAverage(
        _ pixels: [Double], width: Int, height: Int, maxCells: Int
    ) -> (pixels: [Double], width: Int, height: Int) {
        let maxSide = max(width, height)
        guard maxSide > maxCells else { return (pixels, width, height) }
        let factor = Double(maxSide) / Double(maxCells)
        let gw = max(1, Int(ceil(Double(width) / factor)))
        let gh = max(1, Int(ceil(Double(height) / factor)))
        var out = [Double](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            let y0 = Int((Double(gy) * Double(height)) / Double(gh))
            let y1 = max(y0 + 1, Int((Double(gy + 1) * Double(height)) / Double(gh)))
            for gx in 0..<gw {
                let x0 = Int((Double(gx) * Double(width)) / Double(gw))
                let x1 = max(x0 + 1, Int((Double(gx + 1) * Double(width)) / Double(gw)))
                var acc = 0.0
                var n = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        acc += pixels[y * width + x]
                        n += 1
                    }
                }
                out[gy * gw + gx] = n > 0 ? acc / Double(n) : 0
            }
        }
        return (out, gw, gh)
    }

    // MARK: - Grayscale conversion

    /// Render a CGImage into a row-major TOP-DOWN grayscale [0…1] buffer.
    /// Drawing into a device-gray context performs the colorspace conversion
    /// (sRGB/whatever → luminance). Empirically the bitmap context memory is
    /// already top-down (row 0 = image top), so no row flip is applied.
    public static func grayscalePixels(from image: CGImage) -> [Double] {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &buf, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out = [Double](repeating: 0, count: w * h)
        buf.withUnsafeBufferPointer { bp in
            guard let base = bp.baseAddress else { return }
            for i in 0..<(w * h) {
                out[i] = Double(base[i]) / 255.0
            }
        }
        return out
    }
}
