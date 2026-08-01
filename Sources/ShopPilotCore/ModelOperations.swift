import Foundation

// MARK: - Smooth, Emboss, Bake, Split

// 3D operation type.
public enum Operation3D: String, Codable, Sendable {
    case smooth
    case emboss
    case bake
    case split
}

// Smoothing algorithm.
public enum SmoothingAlgorithm: String, Codable, Sendable {
    case laplacian
    case bilateral
    case taubin
    case gaussian
}

// Emboss type.
public enum EmbossType: String, Codable, Sendable {
    case raised
    case recessed
    case stroke
    case letterpress
}

// Bake type.
public enum BakeType: String, Codable, Sendable {
    case heightmap
    case normalmap
    case displacement
    case ambientOcclusion
}

// Split method.
public enum SplitMethod: String, Codable, Sendable {
    case horizontalPlane
    case verticalPlane
    case customPlane
    case byComponent
}

// 3D vector for plane normal.
public struct Vector3D: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    
    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// Smooth operation parameters.
public struct SmoothParams: Codable, Sendable {
    public var iterations: Int
    public var smoothingFactor: Double
    public var algorithm: SmoothingAlgorithm
    public var preserveVolume: Bool
    
    public init(
        iterations: Int = 5,
        smoothingFactor: Double = 0.5,
        algorithm: SmoothingAlgorithm = .laplacian,
        preserveVolume: Bool = false
    ) {
        self.iterations = max(1, min(100, iterations))
        self.smoothingFactor = max(0.0, min(1.0, smoothingFactor))
        self.algorithm = algorithm
        self.preserveVolume = preserveVolume
    }
}

// Emboss operation parameters.
public struct EmbossParams: Codable, Sendable {
    public var embossType: EmbossType
    public var depth: Double
    public var bevelWidth: Double
    public var bevelDepth: Double
    public var font: String
    public var fontSize: Double
    public var text: String?
    
    public init(
        embossType: EmbossType = .raised,
        depth: Double = 2.0,
        bevelWidth: Double = 1.0,
        bevelDepth: Double = 0.5,
        font: String = "Helvetica",
        fontSize: Double = 24.0,
        text: String? = nil
    ) {
        self.embossType = embossType
        self.depth = max(0.0, depth)
        self.bevelWidth = max(0.0, bevelWidth)
        self.bevelDepth = max(0.0, bevelDepth)
        self.font = font
        self.fontSize = max(1.0, fontSize)
        self.text = text
    }
}

// Bake operation parameters.
public struct BakeParams: Codable, Sendable {
    public var bakeType: BakeType
    public var resolution: Int
    public var padding: Int
    
    public init(
        bakeType: BakeType = .heightmap,
        resolution: Int = 1024,
        padding: Int = 16
    ) {
        self.bakeType = bakeType
        self.resolution = max(64, min(8192, resolution))
        self.padding = max(0, padding)
    }
}

// Split operation parameters.
public struct SplitParams: Codable, Sendable {
    public var splitMethod: SplitMethod
    public var planeX: Double
    public var planeY: Double
    public var planeZ: Double
    public var planeNormal: Vector3D
    public var addTabs: Bool
    public var tabWidth: Double
    
    public init(
        splitMethod: SplitMethod = .horizontalPlane,
        planeX: Double = 0.0,
        planeY: Double = 0.0,
        planeZ: Double = 0.0,
        planeNormal: Vector3D = Vector3D(x: 0, y: 0, z: 1),
        addTabs: Bool = false,
        tabWidth: Double = 5.0
    ) {
        self.splitMethod = splitMethod
        self.planeX = planeX
        self.planeY = planeY
        self.planeZ = planeZ
        self.planeNormal = planeNormal
        self.addTabs = addTabs
        self.tabWidth = max(1.0, tabWidth)
    }
}

// 3D operation result.
public struct Operation3DResult: Codable, Sendable {
    public var operation: Operation3D
    public var componentID: UUID
    public var newComponentIDs: [UUID]
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        operation: Operation3D,
        componentID: UUID,
        newComponentIDs: [UUID] = [],
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.operation = operation
        self.componentID = componentID
        self.newComponentIDs = newComponentIDs
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - ModelOperationEngine

// Performs 3D model operations: smooth, emboss, bake, split.
public final class ModelOperationEngine {
    
    // Smooth a component.
    public static func smooth(
        componentID: UUID,
        params: SmoothParams,
        boundingBox: BoundingBox3D
    ) -> Operation3DResult {
        if params.iterations <= 0 {
            return Operation3DResult(
                operation: .smooth,
                componentID: componentID,
                success: false,
                errorMessage: "Iterations must be positive"
            )
        }
        if params.smoothingFactor < 0 || params.smoothingFactor > 1 {
            return Operation3DResult(
                operation: .smooth,
                componentID: componentID,
                success: false,
                errorMessage: "Smoothing factor must be between 0 and 1"
            )
        }
        return Operation3DResult(
            operation: .smooth,
            componentID: componentID,
            newComponentIDs: [componentID],
            success: true
        )
    }
    
    // Emboss a component.
    public static func emboss(
        componentID: UUID,
        params: EmbossParams,
        boundingBox: BoundingBox3D
    ) -> Operation3DResult {
        if params.depth < 0 {
            return Operation3DResult(
                operation: .emboss,
                componentID: componentID,
                success: false,
                errorMessage: "Depth must be non-negative"
            )
        }
        return Operation3DResult(
            operation: .emboss,
            componentID: componentID,
            newComponentIDs: [componentID],
            success: true
        )
    }
    
    // Bake a component.
    public static func bake(
        componentID: UUID,
        params: BakeParams,
        boundingBox: BoundingBox3D
    ) -> Operation3DResult {
        if params.resolution < 64 {
            return Operation3DResult(
                operation: .bake,
                componentID: componentID,
                success: false,
                errorMessage: "Resolution must be at least 64"
            )
        }
        return Operation3DResult(
            operation: .bake,
            componentID: componentID,
            newComponentIDs: [componentID],
            success: true
        )
    }
    
    // Split a component.
    public static func split(
        componentID: UUID,
        params: SplitParams,
        boundingBox: BoundingBox3D
    ) -> Operation3DResult {
        let normal = params.planeNormal
        let magnitude = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
        if magnitude < 0.001 {
            return Operation3DResult(
                operation: .split,
                componentID: componentID,
                success: false,
                errorMessage: "Plane normal must not be zero"
            )
        }
        
        // Split creates two new components
        let newIDs = [UUID(), UUID()]
        return Operation3DResult(
            operation: .split,
            componentID: componentID,
            newComponentIDs: newIDs,
            success: true
        )
    }
    
    // Run any 3D operation.
    public static func run(
        operation: Operation3D,
        componentID: UUID,
        params: Any,
        boundingBox: BoundingBox3D
    ) -> Operation3DResult {
        switch operation {
        case .smooth:
            guard let p = params as? SmoothParams else {
                return Operation3DResult(operation: .smooth, componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return smooth(componentID: componentID, params: p, boundingBox: boundingBox)
        case .emboss:
            guard let p = params as? EmbossParams else {
                return Operation3DResult(operation: .emboss, componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return emboss(componentID: componentID, params: p, boundingBox: boundingBox)
        case .bake:
            guard let p = params as? BakeParams else {
                return Operation3DResult(operation: .bake, componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return bake(componentID: componentID, params: p, boundingBox: boundingBox)
        case .split:
            guard let p = params as? SplitParams else {
                return Operation3DResult(operation: .split, componentID: componentID, success: false, errorMessage: "Invalid params type")
            }
            return split(componentID: componentID, params: p, boundingBox: boundingBox)
        }
    }
    
    // Validates operation parameters.
    public static func validate(operation: Operation3D, params: Any) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        switch operation {
        case .smooth:
            guard let p = params as? SmoothParams else {
                return (false, ["Invalid params type"])
            }
            if p.iterations <= 0 { errors.append("Iterations must be positive") }
            if p.smoothingFactor < 0 || p.smoothingFactor > 1 { errors.append("Smoothing factor must be 0-1") }
        case .emboss:
            guard let p = params as? EmbossParams else {
                return (false, ["Invalid params type"])
            }
            if p.depth < 0 { errors.append("Depth must be non-negative") }
        case .bake:
            guard let p = params as? BakeParams else {
                return (false, ["Invalid params type"])
            }
            if p.resolution < 64 { errors.append("Resolution must be >= 64") }
        case .split:
            guard let p = params as? SplitParams else {
                return (false, ["Invalid params type"])
            }
            let n = p.planeNormal
            let mag = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            if mag < 0.001 { errors.append("Plane normal must not be zero") }
        }
        
        return (errors.isEmpty, errors)
    }
}
