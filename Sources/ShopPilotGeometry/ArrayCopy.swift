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

    /// Copy a shape around a CENTER point (not the origin). Each copy keeps
    /// its distance and angular offset from `center`; with `rotateCopies` it
    /// also spins by its angular position. Rectangles convert to closed
    /// freehands when rotating so the rotation is geometrically honest.
    /// The k=0 copy coincides with the source's original position.
    public static func createCircularArrayAround(
        source: VectorShape,
        center: VectorPoint,
        count: Int,
        rotateCopies: Bool,
        startAngle: Double = 0
    ) -> ArrayCopyResult {
        guard count > 0 else {
            return ArrayCopyResult(sourceShape: source, copies: [], layout: .circular)
        }
        let b = source.boundingRect
        let sc = VectorPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        let ox = sc.x - center.x, oy = sc.y - center.y
        let dist = (ox * ox + oy * oy).squareRoot()
        let baseAngle = dist > 1e-9 ? atan2(oy, ox) : 0
        let base: VectorShape = {
            if rotateCopies, case .rectangle(let o, let w, let h) = source {
                return .freehand(points: [
                    VectorPoint(x: o.x, y: o.y),
                    VectorPoint(x: o.x + w, y: o.y),
                    VectorPoint(x: o.x + w, y: o.y + h),
                    VectorPoint(x: o.x, y: o.y + h),
                    VectorPoint(x: o.x, y: o.y),
                ])
            }
            return source
        }()
        let step = 2.0 * .pi / Double(count)
        var copies: [VectorShape] = []
        for k in 0..<count {
            let angle = baseAngle + startAngle + step * Double(k)
            let px = center.x + dist * cos(angle)
            let py = center.y + dist * sin(angle)
            var copy = base.translated(by: px - sc.x, py - sc.y)
            if rotateCopies, k > 0 {
                let cb = copy.boundingRect
                let cc = VectorPoint(x: (cb.minX + cb.maxX) / 2, y: (cb.minY + cb.maxY) / 2)
                copy = copy.rotated(around: cc, by: step * Double(k))
            }
            copies.append(copy)
        }
        return ArrayCopyResult(sourceShape: source, copies: copies, layout: .circular)
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
