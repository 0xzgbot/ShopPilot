import Foundation

// MARK: - Gadget Preview Rendering

// Preview path point.
public struct PreviewPathPoint: Codable, Sendable {
    public let x: Double
    public let y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

// Preview path for gadget rendering.
public struct PreviewPath: Codable, Sendable {
    public let points: [PreviewPathPoint]
    public let color: String
    public let dashPattern: [Double]?
    
    public init(
        points: [PreviewPathPoint],
        color: String = "#FF6B35",
        dashPattern: [Double]? = nil
    ) {
        self.points = points
        self.color = color
        self.dashPattern = dashPattern
    }
}

// Gadget preview engine.
public final class GadgetPreviewEngine {
    
    // Generates preview path for keyhole.
    public static func previewKeyhole(_ params: KeyholeParams) -> [PreviewPath] {
        var paths: [PreviewPath] = []
        
        // Calculate hole radius
        let holeRadius = params.holeDiameter / 2.0
        let holeSteps = max(12, Int(holeRadius * 10))
        
        // Generate circular hole path
        var holePoints: [PreviewPathPoint] = []
        for i in 0...holeSteps {
            let angle = Double(i) / Double(holeSteps) * 2.0 * .pi
            let x = params.centerX + holeRadius * cos(angle)
            let y = params.centerY + holeRadius * sin(angle)
            holePoints.append(PreviewPathPoint(x: x, y: y))
        }
        
        paths.append(PreviewPath(
            points: holePoints,
            color: "#00FF00",
            dashPattern: nil
        ))
        
        // Generate slot path
        let slotAngleRad = params.slotAngle * .pi / 180.0
        let slotEndX = params.centerX + params.slotLength * cos(slotAngleRad)
        let slotEndY = params.centerY + params.slotLength * sin(slotAngleRad)
        
        paths.append(PreviewPath(
            points: [
                PreviewPathPoint(x: params.centerX, y: params.centerY),
                PreviewPathPoint(x: slotEndX, y: slotEndY)
            ],
            color: "#FFFF00",
            dashPattern: [5.0, 5.0]
        ))
        
        // Generate slot width indicator
        let slotWidthHalf = params.slotWidth / 2.0
        let perpX = -sin(slotAngleRad) * slotWidthHalf
        let perpY = cos(slotAngleRad) * slotWidthHalf
        
        paths.append(PreviewPath(
            points: [
                PreviewPathPoint(x: params.centerX + perpX, y: params.centerY + perpY),
                PreviewPathPoint(x: params.centerX - perpX, y: params.centerY - perpY)
            ],
            color: "#FF0000",
            dashPattern: [2.0, 2.0]
        ))
        
        return paths
    }
    
    // Generates preview path for rounding.
    public static func previewRounding(_ params: RoundingParams) -> [PreviewPath] {
        var paths: [PreviewPath] = []
        
        // Placeholder: shows rounding radius indicator
        paths.append(PreviewPath(
            points: [
                PreviewPathPoint(x: 0.0, y: 0.0),
                PreviewPathPoint(x: params.radius, y: 0.0)
            ],
            color: "#00FF00",
            dashPattern: [3.0, 3.0]
        ))
        
        return paths
    }
    
    // Generates preview path for drag knife.
    public static func previewDragKnife(_ params: DragKnifeParams) -> [PreviewPath] {
        var paths: [PreviewPath] = []
        
        // Placeholder: shows knife radius indicator
        paths.append(PreviewPath(
            points: [
                PreviewPathPoint(x: 0.0, y: 0.0),
                PreviewPathPoint(x: params.knifeRadius, y: 0.0)
            ],
            color: "#0000FF",
            dashPattern: [4.0, 4.0]
        ))
        
        return paths
    }
    
    // Generates preview from gadget type.
    public static func preview(_ gadget: GadgetToolpath) -> [PreviewPath] {
        switch gadget {
        case .keyhole(let params):
            return previewKeyhole(params)
        case .rounding(let params):
            return previewRounding(params)
        case .dragKnife(let params):
            return previewDragKnife(params)
        }
    }
}
