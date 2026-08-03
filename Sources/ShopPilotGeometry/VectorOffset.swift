import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - Offset Result

/// The result of offsetting a vector shape by a given distance.
public struct OffsetResult: Codable, Equatable {
    /// The original (unoffset) shape.
    public let original: VectorShape
    /// Points along the offset path.
    public let offsetPath: [VectorPoint]
    /// The signed offset distance applied (positive = outward).
    public let distance: Double

    public init(original: VectorShape, offsetPath: [VectorPoint], distance: Double) {
        self.original = original
        self.offsetPath = offsetPath
        self.distance = distance
    }

    /// True when at least one offset point was produced.
    public var isValid: Bool { !offsetPath.isEmpty }
}

// MARK: - Arc helpers (private)

/// Number of sample points used when approximating arcs.
private let arcSampleCount = 64

/// Normalise an angle to [0, 2π).
private func normaliseAngle(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a < 0 { a += 2 * .pi }
    return a
}

/// Generate evenly-spaced points along an arc (inclusive of start, exclusive of end to avoid duplication).
private func sampleArcPoints(center: VectorPoint, radius: Double, startAngle: Double, endAngle: Double) -> [VectorPoint] {
    guard radius > 1e-9 else { return [] }

    let sa = normaliseAngle(startAngle)
    let ea = normaliseAngle(endAngle)

    // Raw span BEFORE normalisation. A full-circle call (0 → 2π) normalises to
    // sa == ea and must NOT be treated as a zero-sweep degenerate arc — it is
    // the most common case (circle offset / circle profile cut). Previously the
    // full-circle case collapsed to a single point, silently producing garbage
    // toolpaths for every circle. (SPK review pass 2026-07-31)
    let rawSpan = endAngle - startAngle

    // Determine sweep direction (clockwise vs counter-clockwise).
    // We follow the same convention as Kernel.swift: positive angles are CCW.
    var sweep: Double
    if abs(rawSpan) >= 2 * .pi - 1e-9 {
        // Full turn (circle or multi-turn input): sample the entire circumference.
        sweep = rawSpan > 0 ? 2 * .pi : -2 * .pi
    } else if ea >= sa {
        sweep = ea - sa
    } else {
        sweep = 2 * .pi - (sa - ea)
    }

    guard abs(sweep) > 1e-9 else { return [VectorPoint(x: center.x + radius, y: center.y)] }

    let count = max(2, arcSampleCount)
    var points: [VectorPoint] = []
    for i in 0..<count {
        let t = Double(i) / Double(count - 1) // 0..1 inclusive
        let angle = sa + sweep * t
        points.append(VectorPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        ))
    }
    return points
}

// MARK: - Vector Offset Calculator

/// Static utility class providing parallel offset operations for each vector shape type.
public final class VectorOffsetCalculator {

    // MARK: Line offset

    /// Offsets a line segment parallel to itself by the given signed distance.
    /// Positive distance shifts to the left of the directed line (start→end).
    public static func offsetLine(_ line: VectorShape, by distance: Double) -> OffsetResult? {
        guard case .line(let start, let end) = line else { return nil }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 1e-9 else {
            // Degenerate zero-length line — offset the single point.
            return OffsetResult(
                original: line,
                offsetPath: [VectorPoint(x: start.x - distance, y: start.y)],
                distance: distance
            )
        }

        let len = sqrt(lenSq)
        // Left normal (perpendicular, pointing left of the directed segment).
        let nx = -dy / len
        let ny = dx / len

        let p1 = VectorPoint(x: start.x + nx * distance, y: start.y + ny * distance)
        let p2 = VectorPoint(x: end.x + nx * distance, y: end.y + ny * distance)

        return OffsetResult(original: line, offsetPath: [p1, p2], distance: distance)
    }

    // MARK: Circle offset

    /// Offsets a circle by expanding (positive distance) or contracting (negative distance) its radius.
    public static func offsetCircle(circle: VectorShape, by distance: Double) -> OffsetResult? {
        guard case .circle(let center, let radius) = circle else { return nil }

        let newRadius = radius + distance
        guard newRadius > 1e-9 else {
            // Collapsed to a point.
            return OffsetResult(original: circle, offsetPath: [center], distance: distance)
        }

        let points = sampleArcPoints(center: center, radius: newRadius, startAngle: 0, endAngle: 2 * .pi)
        return OffsetResult(original: circle, offsetPath: points, distance: distance)
    }

    // MARK: Rectangle offset

    /// Expands or contracts a rectangle's edges by the given signed distance.
    /// Positive = outward expansion; negative = inward contraction.
    public static func offsetRectangle(rect: VectorShape, by distance: Double) -> OffsetResult? {
        guard case .rectangle(let origin, let w, let h) = rect else { return nil }

        // Rectangle corners in design-space order (CCW from top-left-ish).
        let minX = min(origin.x, origin.x + w)
        let maxX = max(origin.x, origin.x + w)
        let minY = min(origin.y, origin.y + h)
        let maxY = max(origin.y, origin.y + h)

        // Expand/contract each edge outward by `distance`.
        let p1 = VectorPoint(x: minX - distance, y: minY - distance)
        let p2 = VectorPoint(x: maxX + distance, y: minY - distance)
        let p3 = VectorPoint(x: maxX + distance, y: maxY + distance)
        let p4 = VectorPoint(x: minX - distance, y: maxY + distance)

        // If the rectangle collapses (negative offset too large), return empty.
        let newW = (maxX + distance) - (minX - distance)
        let newH = (maxY + distance) - (minY - distance)
        guard newW > 1e-9 && newH > 1e-9 else {
            return OffsetResult(original: rect, offsetPath: [], distance: distance)
        }

        // Return as a closed polygon (4 corners + repeat first to close).
        let path = [p1, p2, p3, p4, p1]
        return OffsetResult(original: rect, offsetPath: path, distance: distance)
    }

    // MARK: Arc offset

    /// Offsets an arc by adjusting its radius (center stays fixed).
    /// Positive = outward; negative = inward.
    public static func offsetArc(arc: VectorShape, by distance: Double) -> OffsetResult? {
        guard case .arc(let center, let radius, let startAngle, let endAngle) = arc else { return nil }

        let newRadius = radius + distance
        guard newRadius > 1e-9 else {
            // Collapsed to a point.
            return OffsetResult(original: arc, offsetPath: [center], distance: distance)
        }

        let points = sampleArcPoints(center: center, radius: newRadius, startAngle: startAngle, endAngle: endAngle)
        return OffsetResult(original: arc, offsetPath: points, distance: distance)
    }

    // MARK: Closed polyline offset

    /// Offsets a closed polyline (arbitrary polygon) by the given signed distance.
    /// Each edge is shifted parallel to itself, and consecutive offset edges are
    /// intersected (miter join) to produce sharp corners. Positive distance =
    /// outward; negative = inward — regardless of the polygon's winding.
    public static func offsetClosedPolyline(points: [VectorPoint], by distance: Double) -> OffsetResult? {
        guard points.count >= 3 else { return nil }

        // Normalize: an explicit closing duplicate (first == last) is dropped so
        // each corner is processed exactly once.
        var pts = points
        if pts.count > 1, pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return nil }

        // Winding via signed area (shoelace). Positive = CCW.
        var area2 = 0.0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            area2 += a.x * b.y - b.x * a.y
        }
        let isCCW = area2 > 0

        // Outward unit normal of edge (from → to):
        //   CCW → right normal (dy, -dx)/len;  CW → left normal (-dy, dx)/len.
        func outwardNormal(_ from: VectorPoint, _ to: VectorPoint) -> (Double, Double)? {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 1e-9 else { return nil }
            if isCCW {
                return (dy / len, -dx / len)
            } else {
                return (-dy / len, dx / len)
            }
        }

        // Miter join: vertex v is replaced by the intersection of its two offset
        // edge lines. With outward unit normals n1 (incoming edge) and n2
        // (outgoing edge):  v' = v + d * (n1 + n2) / (1 + n1·n2).
        var offsetVerts: [VectorPoint] = []
        let n = pts.count
        for i in 0..<n {
            let prev = pts[(i - 1 + n) % n]
            let curr = pts[i]
            let next = pts[(i + 1) % n]

            guard let n1 = outwardNormal(prev, curr),
                  let n2 = outwardNormal(curr, next) else { continue }

            let dot = n1.0 * n2.0 + n1.1 * n2.1
            let denom = 1.0 + dot
            // Denom ≈ 0 → edges are (near-)collinear in opposite directions
            // (spike); drop the degenerate corner rather than explode.
            guard abs(denom) > 1e-9 else { continue }

            let scale = distance / denom
            offsetVerts.append(VectorPoint(
                x: curr.x + (n1.0 + n2.0) * scale,
                y: curr.y + (n1.1 + n2.1) * scale
            ))
        }

        guard offsetVerts.count >= 3 else { return nil }

        // Always emit an explicitly closed path: corners + closing point.
        var offsetPath = offsetVerts
        offsetPath.append(offsetVerts[0])

        return OffsetResult(
            original: .freehand(points: points),
            offsetPath: offsetPath,
            distance: distance
        )
    }

    // MARK: Shape-level dispatcher

    /// Offset any shape by a signed distance, returning concrete `VectorShape`s
    /// the design editor can commit to the session. Positive = outward.
    ///
    /// - line → offset line segment (freehand polyline, 2 points)
    /// - circle → circle with adjusted radius
    /// - rectangle → rectangle with expanded/contracted extents
    /// - arc → freehand polyline along the offset arc
    /// - freehand (closed) → offset closed polyline
    /// - ellipse/polygon/star → freehand polyline of the offset outline
    ///
    /// Returns an empty array when the shape collapses (offset larger than the
    /// shape) or the input type cannot be offset.
    public static func offsetShape(_ shape: VectorShape, by distance: Double) -> [VectorShape] {
        switch shape {
        case .line:
            guard let r = offsetLine(shape, by: distance), r.offsetPath.count >= 2 else { return [] }
            return [.freehand(points: r.offsetPath)]

        case .circle(let center, let radius):
            let newRadius = radius + distance
            guard newRadius > 1e-9 else { return [] }
            return [.circle(center: center, radius: newRadius)]

        case .rectangle(let origin, let w, let h):
            guard let r = offsetRectangle(rect: shape, by: distance), r.offsetPath.count >= 4 else { return [] }
            // Rebuild a rectangle from the offset box corners.
            let xs = r.offsetPath.map { $0.x }
            let ys = r.offsetPath.map { $0.y }
            let minX = xs.min() ?? origin.x
            let maxX = xs.max() ?? (origin.x + w)
            let minY = ys.min() ?? origin.y
            let maxY = ys.max() ?? (origin.y + h)
            guard maxX - minX > 1e-9, maxY - minY > 1e-9 else { return [] }
            return [.rectangle(origin: VectorPoint(x: minX, y: minY), width: maxX - minX, height: maxY - minY)]

        case .arc:
            guard let r = offsetArc(arc: shape, by: distance), r.offsetPath.count >= 2 else { return [] }
            return [.freehand(points: r.offsetPath)]

        case .ellipse(let center, let rx, let ry, let rotation):
            let newRX = rx + distance
            let newRY = ry + distance
            guard newRX > 1e-9, newRY > 1e-9 else { return [] }
            return [.ellipse(center: center, radiusX: newRX, radiusY: newRY, rotation: rotation)]

        case .polygon(let center, let radius, let sides, let rotation):
            let newRadius = radius + distance
            guard newRadius > 1e-9 else { return [] }
            return [.polygon(center: center, radius: newRadius, sides: sides, rotation: rotation)]

        case .star(let center, let outer, let inner, let points, let rotation):
            let newOuter = outer + distance
            let newInner = inner + distance
            guard newOuter > 1e-9, newInner > 1e-9 else { return [] }
            return [.star(center: center, outerRadius: newOuter, innerRadius: newInner, points: points, rotation: rotation)]

        case .freehand(let pts):
            guard let r = offsetClosedPolyline(points: pts, by: distance), r.offsetPath.count >= 3 else { return [] }
            return [.freehand(points: r.offsetPath)]
        }
    }

    /// Find intersection point of two lines defined by point + direction.
    /// Returns nil if lines are parallel.
    private static func lineIntersection(
        p1: VectorPoint, d1: (Double, Double),
        p2: VectorPoint, d2: (Double, Double)
    ) -> VectorPoint? {
        let (d1x, d1y) = d1
        let (d2x, d2y) = d2
        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 1e-12 else { return nil }

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y

        let t = (dx * d2y - dy * d2x) / denom
        return VectorPoint(x: p1.x + t * d1x, y: p1.y + t * d1y)
    }
}

// MARK: - Profile Offset Generator

/// ObservableObject that generates toolpath offsets for CNC profile cutting.
/// Accounts for tool radius compensation so the cutter follows the correct path relative to the design shape.
@MainActor
public final class ProfileOffsetGenerator: ObservableObject {

    /// Generates one or more offset results for a set of shapes, compensating for tool diameter.
    ///
    /// - Parameters:
    ///   - shapes: The vector shapes defining the profile boundary.
    ///   - offsetDistance: Additional offset beyond tool radius (e.g. for clearance or stepover).
    ///   - toolDiameter: Diameter of the cutting tool in design units.
    /// - Returns: An array of `OffsetResult` representing the computed toolpath offsets.
    public func generateProfileOffsets(
        shapes: [VectorShape],
        offsetDistance: Double = 0.0,
        toolDiameter: Double
    ) -> [OffsetResult] {
        let toolRadius = toolDiameter / 2.0

        var results: [OffsetResult] = []

        for shape in shapes {
            switch shape {
            case .line:
                if let result = VectorOffsetCalculator.offsetLine(shape, by: offsetDistance + toolRadius) {
                    results.append(result)
                }
            case .circle:
                if let result = VectorOffsetCalculator.offsetCircle(circle: shape, by: offsetDistance + toolRadius) {
                    results.append(result)
                }
            case .rectangle:
                if let result = VectorOffsetCalculator.offsetRectangle(rect: shape, by: offsetDistance + toolRadius) {
                    results.append(result)
                }
            case .arc:
                if let result = VectorOffsetCalculator.offsetArc(arc: shape, by: offsetDistance + toolRadius) {
                    results.append(result)
                }
            case .ellipse, .polygon, .star, .freehand:
                break
            }
        }

        return results
    }

    /// Generates inside and outside profile offsets for a closed shape set.
    /// Useful when the user wants both the outer cut path and an inner pocket boundary.
    ///
    /// - Parameters:
    ///   - shapes: The vector shapes defining the profile.
    ///   - toolDiameter: Diameter of the cutting tool.
    ///   - allowance: Extra material to leave (positive = more stock left behind).
    /// - Returns: Two offset results — `[outside, inside]`. Empty if a side cannot be computed.
    public func generateDualProfileOffsets(
        shapes: [VectorShape],
        toolDiameter: Double,
        allowance: Double = 0.0
    ) -> [OffsetResult] {
        let outsideToolRadius = toolDiameter / 2.0 + allowance
        let insideToolRadius = max(toolDiameter / 2.0 - allowance, 1e-9)

        var results: [OffsetResult] = []

        for shape in shapes {
            // Outside offset (positive = outward from shape).
            switch shape {
            case .line:
                if let r = VectorOffsetCalculator.offsetLine(shape, by: outsideToolRadius) {
                    results.append(r)
                }
            case .circle:
                if let r = VectorOffsetCalculator.offsetCircle(circle: shape, by: outsideToolRadius) {
                    results.append(r)
                }
            case .rectangle:
                if let r = VectorOffsetCalculator.offsetRectangle(rect: shape, by: outsideToolRadius) {
                    results.append(r)
                }
            case .arc:
                if let r = VectorOffsetCalculator.offsetArc(arc: shape, by: outsideToolRadius) {
                    results.append(r)
                }
            case .ellipse, .polygon, .star, .freehand:
                break
            }

            // Inside offset (negative = inward from shape).
            switch shape {
            case .line:
                if let r = VectorOffsetCalculator.offsetLine(shape, by: -insideToolRadius) {
                    results.append(r)
                }
            case .circle:
                if let r = VectorOffsetCalculator.offsetCircle(circle: shape, by: -insideToolRadius) {
                    results.append(r)
                }
            case .rectangle:
                if let r = VectorOffsetCalculator.offsetRectangle(rect: shape, by: -insideToolRadius) {
                    results.append(r)
                }
            case .arc:
                if let r = VectorOffsetCalculator.offsetArc(arc: shape, by: -insideToolRadius) {
                    results.append(r)
                }
            case .ellipse, .polygon, .star, .freehand:
                break
            }
        }

        return results
    }
}
