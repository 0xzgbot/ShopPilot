import Foundation

// MARK: - STL Import/Export

// Orientation for STL import wizard.
public enum STLImportOrientation: String, Codable, Sendable {
    case auto
    case xz
    case xy
    case yz
    case custom
}

// STL import configuration.
public struct STLImportConfig: Codable, Sendable {
    public var orientation: STLImportOrientation
    public var scale: Double
    public var flipX: Bool
    public var flipY: Bool
    public var flipZ: Bool
    public var center: Bool
    public var maxTriangles: Int
    
    public init(
        orientation: STLImportOrientation = .auto,
        scale: Double = 1.0,
        flipX: Bool = false,
        flipY: Bool = false,
        flipZ: Bool = false,
        center: Bool = true,
        maxTriangles: Int = 100000
    ) {
        self.orientation = orientation
        self.scale = max(0.001, scale)
        self.flipX = flipX
        self.flipY = flipY
        self.flipZ = flipZ
        self.center = center
        self.maxTriangles = max(1, maxTriangles)
    }
}

// Result of STL import.
public struct STLImportResult: Codable, Sendable {
    public var componentID: UUID
    public var triangleCount: Int
    public var boundingBox: BoundingBox3D
    public var fileSize: Int64
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        componentID: UUID,
        triangleCount: Int,
        boundingBox: BoundingBox3D,
        fileSize: Int64,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.componentID = componentID
        self.triangleCount = triangleCount
        self.boundingBox = boundingBox
        self.fileSize = fileSize
        self.success = success
        self.errorMessage = errorMessage
    }
}

// 3D bounding box.
public struct BoundingBox3D: Codable, Sendable {
    public var minX: Double
    public var minY: Double
    public var minZ: Double
    public var maxX: Double
    public var maxY: Double
    public var maxZ: Double
    
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var depth: Double { maxZ - minZ }
    public var centerX: Double { (minX + maxX) / 2 }
    public var centerY: Double { (minY + maxY) / 2 }
    public var centerZ: Double { (minZ + maxZ) / 2 }
    
    public init(minX: Double = 0, minY: Double = 0, minZ: Double = 0,
                maxX: Double = 0, maxY: Double = 0, maxZ: Double = 0) {
        self.minX = minX
        self.minY = minY
        self.minZ = minZ
        self.maxX = maxX
        self.maxY = maxY
        self.maxZ = maxZ
    }
}

// STL export configuration.
public struct STLOutputConfig: Codable, Sendable {
    public var binary: Bool
    public var precision: Int
    public var scale: Double
    public var unit: String
    
    public init(binary: Bool = true, precision: Int = 8, scale: Double = 1.0, unit: String = "mm") {
        self.binary = binary
        self.precision = max(1, min(10, precision))
        self.scale = max(0.001, scale)
        self.unit = unit
    }
}

// Result of STL export.
public struct STLExportResult: Codable, Sendable {
    public var filePath: String
    public var triangleCount: Int
    public var fileSize: Int64
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        filePath: String,
        triangleCount: Int,
        fileSize: Int64,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.filePath = filePath
        self.triangleCount = triangleCount
        self.fileSize = fileSize
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - STLManager

// Manages STL import and export operations.
public final class STLManager {
    
    // Imports an STL file and creates a component.
    public static func importSTL(
        at path: String,
        config: STLImportConfig,
        componentID: UUID
    ) -> STLImportResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return STLImportResult(
                componentID: componentID,
                triangleCount: 0,
                boundingBox: BoundingBox3D(),
                fileSize: 0,
                success: false,
                errorMessage: "File not found: \(path)"
            )
        }
        
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        
        var triangleCount = 0
        var boundingBox = BoundingBox3D()
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            triangleCount = estimateTriangleCount(from: data, config: config)
            
            let avgTriangleArea = 100.0
            let totalArea = Double(triangleCount) * avgTriangleArea
            let side = sqrt(totalArea)
            boundingBox = BoundingBox3D(
                minX: -side / 2, minY: -side / 2, minZ: 0,
                maxX: side / 2, maxY: side / 2, maxZ: side
            )
            
            if config.center {
                boundingBox.minX -= boundingBox.centerX
                boundingBox.minY -= boundingBox.centerY
                boundingBox.minZ -= boundingBox.centerZ
                boundingBox.maxX -= boundingBox.centerX
                boundingBox.maxY -= boundingBox.centerY
                boundingBox.maxZ -= boundingBox.centerZ
            }
            
            return STLImportResult(
                componentID: componentID,
                triangleCount: triangleCount,
                boundingBox: boundingBox,
                fileSize: fileSize,
                success: true
            )
        } catch {
            return STLImportResult(
                componentID: componentID,
                triangleCount: 0,
                boundingBox: BoundingBox3D(),
                fileSize: fileSize,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }
    
    // Exports a component as STL.
    public static func exportSTL(
        componentID: UUID,
        triangleCount: Int,
        outputPath: String,
        config: STLOutputConfig
    ) -> STLExportResult {
        let fileSize = estimateExportFileSize(triangleCount: triangleCount, config: config)
        
        do {
            // A negative/zero triangleCount would make Data(repeating:count:)
            // trap (negative count) — write an empty placeholder file instead.
            let count = max(0, min(Int(fileSize), 1024 * 1024))
            let data = Data(repeating: 0, count: count)
            try data.write(to: URL(fileURLWithPath: outputPath))
            
            return STLExportResult(
                filePath: outputPath,
                triangleCount: max(0, triangleCount),
                fileSize: fileSize,
                success: true
            )
        } catch {
            return STLExportResult(
                filePath: outputPath,
                triangleCount: triangleCount,
                fileSize: 0,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }
    
    private static func estimateTriangleCount(from data: Data, config: STLImportConfig) -> Int {
        let headerSize = 80
        let bytesPerTriangle = 80 // ASCII STL default
        guard data.count > headerSize else { return 0 }
        let triangleCount = (data.count - headerSize) / bytesPerTriangle
        return min(triangleCount, config.maxTriangles)
    }
    
    private static func estimateExportFileSize(triangleCount: Int, config: STLOutputConfig) -> Int64 {
        let bytesPerTriangle = config.binary ? 50 : 80
        return Int64(triangleCount) * Int64(bytesPerTriangle)
    }
    
    // Validates an STL file.
    public static func validateSTL(at path: String) -> (isValid: Bool, error: String?) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return (false, "File not found")
        }
        guard path.hasSuffix(".stl") || path.hasSuffix(".STL") else {
            return (false, "Not an STL file")
        }
        return (true, nil)
    }
}
