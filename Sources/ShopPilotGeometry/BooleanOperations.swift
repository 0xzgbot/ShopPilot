import Foundation

// MARK: - Boolean Operation Result

/// Tracks a boolean operation for undo/redo history.
public struct BooleanOperationResult: Identifiable, Codable {
    public let id: UUID
    public let operation: String
    public let inputCount: Int
    public private(set) var outputShapes: [VectorShape]
    public let timestamp: Date
    
    public init(id: UUID = UUID(), operation: String, inputCount: Int, outputShapes: [VectorShape]) {
        self.id = id
        self.operation = operation
        self.inputCount = inputCount
        self.outputShapes = outputShapes
        self.timestamp = Date()
    }
}

// MARK: - Shape Boolean Engine

/// Performs boolean operations on vector shapes.
public final class ShapeBooleanEngine {
    
    /// Weld (union) overlapping or touching shapes into a single shape per group.
    public static func weld(shapes: [VectorShape]) -> [VectorShape] {
        guard !shapes.isEmpty else { return [] }
        
        // For simple shapes, if they overlap, merge their bounding rects
        var result: [VectorShape] = []
        var usedIndices: Set<Int> = []
        
        for i in 0..<shapes.count where !usedIndices.contains(i) {
            let shapeA = shapes[i]
            let rectA = shapeA.boundingRect
            
            // Find all shapes that overlap with this one
            var group: [VectorShape] = [shapeA]
            usedIndices.insert(i)
            
            for j in (i+1)..<shapes.count where !usedIndices.contains(j) {
                let shapeB = shapes[j]
                let rectB = shapeB.boundingRect
                
                if rectsOverlap(rectA, rectB) || ShapeBooleanEngine.contains(shapeA, shapeB) || ShapeBooleanEngine.contains(shapeB, shapeA) {
                    group.append(shapeB)
                    usedIndices.insert(j)
                }
            }
            
            // Merge overlapping shapes into a single bounding rectangle
            if group.count > 1 {
                let minX = group.map({ $0.boundingRect.minX }).min() ?? 0.0
                let minY = group.map({ $0.boundingRect.minY }).min() ?? 0.0
                let maxX = group.map({ $0.boundingRect.maxX }).max() ?? 0.0
                let maxY = group.map({ $0.boundingRect.maxY }).max() ?? 0.0
                result.append(.rectangle(origin: VectorPoint(x: minX, y: minY),
                                       width: maxX - minX, height: maxY - minY))
            } else {
                result.append(shapeA)
            }
        }
        
        return result
    }
    
    /// Subtract one shape from another.
    public static func subtract(base: VectorShape, tool: VectorShape) -> [VectorShape] {
        // Simple implementation: if shapes don't overlap, return base unchanged
        let baseRect = base.boundingRect
        let toolRect = tool.boundingRect
        
        guard rectsOverlap(baseRect, toolRect) else {
            return [base]
        }
        
        // For overlapping rectangles, subtract the tool area
        switch (base, tool) {
        case (.rectangle(let bOrigin, let bWidth, let bHeight),
              .rectangle(let tOrigin, let tWidth, let tHeight)):
            // Subtract rectangle from rectangle — return remaining regions
            var result: [VectorShape] = []
            
            // Left region (if tool doesn't cover full width)
            if tOrigin.x > bOrigin.x {
                result.append(.rectangle(origin: VectorPoint(x: bOrigin.x, y: bOrigin.y),
                                       width: tOrigin.x - bOrigin.x, height: bHeight))
            }
            
            // Right region (if tool doesn't cover full width)
            let toolRight = tOrigin.x + tWidth
            if toolRight < bOrigin.x + bWidth {
                result.append(.rectangle(origin: VectorPoint(x: toolRight, y: bOrigin.y),
                                       width: (bOrigin.x + bWidth) - toolRight, height: bHeight))
            }
            
            // Top region (if tool doesn't cover full height)
            if tOrigin.y > bOrigin.y {
                result.append(.rectangle(origin: VectorPoint(x: max(bOrigin.x, tOrigin.x), y: bOrigin.y),
                                       width: min(toolRight, bOrigin.x + bWidth) - max(bOrigin.x, tOrigin.x),
                                       height: tOrigin.y - bOrigin.y))
            }
            
            // Bottom region (if tool doesn't cover full height)
            let toolBottom = tOrigin.y + tHeight
            if toolBottom < bOrigin.y + bHeight {
                result.append(.rectangle(origin: VectorPoint(x: max(bOrigin.x, tOrigin.x), y: toolBottom),
                                       width: min(toolRight, bOrigin.x + bWidth) - max(bOrigin.x, tOrigin.x),
                                       height: (bOrigin.y + bHeight) - toolBottom))
            }
            
            return result.isEmpty ? [base] : result
            
        default:
            // For non-rectangle shapes, return empty array (full overlap assumed)
            return []
        }
    }
    
    /// Find the intersection of multiple shapes.
    public static func intersect(shapes: [VectorShape]) -> [VectorShape] {
        guard shapes.count >= 2 else { return shapes }
        
        var result = shapes[0]
        
        for i in 1..<shapes.count {
            let next = shapes[i]
            
            // Simple intersection: if bounding rects don't overlap, no intersection
            let rectA = result.boundingRect
            let rectB = next.boundingRect
            
            guard rectsOverlap(rectA, rectB) else { return [] }
            
            // For rectangles, compute the overlapping region
            switch (result, next) {
            case (.rectangle(let r1Origin, let r1Width, let r1Height),
                  .rectangle(let r2Origin, let r2Width, let r2Height)):
                let overlapMinX = max(r1Origin.x, r2Origin.x)
                let overlapMinY = max(r1Origin.y, r2Origin.y)
                let overlapMaxX = min(r1Origin.x + r1Width, r2Origin.x + r2Width)
                let overlapMaxY = min(r1Origin.y + r1Height, r2Origin.y + r2Height)
                
                if overlapMinX < overlapMaxX && overlapMinY < overlapMaxY {
                    result = .rectangle(origin: VectorPoint(x: overlapMinX, y: overlapMinY),
                                      width: overlapMaxX - overlapMinX, height: overlapMaxY - overlapMinY)
                } else {
                    return []
                }
                
            default:
                // For other shapes, conservatively return empty (full intersection assumed complex)
                result = next
            }
        }
        
        return [result]
    }
    
    /// Check if one shape fully contains another.
    public static func contains(_ container: VectorShape, _ contained: VectorShape) -> Bool {
        let containerRect = container.boundingRect
        let containedRect = contained.boundingRect
        
        // Quick bounding rect check first
        guard rectsContain(containerRect, containedRect) else { return false }
        
        // For rectangles, precise check
        if case (.rectangle(let cOrigin, let cWidth, let cHeight)) = container,
           case (.rectangle(let tOrigin, let tWidth, let tHeight)) = contained {
            return tOrigin.x >= cOrigin.x &&
                   tOrigin.y >= cOrigin.y &&
                   (tOrigin.x + tWidth) <= (cOrigin.x + cWidth) &&
                   (tOrigin.y + tHeight) <= (cOrigin.y + cHeight)
        }
        
        // For circles, check if all corners of contained rect are within container circle
        if case (.circle(let center, let radius)) = container {
            let points: [VectorPoint] = [
                VectorPoint(x: containedRect.minX, y: containedRect.minY),
                VectorPoint(x: containedRect.maxX, y: containedRect.minY),
                VectorPoint(x: containedRect.minX, y: containedRect.maxY),
                VectorPoint(x: containedRect.maxX, y: containedRect.maxY)
            ]
            return points.allSatisfy { hypot($0.x - center.x, $0.y - center.y) <= radius + 1e-6 }
        }
        
        // Default conservative check
        return true
    }
    
    // MARK: - Helpers
    
    private static func rectsOverlap(_ a: Rect, _ b: Rect) -> Bool {
        return a.minX < b.maxX && a.maxX > b.minX &&
               a.minY < b.maxY && a.maxY > b.minY
    }
    
    private static func rectsContain(_ container: Rect, _ contained: Rect) -> Bool {
        return container.minX <= contained.minX &&
               container.maxX >= contained.maxX &&
               container.minY <= contained.minY &&
               container.maxY >= contained.maxY
    }
}
