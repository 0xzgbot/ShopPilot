import Foundation

// MARK: - Array Copy Result

public struct ArrayCopyResult: Identifiable, Codable {
    public let id: UUID
    public let sourceShape: VectorShape
    public let copies: [VectorShape]
    public let layout: LayoutType
    
    public enum LayoutType: String, Codable {
        case grid
        case circular
    }
    
    public init(id: UUID = UUID(), sourceShape: VectorShape, copies: [VectorShape], layout: LayoutType) {
        self.id = id
        self.sourceShape = sourceShape
        self.copies = copies
        self.layout = layout
    }
}

// MARK: - Array Copy Engine

public final class ArrayCopyEngine {
    
    /// Create a grid array of copies of a shape.
    public static func createGridArray(
        source: VectorShape,
        columns: Int,
        rows: Int,
        spacingX: Double,
        spacingY: Double
    ) -> ArrayCopyResult {
        var copies: [VectorShape] = []
        
        for row in 0..<rows {
            for col in 0..<columns {
                let dx = Double(col) * spacingX
                let dy = Double(row) * spacingY
                let translated = source.translated(by: dx, dy)
                copies.append(translated)
            }
        }
        
        return ArrayCopyResult(sourceShape: source, copies: copies, layout: .grid)
    }
    
    /// Create a circular array of copies of a shape.
    public static func createCircularArray(
        source: VectorShape,
        count: Int,
        radius: Double,
        startAngle: Double = 0
    ) -> ArrayCopyResult {
        guard count > 0 else {
            return ArrayCopyResult(sourceShape: source, copies: [], layout: .circular)
        }
        
        var copies: [VectorShape] = []
        let angleStep = 2.0 * .pi / Double(count)
        
        for i in 0..<count {
            let angle = startAngle + angleStep * Double(i)
            let dx = radius * cos(angle)
            let dy = radius * sin(angle)
            let translated = source.translated(by: dx, dy)
            
            // Also rotate the shape around its center
            let rotated = translated.rotated(around: VectorPoint(x: dx, y: dy), by: angle)
            copies.append(rotated)
        }
        
        return ArrayCopyResult(sourceShape: source, copies: copies, layout: .circular)
    }
    
    /// Merge all array copies into a single group.
    public static func mergeCopies(_ result: ArrayCopyResult) -> [VectorShape] {
        var merged: [VectorShape] = [result.sourceShape]
        merged.append(contentsOf: result.copies)
        return merged
    }
}

// MARK: - VectorShape Array Copy Helpers

public extension VectorShape {
    
    /// Create a grid array of copies of this shape.
    func gridArray(columns: Int, rows: Int, spacingX: Double, spacingY: Double) -> ArrayCopyResult {
        ArrayCopyEngine.createGridArray(source: self, columns: columns, rows: rows, spacingX: spacingX, spacingY: spacingY)
    }
    
    /// Create a circular array of copies of this shape.
    func circularArray(count: Int, radius: Double, startAngle: Double = 0) -> ArrayCopyResult {
        ArrayCopyEngine.createCircularArray(source: self, count: count, radius: radius, startAngle: startAngle)
    }
}

// MARK: - Rotation Helper (needed for circular array)

public extension VectorShape {
    /// Rotate the shape around a center point by the given angle in radians.
    func rotated(around center: VectorPoint, by radians: Double) -> VectorShape {
        let cos = cos(radians)
        let sin = sin(radians)
        
        func rotatePoint(_ point: VectorPoint) -> VectorPoint {
            let dx = point.x - center.x
            let dy = point.y - center.y
            return VectorPoint(
                x: center.x + dx * cos - dy * sin,
                y: center.y + dx * sin + dy * cos
            )
        }
        
        switch self {
        case .line(let start, let end):
            return .line(start: rotatePoint(start), end: rotatePoint(end))
        case .circle(let c, let r):
            return .circle(center: rotatePoint(c), radius: r)
        case .rectangle(let o, let w, let h):
            return .rectangle(origin: rotatePoint(o), width: w, height: h)
        case .arc(let c, let r, let sa, let ea):
            return .arc(center: rotatePoint(c), radius: r, startAngle: sa + radians, endAngle: ea + radians)
        case .ellipse(let c, let rx, let ry, let rot):
            return .ellipse(center: rotatePoint(c), radiusX: rx, radiusY: ry, rotation: rot + radians)
        case .polygon(let c, let r, let s, let rot):
            return .polygon(center: rotatePoint(c), radius: r, sides: s, rotation: rot + radians)
        case .star(let c, let or, let ir, let p, let rot):
            return .star(center: rotatePoint(c), outerRadius: or, innerRadius: ir, points: p, rotation: rot + radians)
        case .freehand(let points):
            return .freehand(points: points.map(rotatePoint))
        }
    }

    /// Rotate the shape around a center point by an angle in degrees.
    ///
    /// Rectangles re-derive their axis-aligned bounding box after rotating all
    /// four corners, so a 90° rotation swaps width/height and keeps the
    /// centroid fixed (the raw origin+w/h form cannot express that). All other
    /// shapes delegate to the radians rotation (SPK-1101j).
    func rotated(byDegrees degrees: Double, around center: VectorPoint) -> VectorShape {
        guard degrees != 0 else { return self }
        let radians = degrees * .pi / 180
        if case .rectangle(let o, let w, let h) = self {
            let cos = cos(radians)
            let sin = sin(radians)
            func rotatePoint(_ point: VectorPoint) -> VectorPoint {
                let dx = point.x - center.x
                let dy = point.y - center.y
                return VectorPoint(
                    x: center.x + dx * cos - dy * sin,
                    y: center.y + dx * sin + dy * cos
                )
            }
            let corners = [
                o,
                VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h),
                VectorPoint(x: o.x, y: o.y + h),
            ].map(rotatePoint)
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            let maxX = xs.max() ?? 0
            let maxY = ys.max() ?? 0
            return .rectangle(
                origin: VectorPoint(x: minX, y: minY),
                width: maxX - minX,
                height: maxY - minY
            )
        }
        return rotated(around: center, by: radians)
    }
}
