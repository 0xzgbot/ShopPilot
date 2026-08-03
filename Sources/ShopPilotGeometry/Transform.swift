import Foundation

// MARK: - Transform Operation

/// A transform operation applied to vector shapes.
public struct TransformOperation: Codable, Equatable {
    public enum OperationType: String, Codable {
        case move
        case rotate
        case scale
        
        public var description: String {
            switch self {
            case .move: return "Move"
            case .rotate: return "Rotate"
            case .scale: return "Scale"
            }
        }
    }
    
    public let type: OperationType
    public let parameters: [String: Double]
    
    public init(type: OperationType, parameters: [String: Double]) {
        self.type = type
        self.parameters = parameters
    }
}

// MARK: - Alignment Mode

/// Alignment modes for positioning multiple shapes.
public enum AlignmentMode: String, Codable {
    case topLeft
    case centerCenter
    case bottomRight
    case distributeHorizontal
    case distributeVertical
    
    public var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .centerCenter: return "Center to Center"
        case .bottomRight: return "Bottom Right"
        case .distributeHorizontal: return "Distribute Horizontally"
        case .distributeVertical: return "Distribute Vertically"
        }
    }
}

// MARK: - Shape Transformer

/// Centroid of a set of shapes: the center of the union bounding box.
/// Returns nil for an empty selection.
public func selectionCentroid(of shapes: [VectorShape]) -> VectorPoint? {
    guard !shapes.isEmpty else { return nil }
    var minX = Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for shape in shapes {
        let r = shape.boundingRect
        minX = min(minX, r.minX)
        minY = min(minY, r.minY)
        maxX = max(maxX, r.maxX)
        maxY = max(maxY, r.maxY)
    }
    return VectorPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
}

/// Applies transform operations to vector shapes.
public final class ShapeTransformer {
    public init() {}
    
    /// Move all shapes by (dx, dy).
    public func move(shapes: [VectorShape], dx: Double, dy: Double) -> [VectorShape] {
        return shapes.map { $0.translated(by: dx, dy) }
    }

    /// Mirror all shapes across the vertical line `x = center.x` (flip horizontal).
    public func flipHorizontal(shapes: [VectorShape], about center: VectorPoint) -> [VectorShape] {
        shapes.map { $0.flippedHorizontally(about: center) }
    }

    /// Uniform scale about a center (SPK-1101k).
    public func scale(shapes: [VectorShape], factor: Double, about center: VectorPoint) -> [VectorShape] {
        shapes.map { $0.scaled(by: factor, about: center) }
    }
    
    /// Rotate all shapes around a center point.
    public func rotate(shapes: [VectorShape], angle: Double, about center: VectorPoint) -> [VectorShape] {
        let radians = angle * .pi / 180.0
        return shapes.map { shape in
            switch shape {
            case .line(let start, let end):
                let newStart = rotatePoint(start, around: center, by: radians)
                let newEnd = rotatePoint(end, around: center, by: radians)
                return .line(start: newStart, end: newEnd)
            case .circle(let c, let r):
                let newCenter = rotatePoint(c, around: center, by: radians)
                return .circle(center: newCenter, radius: r)
            case .rectangle(let o, let w, let h):
                let newOrigin = rotatePoint(o, around: center, by: radians)
                return .rectangle(origin: newOrigin, width: w, height: h)
            case .arc(let c, let r, let sa, let ea):
                let newCenter = rotatePoint(c, around: center, by: radians)
                return .arc(center: newCenter, radius: r, startAngle: sa + radians, endAngle: ea + radians)
            case .ellipse(let c, let rx, let ry, let rot):
                let newCenter = rotatePoint(c, around: center, by: radians)
                return .ellipse(center: newCenter, radiusX: rx, radiusY: ry, rotation: rot + radians)
            case .polygon(let c, let r, let s, let rot):
                let newCenter = rotatePoint(c, around: center, by: radians)
                return .polygon(center: newCenter, radius: r, sides: s, rotation: rot + radians)
            case .star(let c, let or, let ir, let p, let rot):
                let newCenter = rotatePoint(c, around: center, by: radians)
                return .star(center: newCenter, outerRadius: or, innerRadius: ir, points: p, rotation: rot + radians)
            case .freehand(let points):
                return .freehand(points: points.map { rotatePoint($0, around: center, by: radians) })
            }
        }
    }
    
    /// Scale all shapes by (factorX, factorY) about a center point.
    public func scale(shapes: [VectorShape], factorX: Double, factorY: Double, about center: VectorPoint) -> [VectorShape] {
        return shapes.map { shape in
            switch shape {
            case .line(let start, let end):
                let newStart = scalePoint(start, by: factorX, factorY, about: center)
                let newEnd = scalePoint(end, by: factorX, factorY, about: center)
                return .line(start: newStart, end: newEnd)
            case .circle(let c, let r):
                let newCenter = scalePoint(c, by: factorX, factorY, about: center)
                return .circle(center: newCenter, radius: r * max(factorX, factorY))
            case .rectangle(let o, let w, let h):
                let newOrigin = scalePoint(o, by: factorX, factorY, about: center)
                return .rectangle(origin: newOrigin, width: w * factorX, height: h * factorY)
            case .arc(let c, let r, let sa, let ea):
                let newCenter = scalePoint(c, by: factorX, factorY, about: center)
                return .arc(center: newCenter, radius: r * max(factorX, factorY), startAngle: sa, endAngle: ea)
            case .ellipse(let c, let rx, let ry, let rot):
                let newCenter = scalePoint(c, by: factorX, factorY, about: center)
                return .ellipse(center: newCenter, radiusX: rx * factorX, radiusY: ry * factorY, rotation: rot)
            case .polygon(let c, let r, let s, let rot):
                let newCenter = scalePoint(c, by: factorX, factorY, about: center)
                return .polygon(center: newCenter, radius: r * max(factorX, factorY), sides: s, rotation: rot)
            case .star(let c, let or, let ir, let p, let rot):
                let newCenter = scalePoint(c, by: factorX, factorY, about: center)
                return .star(center: newCenter, outerRadius: or * max(factorX, factorY), innerRadius: ir * max(factorX, factorY), points: p, rotation: rot)
            case .freehand(let points):
                return .freehand(points: points.map { scalePoint($0, by: factorX, factorY, about: center) })
            }
        }
    }
    
    /// Align multiple shapes based on the specified alignment mode.
    public func align(shapes: [VectorShape], mode: AlignmentMode) -> [VectorShape] {
        guard !shapes.isEmpty else { return shapes }
        
        switch mode {
        case .topLeft:
            let minX = shapes.map({ $0.boundingRect.minX }).min() ?? 0.0
            let minY = shapes.map({ $0.boundingRect.minY }).min() ?? 0.0
            var result: [VectorShape] = []
            for shape in shapes {
                let rect = shape.boundingRect
                let dx = minX - rect.minX
                let dy = minY - rect.minY
                result.append(shape.translated(by: dx, dy))
            }
            return result
            
        case .centerCenter:
            let centerX = shapes.map({ $0.boundingRect.minX + $0.boundingRect.width / 2.0 }).reduce(0) { $0 + $1 } / Double(shapes.count)
            let centerY = shapes.map({ $0.boundingRect.minY + $0.boundingRect.height / 2.0 }).reduce(0) { $0 + $1 } / Double(shapes.count)
            var result: [VectorShape] = []
            for shape in shapes {
                let rect = shape.boundingRect
                let cx = rect.minX + rect.width / 2.0
                let cy = rect.minY + rect.height / 2.0
                result.append(shape.translated(by: centerX - cx, centerY - cy))
            }
            return result
            
        case .bottomRight:
            let maxX = shapes.map({ $0.boundingRect.maxX }).max() ?? 0.0
            let maxY = shapes.map({ $0.boundingRect.maxY }).max() ?? 0.0
            var result: [VectorShape] = []
            for shape in shapes {
                let rect = shape.boundingRect
                let dx = maxX - rect.maxX
                let dy = maxY - rect.maxY
                result.append(shape.translated(by: dx, dy))
            }
            return result
            
        case .distributeHorizontal:
            guard shapes.count >= 2 else { return shapes }
            var sortedShapes = shapes.sorted { $0.boundingRect.minX < $1.boundingRect.minX }
            let minX = sortedShapes.first!.boundingRect.minX
            let maxX = sortedShapes.last!.boundingRect.maxX
            let totalWidth = maxX - minX
            let spacing = totalWidth / Double(sortedShapes.count - 1)
            
            for i in 0..<sortedShapes.count {
                let targetX = minX + spacing * Double(i)
                let rect = sortedShapes[i].boundingRect
                let dx = targetX - rect.minX
                sortedShapes[i] = sortedShapes[i].translated(by: dx, 0)
            }
            return sortedShapes
            
        case .distributeVertical:
            guard shapes.count >= 2 else { return shapes }
            var sortedShapes = shapes.sorted { $0.boundingRect.minY < $1.boundingRect.minY }
            let minY = sortedShapes.first!.boundingRect.minY
            let maxY = sortedShapes.last!.boundingRect.maxY
            let totalHeight = maxY - minY
            let spacing = totalHeight / Double(sortedShapes.count - 1)
            
            for i in 0..<sortedShapes.count {
                let targetY = minY + spacing * Double(i)
                let rect = sortedShapes[i].boundingRect
                let dy = targetY - rect.minY
                sortedShapes[i] = sortedShapes[i].translated(by: 0, dy)
            }
            return sortedShapes
        }
    }
    
    // MARK: - Helpers
    
    private func rotatePoint(_ point: VectorPoint, around center: VectorPoint, by angle: Double) -> VectorPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return VectorPoint(
            x: center.x + (dx * cosA - dy * sinA),
            y: center.y + (dx * sinA + dy * cosA)
        )
    }
    
    private func scalePoint(_ point: VectorPoint, by factorX: Double, _ factorY: Double, about center: VectorPoint) -> VectorPoint {
        return VectorPoint(
            x: center.x + (point.x - center.x) * factorX,
            y: center.y + (point.y - center.y) * factorY
        )
    }
}

// MARK: - Shape Group

/// A group of shapes that can be transformed together.
public final class ShapeGroup: Identifiable, Codable {
    
    public var id: UUID
    public var name: String
    public private(set) var memberIds: [UUID] = []
    public private(set) var createdAt: Date
    public private(set) var updatedAt: Date
    
    public init(id: UUID = UUID(), name: String, members: [VectorShape]) {
        self.id = id
        self.name = name
        self.memberIds = members.map { _ in UUID() } // Placeholder IDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Add a member shape to the group.
    public func addMember(id: UUID) {
        if !memberIds.contains(id) {
            memberIds.append(id)
            updatedAt = Date()
        }
    }
    
    /// Remove a member from the group.
    public func removeMember(id: UUID) {
        memberIds.removeAll { $0 == id }
        updatedAt = Date()
    }
    
    /// Get all shapes in this group by their IDs.
    public func getMembers(shapes: [VectorShape]) -> [VectorShape] {
        // Note: In practice, shapes would have stable UUIDs for lookup
        return shapes // Simplified — returns all shapes
    }
}
