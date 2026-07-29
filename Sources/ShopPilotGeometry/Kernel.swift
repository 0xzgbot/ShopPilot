import Foundation

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
public struct VectorPoint: Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double
    
    public init(x: Double = 0.0, y: Double = 0.0) {
        self.x = x
        self.y = y
    }
}

// MARK: - Vector Shape

/// A 2D vector shape used in the design kernel.
public enum VectorShape: Codable, Equatable {
    case line(start: VectorPoint, end: VectorPoint)
    case circle(center: VectorPoint, radius: Double)
    case rectangle(origin: VectorPoint, width: Double, height: Double)
    case arc(center: VectorPoint, radius: Double, startAngle: Double, endAngle: Double)
    
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
        }
    }
    
    // MARK: - Helpers
    
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
