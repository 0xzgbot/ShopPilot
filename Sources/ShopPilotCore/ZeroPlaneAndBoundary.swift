import Foundation

// MARK: - Zero Plane + Boundary from Components

// Zero plane configuration.
public struct ZeroPlaneConfig: Codable, Sendable {
    public var planeZ: Double
    public var autoDetect: Bool
    public var offsetFromMinZ: Double
    public var offsetFromMaxZ: Double
    public var componentID: UUID?
    
    public init(
        planeZ: Double = 0.0,
        autoDetect: Bool = true,
        offsetFromMinZ: Double = 0.0,
        offsetFromMaxZ: Double = 0.0,
        componentID: UUID? = nil
    ) {
        self.planeZ = planeZ
        self.autoDetect = autoDetect
        self.offsetFromMinZ = offsetFromMinZ
        self.offsetFromMaxZ = offsetFromMaxZ
        self.componentID = componentID
    }
}

// Boundary source type.
public enum BoundarySource: String, Codable, Sendable {
    case componentBounds
    case customRectangle
    case customPolygon
    case jobSheetBounds
}

// A single polygon point.
public struct PolygonPoint: Codable, Sendable {
    public var x: Double
    public var y: Double
    
    public init(x: Double = 0.0, y: Double = 0.0) {
        self.x = x
        self.y = y
    }
}

// Boundary configuration.
public struct BoundaryConfig: Codable, Sendable {
    public var source: BoundarySource
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public var polygonPoints: [PolygonPoint]
    public var safetyMargin: Double
    public var componentID: UUID?
    
    public init(
        source: BoundarySource = .componentBounds,
        minX: Double = 0.0,
        minY: Double = 0.0,
        maxX: Double = 100.0,
        maxY: Double = 100.0,
        polygonPoints: [PolygonPoint] = [],
        safetyMargin: Double = 5.0,
        componentID: UUID? = nil
    ) {
        self.source = source
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.polygonPoints = polygonPoints
        self.safetyMargin = max(0.0, safetyMargin)
        self.componentID = componentID
    }
}

// Combined work area.
public struct WorkArea: Codable, Sendable {
    public var zeroPlane: ZeroPlaneConfig
    public var boundary: BoundaryConfig
    public var boundingBox: BoundingBox3D
    public var areaWidth: Double
    public var areaHeight: Double
    public var area: Double
    public var originX: Double
    public var originY: Double
    public var originZ: Double
    
    public init(
        zeroPlane: ZeroPlaneConfig,
        boundary: BoundaryConfig,
        boundingBox: BoundingBox3D,
        originX: Double = 0.0,
        originY: Double = 0.0,
        originZ: Double = 0.0
    ) {
        self.zeroPlane = zeroPlane
        self.boundary = boundary
        self.boundingBox = boundingBox
        self.areaWidth = max(0, boundary.maxX - boundary.minX)
        self.areaHeight = max(0, boundary.maxY - boundary.minY)
        self.area = self.areaWidth * self.areaHeight
        self.originX = originX
        self.originY = originY
        self.originZ = zeroPlane.planeZ
    }
}

// MARK: - ZeroPlaneAndBoundaryEngine

// Computes zero plane and boundary from components.
public final class ZeroPlaneAndBoundaryEngine {
    
    // Computes zero plane from component bounds.
    public static func computeZeroPlane(
        componentBoundingBox: BoundingBox3D,
        offsetFromMinZ: Double = 0.0
    ) -> Double {
        componentBoundingBox.minZ + offsetFromMinZ
    }
    
    // Computes boundary from component bounds with safety margin.
    public static func computeBoundary(
        componentBoundingBox: BoundingBox3D,
        safetyMargin: Double = 5.0
    ) -> BoundaryConfig {
        BoundaryConfig(
            source: .componentBounds,
            minX: componentBoundingBox.minX - safetyMargin,
            minY: componentBoundingBox.minY - safetyMargin,
            maxX: componentBoundingBox.maxX + safetyMargin,
            maxY: componentBoundingBox.maxY + safetyMargin,
            safetyMargin: safetyMargin
        )
    }
    
    // Computes complete work area from component.
    public static func computeWorkArea(
        componentBoundingBox: BoundingBox3D,
        zeroPlaneOffset: Double = 0.0,
        boundarySafetyMargin: Double = 5.0
    ) -> WorkArea {
        let zeroPlane = ZeroPlaneConfig(
            planeZ: computeZeroPlane(componentBoundingBox: componentBoundingBox, offsetFromMinZ: zeroPlaneOffset),
            autoDetect: true,
            offsetFromMinZ: zeroPlaneOffset
        )
        let boundary = computeBoundary(
            componentBoundingBox: componentBoundingBox,
            safetyMargin: boundarySafetyMargin
        )
        return WorkArea(
            zeroPlane: zeroPlane,
            boundary: boundary,
            boundingBox: componentBoundingBox
        )
    }
    
    // Computes work area from multiple components.
    public static func computeWorkArea(
        componentBoundingBoxes: [BoundingBox3D],
        zeroPlaneOffset: Double = 0.0,
        boundarySafetyMargin: Double = 5.0
    ) -> WorkArea {
        guard !componentBoundingBoxes.isEmpty else {
            let emptyBox = BoundingBox3D()
            return computeWorkArea(
                componentBoundingBox: emptyBox,
                zeroPlaneOffset: zeroPlaneOffset,
                boundarySafetyMargin: boundarySafetyMargin
            )
        }
        
        var mergedMinX = componentBoundingBoxes[0].minX
        var mergedMinY = componentBoundingBoxes[0].minY
        var mergedMinZ = componentBoundingBoxes[0].minZ
        var mergedMaxX = componentBoundingBoxes[0].maxX
        var mergedMaxY = componentBoundingBoxes[0].maxY
        var mergedMaxZ = componentBoundingBoxes[0].maxZ
        
        for box in componentBoundingBoxes[1...] {
            mergedMinX = min(mergedMinX, box.minX)
            mergedMinY = min(mergedMinY, box.minY)
            mergedMinZ = min(mergedMinZ, box.minZ)
            mergedMaxX = max(mergedMaxX, box.maxX)
            mergedMaxY = max(mergedMaxY, box.maxY)
            mergedMaxZ = max(mergedMaxZ, box.maxZ)
        }
        
        let mergedBox = BoundingBox3D(
            minX: mergedMinX,
            minY: mergedMinY,
            minZ: mergedMinZ,
            maxX: mergedMaxX,
            maxY: mergedMaxY,
            maxZ: mergedMaxZ
        )
        
        return computeWorkArea(
            componentBoundingBox: mergedBox,
            zeroPlaneOffset: zeroPlaneOffset,
            boundarySafetyMargin: boundarySafetyMargin
        )
    }
    
    // Validates work area configuration.
    public static func validate(_ workArea: WorkArea) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if workArea.areaWidth <= 0 {
            errors.append("Work area width must be positive")
        }
        if workArea.areaHeight <= 0 {
            errors.append("Work area height must be positive")
        }
        if workArea.boundary.safetyMargin < 0 {
            errors.append("Safety margin cannot be negative")
        }
        
        return (errors.isEmpty, errors)
    }
}
