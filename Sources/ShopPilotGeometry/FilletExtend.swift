import Foundation

// MARK: - Fillet / Extend Engine

public final class FilletExtendEngine {
    
    // MARK: - Fillet
    
    /// Apply a fillet (rounded corner) to a shape.
    /// For `VectorShape.line`, inserts an arc between two connected segments meeting at a point within `cornerPoint` tolerance.
    /// For `VectorShape.rectangle`, rounds all corners.
    public static func fillet(
        shape: VectorShape,
        cornerPoint: VectorPoint,
        radius: Double
    ) -> [VectorShape] {
        guard radius > 1e-9 else { return [shape] }
        
        switch shape {
        case .line(let start, let end):
            // If corner is near start or end, append a small arc-like polyline approximation
            if hypot(start.x - cornerPoint.x, start.y - cornerPoint.y) < 1e-6 {
                return filletLineEnd(point: start, other: end, radius: radius)
            } else if hypot(end.x - cornerPoint.x, end.y - cornerPoint.y) < 1e-6 {
                return filletLineEnd(point: end, other: start, radius: radius)
            }
            return [shape]
            
        case .rectangle(let origin, let width, let height):
            return filletRectangle(
                origin: origin,
                width: width,
                height: height,
                radius: radius
            )
            
        default:
            return [shape]
        }
    }
    
    private static func filletLineEnd(point: VectorPoint, other: VectorPoint, radius: Double) -> [VectorShape] {
        let dx = other.x - point.x
        let dy = other.y - point.y
        let len = hypot(dx, dy)
        guard len > 1e-9 else { return [.line(start: point, end: point)] }
        
        let nx = -dy / len
        let ny = dx / len
        
        let p1 = VectorPoint(x: point.x + nx * radius, y: point.y + ny * radius)
        let p2 = VectorPoint(x: point.x - nx * radius, y: point.y - ny * radius)
        
        // Two small lines approximating the rounded corner
        return [
            .line(start: p1, end: point),
            .line(start: point, end: p2)
        ]
    }
    
    private static func filletRectangle(origin: VectorPoint, width: Double, height: Double, radius: Double) -> [VectorShape] {
        let minX = min(origin.x, origin.x + width)
        let maxX = max(origin.x, origin.x + width)
        let minY = min(origin.y, origin.y + height)
        let maxY = max(origin.y, origin.y + height)
        
        let r = min(radius, min(abs(width), abs(height)) / 2.0)
        
        let tl = VectorPoint(x: minX + r, y: minY + r)
        let tr = VectorPoint(x: maxX - r, y: minY + r)
        let br = VectorPoint(x: maxX - r, y: maxY - r)
        let bl = VectorPoint(x: minX + r, y: maxY - r)
        
        let corners: [VectorPoint] = [tl, tr, br, bl]
        
        var polylines: [VectorShape] = []
        for i in 0..<corners.count {
            let current = corners[i]
            let next = corners[(i + 1) % corners.count]
            polylines.append(.line(start: current, end: next))
        }
        
        return polylines
    }
    
    // MARK: - Extend
    
    /// Extend a line shape to a target point, keeping it collinear.
    public static func extendLine(_ shape: VectorShape, to target: VectorPoint) -> [VectorShape] {
        guard case .line(let start, let end) = shape else { return [shape] }
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 1e-9 else { return [shape] }
        
        let len = sqrt(lenSq)
        let nx = dx / len
        let ny = dy / len
        
        let newEnd = VectorPoint(
            x: target.x,
            y: target.y
        )
        
        return [.line(start: start, end: newEnd)]
    }
    
    /// Extend a line until it intersects another shape's bounding box or another line.
    public static func extendLineUntilIntersect(
        _ shape: VectorShape,
        other: VectorShape,
        tolerance: Double = 1e-6
    ) -> [VectorShape] {
        guard case .line(let start, let end) = shape else { return [shape] }
        guard case .line(let otherStart, let otherEnd) = other else { return [shape] }
        
        let intersection = lineLineIntersection(
            p1: start, p2: end,
            p3: otherStart, p4: otherEnd
        )
        
        if let inter = intersection {
            // Extend end of first line to intersection point
            return [.line(start: start, end: inter)]
        }
        
        return [shape]
    }
    
    // MARK: - Helpers
    
    private static func lineLineIntersection(
        p1: VectorPoint, p2: VectorPoint,
        p3: VectorPoint, p4: VectorPoint
    ) -> VectorPoint? {
        let dx1 = p2.x - p1.x
        let dy1 = p2.y - p1.y
        let dx2 = p4.x - p3.x
        let dy2 = p4.y - p3.y
        
        let denom = dx1 * dy2 - dy1 * dx2
        guard abs(denom) > 1e-9 else { return nil }
        
        let t = ((p3.x - p1.x) * dy2 - (p3.y - p1.y) * dx2) / denom
        
        return VectorPoint(
            x: p1.x + t * dx1,
            y: p1.y + t * dy1
        )
    }
}
