import Foundation
import CoreGraphics
import ImageIO
import ShopPilotCore

// MARK: - Bitmap Trace Result

/// Result of tracing a bitmap into vector paths.
public struct BitmapTraceResult {
    
    /// The traced vector paths.
    public let paths: [VectorPath]
    
    /// Number of pixels processed.
    public let pixelCount: Int
    
    /// Trace quality settings used.
    public let quality: BitmapTraceQuality
    
    /// Whether any paths were traced.
    public var isEmpty: Bool { paths.isEmpty }
    
    /// Total length of all traced paths.
    public var totalLength: Double {
        paths.map(\.length).reduce(0, +)
    }
}

// MARK: - Trace Quality

/// Controls the quality and detail level of bitmap tracing.
public struct BitmapTraceQuality: Sendable {
    
    /// Threshold for pixel-to-path conversion (0.0–1.0).
    /// Higher = more detail, more paths.
    public var threshold: Double
    
    /// Minimum path length to include (in pixels).
    /// Shorter paths are discarded as noise.
    public var minPathLength: Double
    
    /// Whether to smooth the traced paths.
    public var smooth: Bool
    
    /// Whether to simplify paths (reduce point count).
    public var simplify: Bool
    
    /// Simplification tolerance (Douglas-Peucker).
    public var simplifyTolerance: Double
    
    /// Pixel resolution (pixels per mm).
    public var pixelsPerMm: Double
    
    /// Image format hint for diagnostics.
    public var imageFormat: String
    
    public init(
        threshold: Double = 0.5,
        minPathLength: Double = 3.0,
        smooth: Bool = true,
        simplify: Bool = true,
        simplifyTolerance: Double = 0.5,
        pixelsPerMm: Double = 10.0,
        imageFormat: String = "unknown"
    ) {
        self.threshold = threshold
        self.minPathLength = minPathLength
        self.smooth = smooth
        self.simplify = simplify
        self.simplifyTolerance = simplifyTolerance
        self.pixelsPerMm = pixelsPerMm
        self.imageFormat = imageFormat
    }
}

// MARK: - Bitmap Tracer

/// Converts raster bitmap images to vector paths for CNC toolpaths.
///
/// Uses edge detection (Sobel operator) to find contours,
/// then traces them into closed VectorPath objects suitable
/// for profile toolpaths.
public struct BitmapTracer {
    
    // MARK: - Public API
    
    /// Trace a bitmap (grayscale pixel array) into vector paths.
    ///
    /// - Parameters:
    ///   - pixels: 2D array of grayscale values (0.0 = black, 1.0 = white).
    ///   - quality: Trace quality settings.
    ///   - imageWidth: Width of the image in mm (for scale conversion).
    ///   - imageHeight: Height of the image in mm (for scale conversion).
    /// - Returns: BitmapTraceResult with traced paths.
    public static func trace(
        pixels: [[Double]],
        quality: BitmapTraceQuality = BitmapTraceQuality(),
        imageWidth: Double,
        imageHeight: Double
    ) -> BitmapTraceResult {
        
        let height = pixels.count
        guard height > 0 else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        let width = pixels[0].count
        guard width > 0 else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        let pixelCount = height * width
        
        // Step 1: Threshold the image to binary
        let binary = thresholdImage(pixels, threshold: quality.threshold)
        
        // Step 2: Detect edges using Sobel operator
        let edges = detectEdges(binary, width: width, height: height)
        
        // Step 3: Trace contours from edge map
        let rawPaths = traceContours(edges, width: width, height: height)
        
        // Step 4: Convert pixel coordinates to mm coordinate
        let scale = imageWidth / Double(width)
        let pathsInMm = rawPaths.map { path in
            VectorPath(
                id: UUID(),
                name: "",
                points: path.points.map { pt in
                    ShopPilotCore.VectorPoint(x: pt.x * scale, y: pt.y * scale)
                },
                isClosed: path.isClosed,
                layerId: UUID()
            )
        }
        
        // Step 5: Filter by minimum length
        let filteredPaths = pathsInMm.filter { $0.length >= quality.minPathLength }
        
        // Step 6: Smooth if requested
        let smoothedPaths = quality.smooth ? smoothPaths(filteredPaths) : filteredPaths
        
        // Step 7: Simplify if requested
        let finalPaths = quality.simplify ? simplifyPaths(smoothedPaths, tolerance: quality.simplifyTolerance) : smoothedPaths
        
        return BitmapTraceResult(
            paths: finalPaths,
            pixelCount: pixelCount,
            quality: quality
        )
    }
    
    /// Trace a bitmap from a URL (loads PNG/JPEG/BMP).
    ///
    /// - Parameters:
    ///   - url: URL of the image file.
    ///   - quality: Trace quality settings.
    ///   - imageWidth: Width of the image in mm.
    ///   - imageHeight: Height of the image in mm.
    /// - Returns: BitmapTraceResult with traced paths.
    public static func trace(
        from url: URL,
        quality: BitmapTraceQuality = BitmapTraceQuality(),
        imageWidth: Double,
        imageHeight: Double
    ) -> BitmapTraceResult {
        
        // Load image data
        guard let data = try? Data(contentsOf: url) else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        // Load image using CGImageSource (supports PNG, JPEG, BMP, TIFF, GIF, etc.)
        guard let cgImage = loadCGImage(from: data) else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        // Convert CGImage to grayscale pixel array
        guard let pixels = cgImageToGrayscalePixels(cgImage) else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        // Build quality with detected format info
        var adjustedQuality = quality
        adjustedQuality.imageFormat = imageFormat(from: data)
        
        return trace(
            pixels: pixels,
            quality: adjustedQuality,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
    }
    
    /// Trace a CGImage directly into vector paths.
    ///
    /// - Parameters:
    ///   - cgImage: A CoreGraphics image to trace.
    ///   - quality: Trace quality settings.
    ///   - imageWidth: Width of the image in mm.
    ///   - imageHeight: Height of the image in mm.
    /// - Returns: BitmapTraceResult with traced paths.
    public static func trace(
        cgImage: CGImage,
        quality: BitmapTraceQuality = BitmapTraceQuality(),
        imageWidth: Double,
        imageHeight: Double
    ) -> BitmapTraceResult {
        
        guard let pixels = cgImageToGrayscalePixels(cgImage) else {
            return BitmapTraceResult(paths: [], pixelCount: 0, quality: quality)
        }
        
        return trace(
            pixels: pixels,
            quality: quality,
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
    }
    
    // MARK: - Image Loading
    
    /// Load a CGImage from data, supporting PNG, JPEG, BMP, TIFF, GIF.
    private static func loadCGImage(from data: Data) -> CGImage? {
        guard let _ = CGDataProvider(data: data as CFData) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    
    /// Detect image format from data bytes.
    private static func imageFormat(from data: Data) -> String {
        guard data.count >= 4 else { return "unknown" }
        // PNG: starts with 0x89 0x50 0x4E 0x47
        let pngSig = Data([0x89, 0x50, 0x4E, 0x47])
        if data.starts(with: pngSig) { return "PNG" }
        // JPEG: starts with 0xFF 0xD8
        let jpegSig = Data([0xFF, 0xD8])
        if data.starts(with: jpegSig) { return "JPEG" }
        // BMP: starts with 'BM'
        let bmpSig = Data([0x42, 0x4D])
        if data.starts(with: bmpSig) { return "BMP" }
        // TIFF: starts with 'II' or 'MM'
        let tiffII = Data([0x49, 0x49])
        let tiffMM = Data([0x4D, 0x4D])
        if data.starts(with: tiffII) || data.starts(with: tiffMM) { return "TIFF" }
        return "unknown"
    }
    
    /// Convert a CGImage to a grayscale pixel array [[Double]].
    ///
    /// Uses a grayscale color space so that each pixel is a single 0–255 value.
    /// Returns nil if the image has zero dimensions or the color space conversion fails.
    private static func cgImageToGrayscalePixels(_ cgImage: CGImage) -> [[Double]]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }
        
        // Create a grayscale bitmap context
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        
        // Draw the image into the grayscale context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let imageData = context.data else {
            return nil
        }
        
        // Convert raw bytes to [[Double]] (0.0 = black, 1.0 = white)
        var pixels = Array(repeating: Array(repeating: 0.0, count: width), count: height)
        let bytePtr = imageData.bindMemory(to: UInt8.self, capacity: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = y * bytesPerRow + x
                pixels[y][x] = Double(bytePtr[byteIndex]) / 255.0
            }
        }
        
        return pixels
    }
    
    // MARK: - Private helpers
    
    /// Threshold image to binary (0.0 or 1.0).
    private static func thresholdImage(_ pixels: [[Double]], threshold: Double) -> [[Double]] {
        pixels.map { row in
            row.map { pixel in
                pixel >= threshold ? 1.0 : 0.0
            }
        }
    }
    
    /// Detect edges using Sobel operator.
    private static func detectEdges(_ binary: [[Double]], width: Int, height: Int) -> [[Double]] {
        var edges = Array(repeating: Array(repeating: 0.0, count: width), count: height)
        
        // Sobel kernels
        let sobelX = [
            [-1.0, 0.0, 1.0],
            [-2.0, 0.0, 2.0],
            [-1.0, 0.0, 1.0]
        ]
        
        let sobelY = [
            [-1.0, -2.0, -1.0],
            [ 0.0,  0.0,  0.0],
            [ 1.0,  2.0,  1.0]
        ]
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var gx = 0.0, gy = 0.0
                
                for ky in 0..<3 {
                    for kx in 0..<3 {
                        let pixel = binary[y + ky - 1][x + kx - 1]
                        gx += sobelX[ky][kx] * pixel
                        gy += sobelY[ky][kx] * pixel
                    }
                }
                
                edges[y][x] = sqrt(gx * gx + gy * gy)
            }
        }
        
        // Normalize to 0.0–1.0
        let maxEdge = edges.flatMap { $0 }.max() ?? 1.0
        if maxEdge > 0 {
            for y in 0..<height {
                for x in 0..<width {
                    edges[y][x] /= maxEdge
                }
            }
        }
        
        return edges
    }
    
    /// Trace contours from edge map using Moore boundary-following.
    private static func traceContours(_ edges: [[Double]], width: Int, height: Int) -> [Path2D] {
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        var paths: [Path2D] = []
        
        let threshold = 0.1 // Edge threshold for contour following
        
        for y in 0..<height {
            for x in 0..<width {
                // Find unvisited edge pixel
                guard edges[y][x] > threshold && !visited[y][x] else { continue }
                
                // Start a new contour
                let contour = followContour(edges, x: x, y: y, width: width, height: height, visited: &visited)
                if contour.points.count >= 3 {
                    paths.append(contour)
                }
            }
        }
        
        return paths
    }
    
    /// Follow a contour using Moore boundary-following algorithm.
    private static func followContour(
        _ edges: [[Double]],
        x: Int, y: Int,
        width: Int, height: Int,
        visited: inout [[Bool]]
    ) -> Path2D {
        var points: [ShopPilotCore.VectorPoint] = []
        var cx = x, cy = y
        var startDir = 0
        
        // Find starting direction (first edge neighbor)
        for dir in 0..<8 {
            let nx = cx + [-1, -1, 0, 1, 1, 1, 0, -1][dir]
            let ny = cy + [-1, 0, 1, 1, 0, -1, -1, -1][dir]
            if nx >= 0 && nx < width && ny >= 0 && ny < height && edges[ny][nx] > 0.1 {
                startDir = dir
                break
            }
        }
        
        var dir = startDir
        var iterations = 0
        let maxIterations = width * height // Prevent infinite loops
        
        while iterations < maxIterations {
            iterations += 1
            
            // Add current point
            points.append(ShopPilotCore.VectorPoint(x: Double(cx), y: Double(cy)))
            visited[cy][cx] = true
            
            // Move to next edge pixel in current direction
            let moved = moveAlongBoundary(edges, x: &cx, y: &cy, dir: &dir, width: width, height: height)
            if !moved { break }
            
            // Check if we've returned to start (closed contour)
            if points.count >= 5 && cx == x && cy == y {
                break
            }
        }
        
        return Path2D(points: points, isClosed: iterations < maxIterations)
    }
    
    /// Move along boundary to next edge pixel.
    private static func moveAlongBoundary(
        _ edges: [[Double]],
        x: inout Int, y: inout Int,
        dir: inout Int,
        width: Int, height: Int
    ) -> Bool {
        let dx = [-1, -1, 0, 1, 1, 1, 0, -1]
        let dy = [-1, 0, 1, 1, 0, -1, -1, -1]
        
        // Try current direction and neighbors (Moore following)
        for i in 0..<8 {
            let newDir = (dir + i - 4 + 8) % 8 // Search around current direction
            let nx = x + dx[newDir]
            let ny = y + dy[newDir]
            
            if nx >= 0 && nx < width && ny >= 0 && ny < height && edges[ny][nx] > 0.1 {
                x = nx
                y = ny
                dir = newDir
                return true
            }
        }
        
        return false
    }
    
    /// Smooth path using moving average.
    private static func smoothPaths(_ paths: [VectorPath]) -> [VectorPath] {
        paths.map { path in
            guard path.points.count > 2 else { return path }
            
            let smoothed = path.points.map { pt in
                ShopPilotCore.VectorPoint(x: Double(Int(pt.x.rounded())), y: Double(Int(pt.y.rounded())))
            }
            
            return VectorPath(id: path.id, name: path.name, points: smoothed, isClosed: path.isClosed, layerId: path.layerId)
        }
    }
    
    /// Simplify path using Douglas-Peucker algorithm.
    private static func simplifyPaths(_ paths: [VectorPath], tolerance: Double) -> [VectorPath] {
        paths.map { path in
            guard path.points.count > 2 else { return path }
            
            let simplified = douglasPeucker(path.points, tolerance: tolerance)
            
            return VectorPath(id: path.id, name: path.name, points: simplified, isClosed: path.isClosed, layerId: path.layerId)
        }
    }
    
    /// Douglas-Peucker line simplification.
    private static func douglasPeucker(_ points: [ShopPilotCore.VectorPoint], tolerance: Double) -> [ShopPilotCore.VectorPoint] {
        guard points.count > 2 else { return points }
        
        let squaredTolerance = tolerance * tolerance
        let first = points.first!
        let last = points.last!
        
        return recursiveSimplifyDP(points, first: first, last: last, tolerance: squaredTolerance)
    }
    
    private static func recursiveSimplifyDP(
        _ points: [ShopPilotCore.VectorPoint],
        first: ShopPilotCore.VectorPoint,
        last: ShopPilotCore.VectorPoint,
        tolerance: Double
    ) -> [ShopPilotCore.VectorPoint] {
        var maxDist = 0.0
        var maxIndex = 0
        
        for i in 1..<(points.count - 1) {
            let dist = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if dist > maxDist {
                maxDist = dist
                maxIndex = i
            }
        }
        
        if maxDist > tolerance {
            let left = recursiveSimplifyDP(points, first: first, last: points[maxIndex], tolerance: tolerance)
            let right = recursiveSimplifyDP(points, first: points[maxIndex], last: last, tolerance: tolerance)
            return left + [points[maxIndex]] + right
        }
        
        return [first, last]
    }
    
    /// Calculate perpendicular distance from point to line.
    private static func perpendicularDistance(_ point: ShopPilotCore.VectorPoint, lineStart: ShopPilotCore.VectorPoint, lineEnd: ShopPilotCore.VectorPoint) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return hypot(point.x - lineStart.x, point.y - lineStart.y) }
        
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
        let projectionX = lineStart.x + t * dx
        let projectionY = lineStart.y + t * dy
        
        return hypot(point.x - projectionX, point.y - projectionY)
    }
}

// MARK: - Path2D

/// Simple 2D path representation for internal use.
private struct Path2D {
    let points: [ShopPilotCore.VectorPoint]
    let isClosed: Bool
}
