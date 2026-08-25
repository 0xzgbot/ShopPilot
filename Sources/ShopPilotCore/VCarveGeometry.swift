import Foundation

// MARK: - V-carve valley geometry, SPK-2010a
//
// Depth for a V-bit comes from the LOCAL channel half-width, never from the
// point's page position. At half-width w and included bit angle A, the bit
// bottom sits at z = -(w / tan(A/2)), clamped to max depth. Wide regions go
// deep; necks stay shallow.

public enum VCarveGeometry {

    /// Z depth (negative, below stock top) for a given local half-width.
    ///
    /// - Parameters:
    ///   - halfWidth: clearance to the nearest other edge (mm).
    ///   - toolAngleDegrees: full included angle of the V-bit.
    ///   - maxDepth: maximum carve depth in mm (positive magnitude).
    public static func depthForHalfWidth(
        _ halfWidth: Double,
        angle toolAngleDegrees: Double,
        maxDepth: Double
    ) -> Double {
        guard halfWidth > 0 else { return 0 }

        let halfAngleRad = max(1e-6, toolAngleDegrees / 2.0 * .pi / 180.0)
        let tan = Foundation.tan(halfAngleRad)
        if tan <= 1e-9 { return -maxDepth }

        let depth = halfWidth / tan
        return -min(depth, maxDepth)
    }

    /// Distance from a vertex of one vector to the nearest edge of any
    /// vector that is NOT one of that vertex's own two adjoining segments.
    /// Those two segments are always at distance zero and say nothing about
    /// the channel width — skipping them is what makes this an approximation
    /// of the medial-axis radius at the vertex.
    public static func distanceToNearestOtherEdge(
        _ vector: VectorPath,
        index: Int,
        allVectors: [VectorPath]
    ) -> Double {
        guard index >= 0 && index < vector.points.count else { return 0 }
        let p = vector.points[index]
        var best = Double.infinity

        for other in allVectors {
            let pts = other.points
            if pts.count < 2 { continue }
            let same = (other.id == vector.id)

            // Closed loops wrap; open polylines do not.
            let segCount = other.isClosed ? pts.count : pts.count - 1
            for s in 0..<max(0, segCount) {
                let a = s, b = (s + 1) % pts.count

                // Skip the two segments touching this point.
                if same && (a == index || b == index) { continue }

                let d = pointToSegment(p, pts[a], pts[b])
                if d < best { best = d }
            }
        }

        return best.isFinite ? best : 0
    }

    static func pointToSegment(_ p: VectorPoint, _ a: VectorPoint, _ b: VectorPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 1e-18 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
