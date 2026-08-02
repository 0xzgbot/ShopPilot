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
    /// intersected to produce sharp corners. Positive distance = outward; negative = inward.
    public static func offsetClosedPolyline(points: [VectorPoint], by distance: Double) -> OffsetResult? {
        guard points.count >= 3 else { return nil }

        var offsetVerts: [VectorPoint] = []
        for i in 0..<points.count {
            let curr = points[i]
            let prev = points[(i - 1 + points.count) % points.count]
            let next = points[(i + 1) % points.count]

            let dx1 = curr.x - prev.x
            let dy1 = curr.y - prev.y
            let len1 = sqrt(dx1 * dx1 + dy1 * dy1)

            let dx2 = next.x - curr.x
            let dy2 = next.y - curr.y
            let len2 = sqrt(dx2 * dx2 + dy2 * dy2)

            guard len1 > 1e-9, len2 > 1e-9 else { continue }

            let nx1 = -dy1 / len1
            let ny1 = dx1 / len1
            let nx2 = -dy2 / len2
            let ny2 = dx2 / len2

            let nx = (nx1 + nx2) / 2.0
            let ny = (ny1 + ny2) / 2.0
            let nLen = sqrt(nx * nx + ny * ny)
            guard nLen > 1e-9 else { continue }

            offsetVerts.append(VectorPoint(
                x: curr.x + nx / nLen * distance,
                y: curr.y + ny / nLen * distance
            ))
        }

        guard !offsetVerts.isEmpty else { return nil }

        var offsetPath: [VectorPoint] = []
        for i in 0..<offsetVerts.count {
            let curr = offsetVerts[i]
            let next = offsetVerts[(i + 1) % offsetVerts.count]
            let prev = offsetVerts[(i - 1 + offsetVerts.count) % offsetVerts.count]

            let e1dx = curr.x - prev.x
            let e1dy = curr.y - prev.y
            let e2dx = next.x - curr.x
            let e2dy = next.y - curr.y

            if let intersection = lineIntersection(
                p1: prev, d1: (e1dx, e1dy),
                p2: curr, d2: (e2dx, e2dy)
            ) {
                offsetPath.append(intersection)
            }
        }

        if offsetPath.isEmpty {
            offsetPath = offsetVerts
        }

        if let first = offsetPath.first, offsetPath.last != first {
            offsetPath.append(first)
        }

        return OffsetResult(
            original: .freehand(points: points),
            offsetPath: offsetPath,
            distance: distance
        )
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
