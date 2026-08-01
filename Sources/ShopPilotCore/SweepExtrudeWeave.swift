import Foundation

// MARK: - Two-Rail Sweep, Extrude, Weave

// Sweep profile type.
public enum SweepProfile: String, Codable, Sendable {
    case rectangle
    case circle
    case ellipse
    case custom
    case path
}

// Extrude type.
public enum ExtrudeType: String, Codable, Sendable {
    case normal
    case directional
    case tapered
    case draft
}

// Weave pattern type.
public enum WeavePattern: String, Codable, Sendable {
    case plain
    case twill
    case satin
    case basket
    case custom
}

// 2D point for path definition.
public struct Point2D: Codable, Sendable {
    public var x: Double
    public var y: Double
    
    public init(x: Double = 0.0, y: Double = 0.0) {
        self.x = x
        self.y = y
    }
}

// Sweep profile parameters.
public struct SweepProfileParams: Codable, Sendable {
    public var profile: SweepProfile
    public var width: Double
    public var height: Double
    public var radius: Double
    public var cornerRadius: Double
    public var segments: Int
    
    public init(
        profile: SweepProfile = .rectangle,
        width: Double = 10.0,
        height: Double = 10.0,
        radius: Double = 5.0,
        cornerRadius: Double = 0.0,
        segments: Int = 32
    ) {
        self.profile = profile
        self.width = max(0.01, width)
        self.height = max(0.01, height)
        self.radius = max(0.01, radius)
        self.cornerRadius = max(0.0, cornerRadius)
        self.segments = max(3, min(256, segments))
    }
}

// Two-rail sweep parameters.
public struct TwoRailSweepParams: Codable, Sendable {
    public var rail1Points: [Point2D]
    public var rail2Points: [Point2D]
    public var profile: SweepProfileParams
    public var numberOfProfiles: Int
    public var closed: Bool
    public var twistAngle: Double
    
    public init(
        rail1Points: [Point2D] = [],
        rail2Points: [Point2D] = [],
        profile: SweepProfileParams = SweepProfileParams(),
        numberOfProfiles: Int = 20,
        closed: Bool = false,
        twistAngle: Double = 0.0
    ) {
        self.rail1Points = rail1Points
        self.rail2Points = rail2Points
        self.profile = profile
        self.numberOfProfiles = max(2, numberOfProfiles)
        self.closed = closed
        self.twistAngle = twistAngle
    }
}

// Extrude parameters.
public struct ExtrudeParams: Codable, Sendable {
    public var extrudeType: ExtrudeType
    public var distance: Double
    public var direction: Vector3D
    public var taperAngle: Double
    public var draftAngle: Double
    public var bilateral: Bool
    public var draftDirection: Vector3D
    
    public init(
        extrudeType: ExtrudeType = .normal,
        distance: Double = 10.0,
        direction: Vector3D = Vector3D(x: 0, y: 0, z: 1),
        taperAngle: Double = 0.0,
        draftAngle: Double = 0.0,
        bilateral: Bool = false,
        draftDirection: Vector3D = Vector3D(x: 0, y: 0, z: 1)
    ) {
        self.extrudeType = extrudeType
        self.distance = max(0.0, distance)
        self.direction = direction
        self.taperAngle = taperAngle
        self.draftAngle = draftAngle
        self.bilateral = bilateral
        self.draftDirection = draftDirection
    }
}

// Weave parameters.
public struct WeaveParams: Codable, Sendable {
    public var pattern: WeavePattern
    public var threadSize: Double
    public var spacing: Double
    public var warpCount: Int
    public var weftCount: Int
    public var overlap: Double
    public var tension: Double
    
    public init(
        pattern: WeavePattern = .plain,
        threadSize: Double = 1.0,
        spacing: Double = 2.0,
        warpCount: Int = 20,
        weftCount: Int = 20,
        overlap: Double = 0.5,
        tension: Double = 0.5
    ) {
        self.pattern = pattern
        self.threadSize = max(0.01, threadSize)
        self.spacing = max(0.01, spacing)
        self.warpCount = max(1, warpCount)
        self.weftCount = max(1, weftCount)
        self.overlap = max(0.0, min(1.0, overlap))
        self.tension = max(0.0, min(1.0, tension))
    }
}

// 3D sweep/extrude/weave result.
public struct SweepExtrudeWeaveResult: Codable, Sendable {
    public var operation: String
    public var componentID: UUID
    public var newComponentIDs: [UUID]
    public var volumeMM3: Double
    public var surfaceAreaMM2: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        operation: String,
        componentID: UUID,
        newComponentIDs: [UUID] = [],
        volumeMM3: Double = 0.0,
        surfaceAreaMM2: Double = 0.0,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.operation = operation
        self.componentID = componentID
        self.newComponentIDs = newComponentIDs
        self.volumeMM3 = volumeMM3
        self.surfaceAreaMM2 = surfaceAreaMM2
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - SweepExtrudeWeaveEngine

// Performs two-rail sweep, extrude, and weave operations.
public final class SweepExtrudeWeaveEngine {
    
    // Performs a two-rail sweep.
    public static func twoRailSweep(
        componentID: UUID,
        params: TwoRailSweepParams
    ) -> SweepExtrudeWeaveResult {
        guard params.rail1Points.count >= 2 else {
            return SweepExtrudeWeaveResult(
                operation: "twoRailSweep",
                componentID: componentID,
                success: false,
                errorMessage: "Rail 1 must have at least 2 points"
            )
        }
        guard params.rail2Points.count >= 2 else {
            return SweepExtrudeWeaveResult(
                operation: "twoRailSweep",
                componentID: componentID,
                success: false,
                errorMessage: "Rail 2 must have at least 2 points"
            )
        }
        
        guard params.rail1Points.count == params.rail2Points.count else {
            return SweepExtrudeWeaveResult(
                operation: "twoRailSweep",
                componentID: componentID,
                success: false,
                errorMessage: "Both rails must have the same number of points"
            )
        }
        
        let avgRailLength = averagePathLength(points: params.rail1Points)
        let profileArea = calculateProfileArea(params.profile)
        let volume = avgRailLength * profileArea
        let surfaceArea = avgRailLength * (params.profile.width + params.profile.height)
        
        return SweepExtrudeWeaveResult(
            operation: "twoRailSweep",
            componentID: componentID,
            newComponentIDs: [componentID],
            volumeMM3: volume,
            surfaceAreaMM2: surfaceArea,
            success: true
        )
    }
    
    // Performs an extrude operation.
    public static func extrude(
        componentID: UUID,
        params: ExtrudeParams,
        boundingBox: BoundingBox3D
    ) -> SweepExtrudeWeaveResult {
        let dirMag = sqrt(params.direction.x * params.direction.x + params.direction.y * params.direction.y + params.direction.z * params.direction.z)
        if dirMag < 0.001 {
            return SweepExtrudeWeaveResult(
                operation: "extrude",
                componentID: componentID,
                success: false,
                errorMessage: "Extrusion direction must not be zero"
            )
        }
        
        let baseArea = boundingBox.width * boundingBox.height
        let effectiveDistance = params.bilateral ? params.distance * 2 : params.distance
        let volume = baseArea * effectiveDistance
        let perimeter = 2 * (boundingBox.width + boundingBox.height)
        let sideArea = perimeter * effectiveDistance
        let topArea = baseArea
        let surfaceArea = sideArea + topArea * 2
        
        return SweepExtrudeWeaveResult(
            operation: "extrude",
            componentID: componentID,
            newComponentIDs: [componentID],
            volumeMM3: volume,
            surfaceAreaMM2: surfaceArea,
            success: true
        )
    }
    
    // Performs a weave operation.
    public static func weave(
        componentID: UUID,
        params: WeaveParams,
        boundingBox: BoundingBox3D
    ) -> SweepExtrudeWeaveResult {
        if params.warpCount <= 0 || params.weftCount <= 0 {
            return SweepExtrudeWeaveResult(
                operation: "weave",
                componentID: componentID,
                success: false,
                errorMessage: "Warp and weft counts must be positive"
            )
        }
        
        let totalThreadLength = Double(params.warpCount + params.weftCount) * max(boundingBox.width, boundingBox.height)
        let threadCrossSection = params.threadSize * params.threadSize
        let volume = totalThreadLength * threadCrossSection * params.overlap
        let surfaceArea = totalThreadLength * params.threadSize * 2
        
        return SweepExtrudeWeaveResult(
            operation: "weave",
            componentID: componentID,
            newComponentIDs: [componentID],
            volumeMM3: volume,
            surfaceAreaMM2: surfaceArea,
            success: true
        )
    }
    
    // Run any sweep/extrude/weave operation.
    public static func run(
        operation: String,
        componentID: UUID,
        params: Any,
        boundingBox: BoundingBox3D = BoundingBox3D()
    ) -> SweepExtrudeWeaveResult {
        switch operation {
        case "twoRailSweep":
            guard let p = params as? TwoRailSweepParams else {
                return SweepExtrudeWeaveResult(operation: "twoRailSweep", componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return twoRailSweep(componentID: componentID, params: p)
        case "extrude":
            guard let p = params as? ExtrudeParams else {
                return SweepExtrudeWeaveResult(operation: "extrude", componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return extrude(componentID: componentID, params: p, boundingBox: boundingBox)
        case "weave":
            guard let p = params as? WeaveParams else {
                return SweepExtrudeWeaveResult(operation: "weave", componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return weave(componentID: componentID, params: p, boundingBox: boundingBox)
        default:
            return SweepExtrudeWeaveResult(
                operation: operation,
                componentID: componentID,
                success: false,
                errorMessage: "Unknown operation: \(operation)"
            )
        }
    }
    
    // Validates operation parameters.
    public static func validate(operation: String, params: Any) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        switch operation {
        case "twoRailSweep":
            guard let p = params as? TwoRailSweepParams else {
                return (false, ["Invalid params type"])
            }
            if p.rail1Points.count < 2 { errors.append("Rail 1 needs at least 2 points") }
            if p.rail2Points.count < 2 { errors.append("Rail 2 needs at least 2 points") }
            if p.rail1Points.count != p.rail2Points.count { errors.append("Rails must have equal points") }
        case "extrude":
            guard let p = params as? ExtrudeParams else {
                return (false, ["Invalid params type"])
            }
            let mag = sqrt(p.direction.x * p.direction.x + p.direction.y * p.direction.y + p.direction.z * p.direction.z)
            if mag < 0.001 { errors.append("Direction must not be zero") }
        case "weave":
            guard let p = params as? WeaveParams else {
                return (false, ["Invalid params type"])
            }
            if p.warpCount <= 0 { errors.append("Warp count must be positive") }
            if p.weftCount <= 0 { errors.append("Weft count must be positive") }
        default:
            errors.append("Unknown operation: \(operation)")
        }
        
        return (errors.isEmpty, errors)
    }
    
    private static func averagePathLength(points: [Point2D]) -> Double {
        guard points.count >= 2 else { return 0 }
        var totalLength: Double = 0
        for i in 0..<(points.count - 1) {
            let dx = points[i + 1].x - points[i].x
            let dy = points[i + 1].y - points[i].y
            totalLength += sqrt(dx * dx + dy * dy)
        }
        return totalLength / Double(points.count - 1)
    }
    
    private static func calculateProfileArea(_ profile: SweepProfileParams) -> Double {
        switch profile.profile {
        case .rectangle:
            return profile.width * profile.height
        case .circle:
            return .pi * profile.radius * profile.radius
        case .ellipse:
            return .pi * (profile.width / 2) * (profile.height / 2)
        case .custom, .path:
            return profile.width * profile.height
        }
    }
}
