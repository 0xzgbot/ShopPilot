import Foundation

// MARK: - Gadget Toolpaths

// Keyhole cutting parameters.
public struct KeyholeParams: Codable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var holeDiameter: Double
    public var slotWidth: Double
    public var slotLength: Double
    public var slotAngle: Double
    public var toolID: UUID?
    public var feedRate: Double
    public var spindleSpeed: Double
    public var cutDepth: Double
    
    public init(
        centerX: Double,
        centerY: Double,
        holeDiameter: Double,
        slotWidth: Double,
        slotLength: Double,
        slotAngle: Double = 0.0,
        toolID: UUID? = nil,
        feedRate: Double = 1000.0,
        spindleSpeed: Double = 12000.0,
        cutDepth: Double = 1.0
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.holeDiameter = max(1.0, holeDiameter)
        self.slotWidth = max(0.1, slotWidth)
        self.slotLength = max(1.0, slotLength)
        self.slotAngle = max(0.0, min(360.0, slotAngle))
        self.toolID = toolID
        self.feedRate = max(1.0, feedRate)
        self.spindleSpeed = max(1000.0, spindleSpeed)
        self.cutDepth = max(0.0, cutDepth)
    }
}

// Edge rounding parameters.
public struct RoundingParams: Codable, Sendable {
    public var vectorID: UUID
    public var radius: Double
    public var toolID: UUID?
    public var feedRate: Double
    public var spindleSpeed: Double
    public var cutDepth: Double
    
    public init(
        vectorID: UUID,
        radius: Double,
        toolID: UUID? = nil,
        feedRate: Double = 800.0,
        spindleSpeed: Double = 10000.0,
        cutDepth: Double = 0.5
    ) {
        self.vectorID = vectorID
        self.radius = max(0.1, radius)
        self.toolID = toolID
        self.feedRate = max(1.0, feedRate)
        self.spindleSpeed = max(1000.0, spindleSpeed)
        self.cutDepth = max(0.0, cutDepth)
    }
}

// Drag knife cutting parameters.
public struct DragKnifeParams: Codable, Sendable {
    public var vectorID: UUID
    public var knifeRadius: Double
    public var toolID: UUID?
    public var feedRate: Double
    public var cutDepth: Double
    
    public init(
        vectorID: UUID,
        knifeRadius: Double,
        toolID: UUID? = nil,
        feedRate: Double = 2000.0,
        cutDepth: Double = 0.5
    ) {
        self.vectorID = vectorID
        self.knifeRadius = max(0.1, knifeRadius)
        self.toolID = toolID
        self.feedRate = max(1.0, feedRate)
        self.cutDepth = max(0.0, cutDepth)
    }
}

// Gadget toolpath type.
public enum GadgetToolpath {
    case keyhole(KeyholeParams)
    case rounding(RoundingParams)
    case dragKnife(DragKnifeParams)
    
    public var type: String {
        switch self {
        case .keyhole: return "keyhole"
        case .rounding: return "rounding"
        case .dragKnife: return "dragKnife"
        }
    }
}

// Gadget toolpath engine.
public final class GadgetToolpathEngine {
    
    // Generates keyhole toolpath.
    public static func generateKeyhole(_ params: KeyholeParams) -> [GadgetPathSegment] {
        var segments: [GadgetPathSegment] = []
        
        // Calculate hole radius
        let holeRadius = params.holeDiameter / 2.0
        
        // Calculate slot endpoint
        let slotAngleRad = params.slotAngle * .pi / 180.0
        let slotEndX = params.centerX + params.slotLength * cos(slotAngleRad)
        let slotEndY = params.centerY + params.slotLength * sin(slotAngleRad)
        
        // Segment 1: Move to hole center
        segments.append(GadgetPathSegment(
            type: .move,
            x: params.centerX,
            y: params.centerY,
            z: 0.0
        ))
        
        // Segment 2: Plunge to cut depth
        segments.append(GadgetPathSegment(
            type: .plunge,
            x: params.centerX,
            y: params.centerY,
            z: params.cutDepth
        ))
        
        // Segment 3: Circular hole
        segments.append(GadgetPathSegment(
            type: .circular(.clockwise, holeRadius, params.centerX, params.centerY),
            x: params.centerX + holeRadius,
            y: params.centerY,
            z: params.cutDepth
        ))
        
        // Segment 4: Move to slot start
        segments.append(GadgetPathSegment(
            type: .move,
            x: params.centerX,
            y: params.centerY,
            z: 0.0
        ))
        
        // Segment 5: Plunge to cut depth at slot
        segments.append(GadgetPathSegment(
            type: .plunge,
            x: params.centerX,
            y: params.centerY,
            z: params.cutDepth
        ))
        
        // Segment 6: Cut slot
        segments.append(GadgetPathSegment(
            type: .linear,
            x: slotEndX,
            y: slotEndY,
            z: params.cutDepth
        ))
        
        // Segment 7: Move up
        segments.append(GadgetPathSegment(
            type: .move,
            x: slotEndX,
            y: slotEndY,
            z: 0.0
        ))
        
        return segments
    }
    
    // Generates rounding toolpath.
    public static func generateRounding(_ params: RoundingParams) -> [GadgetPathSegment] {
        var segments: [GadgetPathSegment] = []
        
        // Placeholder: rounding follows the vector with rounded corners
        // Full implementation would need vector geometry analysis
        segments.append(GadgetPathSegment(
            type: .linear,
            x: 0.0,
            y: 0.0,
            z: params.cutDepth
        ))
        
        return segments
    }
    
    // Generates drag knife toolpath.
    public static func generateDragKnife(_ params: DragKnifeParams) -> [GadgetPathSegment] {
        var segments: [GadgetPathSegment] = []
        
        // Placeholder: drag knife follows vector with angle compensation
        segments.append(GadgetPathSegment(
            type: .linear,
            x: 0.0,
            y: 0.0,
            z: params.cutDepth
        ))
        
        return segments
    }
    
    // Generates toolpath from gadget type.
    public static func generate(_ gadget: GadgetToolpath) -> [GadgetPathSegment] {
        switch gadget {
        case .keyhole(let params):
            return generateKeyhole(params)
        case .rounding(let params):
            return generateRounding(params)
        case .dragKnife(let params):
            return generateDragKnife(params)
        }
    }
    
    // Validates gadget parameters.
    public static func validate(_ gadget: GadgetToolpath) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        switch gadget {
        case .keyhole(let params):
            if params.slotWidth > params.holeDiameter {
                errors.append("Slot width must be less than or equal to hole diameter")
            }
            if params.slotLength <= 0 {
                errors.append("Slot length must be positive")
            }
        case .rounding(let params):
            if params.radius <= 0 {
                errors.append("Rounding radius must be positive")
            }
        case .dragKnife(let params):
            if params.knifeRadius <= 0 {
                errors.append("Knife radius must be positive")
            }
        }
        
        return (errors.isEmpty, errors)
    }
}

// Gadget path segment.
public struct GadgetPathSegment: Codable, Sendable {
    public let type: GadgetPathType
    public let x: Double
    public let y: Double
    public let z: Double
    
    public init(type: GadgetPathType, x: Double, y: Double, z: Double) {
        self.type = type
        self.x = x
        self.y = y
        self.z = z
    }
}

// Gadget path type.
public enum GadgetPathType: Codable, Sendable {
    case move
    case plunge
    case linear
    case circular(CircularDirection, Double, Double, Double)
}

// Circular direction.
public enum CircularDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise
}
