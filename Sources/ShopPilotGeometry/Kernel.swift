import Foundation
import ShopPilotCore

// MARK: - Rect

/// Bounding rectangle for a 2D shape.
public struct Rect: Codable, Equatable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double
    
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    
    public init(minX: Double = 0, minY: Double = 0, maxX: Double = 0, maxY: Double = 0) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

// MARK: - Vector Point

/// A 2D point in the design coordinate space.
///
/// Single source of truth lives in `ShopPilotCore` — Geometry re-exports it so
/// both modules share one `VectorPoint` type (avoids cross-module ambiguity).
public typealias VectorPoint = ShopPilotCore.VectorPoint

// MARK: - Vector Shape

/// A 2D vector shape used in the design kernel.
public enum VectorShape: Codable, Equatable {
    case line(start: VectorPoint, end: VectorPoint)
    case circle(center: VectorPoint, radius: Double)
    case rectangle(origin: VectorPoint, width: Double, height: Double)
    case arc(center: VectorPoint, radius: Double, startAngle: Double, endAngle: Double)
    case ellipse(center: VectorPoint, radiusX: Double, radiusY: Double, rotation: Double = 0)
    case polygon(center: VectorPoint, radius: Double, sides: Int, rotation: Double = 0)
    case star(center: VectorPoint, outerRadius: Double, innerRadius: Double, points: Int, rotation: Double = 0)
    case freehand(points: [VectorPoint])
    
    /// Hashable identity for the shape.
    public var hashValue: Int {
        var hasher = Hasher()
        switch self {
        case .line(let s, let e):
            hasher.combine(0)
            hasher.combine(s)
            hasher.combine(e)
        case .circle(let c, let r):
            hasher.combine(1)
            hasher.combine(c)
            hasher.combine(r)
        case .rectangle(let o, let w, let h):
            hasher.combine(2)
            hasher.combine(o)
            hasher.combine(w)
            hasher.combine(h)
        case .arc(let c, let r, let sa, let ea):
            hasher.combine(3)
            hasher.combine(c)
            hasher.combine(r)
            hasher.combine(sa)
            hasher.combine(ea)
        case .ellipse(let c, let rx, let ry, let rot):
            hasher.combine(4)
            hasher.combine(c)
            hasher.combine(rx)
            hasher.combine(ry)
            hasher.combine(rot)
        case .polygon(let c, let r, let s, let rot):
            hasher.combine(5)
            hasher.combine(c)
            hasher.combine(r)
            hasher.combine(s)
            hasher.combine(rot)
        case .star(let c, let or, let ir, let p, let rot):
            hasher.combine(6)
            hasher.combine(c)
            hasher.combine(or)
            hasher.combine(ir)
            hasher.combine(p)
            hasher.combine(rot)
        case .freehand(let pts):
            hasher.combine(7)
            hasher.combine(pts)
        }
        return hasher.finalize()
    }
    
    // MARK: - Computed Properties
    
    /// Area enclosed by the shape (0 for lines).
    public var area: Double {
        switch self {
        case .line: return 0.0
        case .circle(_, let r): return .pi * r * r
        case .rectangle(_, let w, let h): return abs(w * h)
        case .arc(_, let r, let sa, let ea):
            let sweep = normalizeAngle(ea - sa)
            return 0.5 * r * r * sweep
        case .ellipse(_, let rx, let ry, _):
            return .pi * rx * ry
        case .polygon(_, let r, let s, _):
            return 0.5 * Double(s) * r * r * sin(2.0 * .pi / Double(s))
        case .star(_, let outer, let inner, let points, _):
            let spikes = Double(points)
            let area = spikes * 0.5 * (outer * outer - inner * inner) * sin(2.0 * .pi / spikes)
            return abs(area)
        case .freehand:
            return 0.0
        }
    }
    
    /// Bounding rectangle of the shape.
    public var boundingRect: Rect {
        switch self {
        case .line(let s, let e):
            return Rect(
                minX: min(s.x, e.x), minY: min(s.y, e.y),
                maxX: max(s.x, e.x), maxY: max(s.y, e.y)
            )
        case .circle(let c, let r):
            return Rect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        case .rectangle(let o, let w, let h):
            return Rect(
                minX: min(o.x, o.x + w), minY: min(o.y, o.y + h),
                maxX: max(o.x, o.x + w), maxY: max(o.y, o.y + h)
            )
        case .arc(let c, let r, _, _):
            return Rect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        case .ellipse(let c, let rx, let ry, _):
            return Rect(minX: c.x - rx, minY: c.y - ry, maxX: c.x + rx, maxY: c.y + ry)
        case .polygon(let c, let r, _, _):
            return Rect(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        case .star(let c, let outer, _, _, _):
            return Rect(minX: c.x - outer, minY: c.y - outer, maxX: c.x + outer, maxY: c.y + outer)
        case .freehand(let points):
            guard !points.isEmpty else { return Rect() }
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            return Rect(minX: xs.min()!, minY: ys.min()!, maxX: xs.max()!, maxY: ys.max()!)
        }
    }
    
    /// Whether the shape is a closed loop (boundary): rectangles, circles,
    /// ellipses, polygons and stars are always closed; lines and arcs are
    /// open; a freehand polyline is closed only when its vertex list closes on
    /// itself (SPK-1101d trim boundary detection).
    public var isClosedShape: Bool {
        switch self {
        case .line, .arc:
            return false
        case .freehand(let points):
            return points.count >= 3 && points.first == points.last
        default:
            return true
        }
    }

    /// Whether the given point lies inside or on the boundary of this shape.
    public func contains(_ point: VectorPoint) -> Bool {
        switch self {
        case .line(let s, let e):
            // Point is on the line segment if cross product is ~0 and within bounds
            let dx = e.x - s.x, dy = e.y - s.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 1e-9 else { return hypot(point.x - s.x, point.y - s.y) < 1e-6 }
            let t = ((point.x - s.x) * dx + (point.y - s.y) * dy) / lenSq
            guard t >= 0.0 && t <= 1.0 else { return false }
            let closestX = s.x + t * dx, closestY = s.y + t * dy
            return hypot(point.x - closestX, point.y - closestY) < 1e-6
            
        case .circle(let c, let r):
            return hypot(point.x - c.x, point.y - c.y) <= r + 1e-6
            
        case .rectangle(let o, let w, let h):
            let minX = min(o.x, o.x + w), maxX = max(o.x, o.x + w)
            let minY = min(o.y, o.y + h), maxY = max(o.y, o.y + h)
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
            
        case .arc(let c, let r, let sa, let ea):
            // For arcs: check if distance to center ≈ radius and angle is within sweep
            let dist = hypot(point.x - c.x, point.y - c.y)
            guard abs(dist - r) < 1e-6 else { return false }
            let angle = atan2(point.y - c.y, point.x - c.x)
            let normalizedAngle = normalizeAngle(angle)
            let startNorm = normalizeAngle(sa)
            let endNorm = normalizeAngle(ea)
            if startNorm <= endNorm {
                return normalizedAngle >= startNorm && normalizedAngle <= endNorm
            } else {
                // Arc crosses 0/2π boundary
                return normalizedAngle >= startNorm || normalizedAngle <= endNorm
            }
            
        case .ellipse(let c, let rx, let ry, let rotation):
            let dx = point.x - c.x
            let dy = point.y - c.y
            let cos = cos(-rotation)
            let sin = sin(-rotation)
            let localX = dx * cos - dy * sin
            let localY = dx * sin + dy * cos
            return (localX * localX) / (rx * rx) + (localY * localY) / (ry * ry) <= 1.0 + 1e-6
            
        case .polygon(let c, let r, let sides, let rotation):
            // Check if point is inside regular polygon using ray casting
            let vertices = polygonVertices(center: c, radius: r, sides: sides, rotation: rotation)
            return isPointInPolygon(point, vertices: vertices)
            
        case .star(let c, let outerR, let innerR, let points, let rotation):
            let vertices = starVertices(center: c, outerRadius: outerR, innerRadius: innerR, points: points, rotation: rotation)
            return isPointInPolygon(point, vertices: vertices)
            
        case .freehand(let points):
            return isPointInPolygon(point, vertices: points)
        }
    }
    
    /// Translate the shape by (dx, dy).
    public func translated(by dx: Double, _ dy: Double) -> VectorShape {
        switch self {
        case .line(let s, let e):
            return .line(start: s.translated(dx, dy), end: e.translated(dx, dy))
        case .circle(let c, let r):
            return .circle(center: c.translated(dx, dy), radius: r)
        case .rectangle(let o, let w, let h):
            return .rectangle(origin: o.translated(dx, dy), width: w, height: h)
        case .arc(let c, let r, let sa, let ea):
            return .arc(center: c.translated(dx, dy), radius: r, startAngle: sa, endAngle: ea)
        case .ellipse(let c, let rx, let ry, let rot):
            return .ellipse(center: c.translated(dx, dy), radiusX: rx, radiusY: ry, rotation: rot)
        case .polygon(let c, let r, let s, let rot):
            return .polygon(center: c.translated(dx, dy), radius: r, sides: s, rotation: rot)
        case .star(let c, let or, let ir, let p, let rot):
            return .star(center: c.translated(dx, dy), outerRadius: or, innerRadius: ir, points: p, rotation: rot)
        case .freehand(let points):
            return .freehand(points: points.map { $0.translated(dx, dy) })
        }
    }
    
    /// Scale the shape by a factor about a center point.
    public func scaled(by factor: Double, about center: VectorPoint) -> VectorShape {
        switch self {
        case .line(let s, let e):
            return .line(
                start: s.scaled(factor, about: center),
                end: e.scaled(factor, about: center)
            )
        case .circle(let c, let r):
            return .circle(center: c.scaled(factor, about: center), radius: r * factor)
        case .rectangle(let o, let w, let h):
            return .rectangle(
                origin: o.scaled(factor, about: center),
                width: w * factor, height: h * factor
            )
        case .arc(let c, let r, let sa, let ea):
            return .arc(center: c.scaled(factor, about: center), radius: r * factor, startAngle: sa, endAngle: ea)
        case .ellipse(let c, let rx, let ry, let rot):
            return .ellipse(center: c.scaled(factor, about: center), radiusX: rx * factor, radiusY: ry * factor, rotation: rot)
        case .polygon(let c, let r, let s, let rot):
            return .polygon(center: c.scaled(factor, about: center), radius: r * factor, sides: s, rotation: rot)
        case .star(let c, let or, let ir, let p, let rot):
            return .star(center: c.scaled(factor, about: center), outerRadius: or * factor, innerRadius: ir * factor, points: p, rotation: rot)
        case .freehand(let points):
            return .freehand(points: points.map { $0.scaled(factor, about: center) })
        }
    }

    /// Mirror this shape across the vertical line `x = center.x`.
    public func flippedHorizontally(about center: VectorPoint) -> VectorShape {
        func mirror(_ p: VectorPoint) -> VectorPoint {
            VectorPoint(x: 2 * center.x - p.x, y: p.y)
        }
        switch self {
        case .line(let start, let end):
            return .line(start: mirror(start), end: mirror(end))
        case .circle(let c, let r):
            return .circle(center: mirror(c), radius: r)
        case .rectangle(let o, let w, let h):
            let corners = [
                o,
                VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h),
                VectorPoint(x: o.x, y: o.y + h),
            ]
            let m = corners.map(mirror)
            let xs = m.map(\.x)
            let ys = m.map(\.y)
            return .rectangle(
                origin: VectorPoint(x: xs.min()!, y: ys.min()!),
                width: xs.max()! - xs.min()!,
                height: ys.max()! - ys.min()!
            )
        case .arc(let c, let r, let sa, let ea):
            return .arc(center: mirror(c), radius: r, startAngle: .pi - ea, endAngle: .pi - sa)
        case .ellipse(let c, let rx, let ry, let rot):
            return .ellipse(center: mirror(c), radiusX: rx, radiusY: ry, rotation: -rot)
        case .polygon(let c, let r, let s, let rot):
            return .polygon(center: mirror(c), radius: r, sides: s, rotation: -rot)
        case .star(let c, let or, let ir, let p, let rot):
            return .star(center: mirror(c), outerRadius: or, innerRadius: ir, points: p, rotation: -rot)
        case .freehand(let points):
            return .freehand(points: points.map(mirror))
        }
    }
    
    /// Move the vertex at the given index to a new position.
    /// Returns a new shape; only `.freehand` (polyline) and `.line` are affected.
    /// For `.freehand`, `index` must be in `0..<points.count`.
    /// For `.line`, index 0 moves the start point, index 1 moves the end point.
    /// For all other shape cases, returns `self` unchanged.
    public func moveVertex(at index: Int, to point: VectorPoint) -> VectorShape {
        switch self {
        case .line(let s, let e):
            switch index {
            case 0: return .line(start: point, end: e)
            case 1: return .line(start: s, end: point)
            default: return self
            }
        case .freehand(var points):
            guard index >= 0, index < points.count else { return self }
            points[index] = point
            return .freehand(points: points)
        default:
            return self
        }
    }
    
    // MARK: - Helpers
    
    public var points: [VectorPoint] {
        switch self {
        case .line(let s, let e): return [s, e]
        case .circle(let c, _): return [c]
        case .rectangle(let o, _, _): return [o]
        case .arc(let c, _, _, _): return [c]
        case .ellipse(let c, _, _, _): return [c]
        case .polygon(let c, _, _, _): return [c]
        case .star(let c, _, _, _, _): return [c]
        case .freehand(let pts): return pts
        }
    }
    
    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return a
    }
}

// MARK: - VectorPoint Extensions

extension VectorPoint {
    func translated(_ dx: Double, _ dy: Double) -> VectorPoint {
        VectorPoint(x: x + dx, y: y + dy)
    }
    
    func scaled(_ factor: Double, about center: VectorPoint) -> VectorPoint {
        VectorPoint(
            x: center.x + (x - center.x) * factor,
            y: center.y + (y - center.y) * factor
        )
    }
}

// MARK: - Geometry Helpers

func polygonVertices(center: VectorPoint, radius: Double, sides: Int, rotation: Double = 0) -> [VectorPoint] {
    guard sides >= 3 else { return [] }
    return (0..<sides).map { i in
        let angle = rotation + 2.0 * .pi * Double(i) / Double(sides) - .pi / 2.0
        return VectorPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

func starVertices(center: VectorPoint, outerRadius: Double, innerRadius: Double, points: Int, rotation: Double = 0) -> [VectorPoint] {
    guard points >= 3, innerRadius < outerRadius else { return [] }
    var vertices: [VectorPoint] = []
    for i in 0..<(points * 2) {
        let angle = rotation + .pi * Double(i) / Double(points) - .pi / 2.0
        let r = i % 2 == 0 ? outerRadius : innerRadius
        vertices.append(VectorPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
    }
    return vertices
}

func isPointInPolygon(_ point: VectorPoint, vertices: [VectorPoint]) -> Bool {
    guard vertices.count > 2 else { return false }
    var inside = false
    var j = vertices.count - 1
    for i in 0..<vertices.count {
        let vi = vertices[i]
        let vj = vertices[j]
        if (vi.y > point.y) != (vj.y > point.y),
           point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y + 1e-12) + vi.x {
            inside.toggle()
        }
        j = i
    }
    return inside
}
