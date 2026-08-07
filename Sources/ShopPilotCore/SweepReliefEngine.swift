import Foundation

// MARK: - Two-rail sweep relief engine (SPK-0714 lean slice)

/// REAL engine behind the legacy `SweepExtrudeWeaveEngine` stub (estimate-only
/// volume/surface math — this produces an actual heightfield). Sweeps a
/// profile between two rails (aligned polylines) and rasterizes the swept
/// region onto a grid, so the result drops straight into the component stack.
///
/// Lean slice: rails are re-sampled to the same point count by length
/// fraction; the swept region is the quad strip between consecutive rail
/// points. Rectangle profile = flat top at `height`; circle profile = domed
/// top (full height on the centerline, falling to 0 at the rail edges).
/// Extrude/weave full-3D variants stay Phase H.
public enum SweepReliefEngine {

    /// Sweep between two rails and rasterize onto a heightfield.
    /// `rail1`/`rail2` are world-space polylines (may differ in point count —
    /// both are re-sampled to `samples` by length fraction). The grid spans
    /// the swept region's bounding box at `cellSizeMm`.
    public static func sweep(
        rail1: [VectorPoint],
        rail2: [VectorPoint],
        profile: SweepProfile,
        height: Double,
        cellSizeMm: Double = 1.0,
        samples: Int = 40
    ) -> HeightfieldData? {
        guard rail1.count >= 2, rail2.count >= 2 else { return nil }
        let a = resample(rail1, samples: max(4, samples))
        let b = resample(rail2, samples: max(4, samples))
        guard a.count == b.count else { return nil }

        // Swept region = polygon strip A0 B0 B1 A1 … A0.
        var strip: [VectorPoint] = []
        strip.append(contentsOf: a)
        strip.append(contentsOf: b.reversed())
        guard strip.count >= 4 else { return nil }

        let xs = strip.map(\.x)
        let ys = strip.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let cols = max(2, Int(((maxX - minX) / cellSizeMm).rounded()))
        let rows = max(2, Int(((maxY - minY) / cellSizeMm).rounded()))
        let peak = max(0, height)
        var heights = [Double](repeating: 0, count: cols * rows)

        for j in 0..<rows {
            for i in 0..<cols {
                let wx = minX + (Double(i) + 0.5) * cellSizeMm
                let wy = minY + (Double(j) + 0.5) * cellSizeMm
                let p = VectorPoint(x: wx, y: wy)
                guard pointInPolygon(p, strip) else { continue }
                switch profile {
                case .circle:
                    // Dome across the strip: height = peak·(1 − t) where t is
                    // the distance from the centerline normalized by the local
                    // half-width (half the rail separation at that station).
                    let centerline = midpointPolyline(a: a, b: b)
                    let d = distanceToPolyline(p, centerline)
                    let halfWidth = localHalfWidth(at: p, centerline: centerline, a: a, b: b)
                    let t = halfWidth > 1e-9 ? min(1.0, d / halfWidth) : 1.0
                    heights[j * cols + i] = peak * max(0, 1 - t)
                default:
                    // Rectangle (and custom/path) = flat top.
                    heights[j * cols + i] = peak
                }
            }
        }
        return HeightfieldData(
            width: cols, height: rows,
            cellSizeMm: cellSizeMm, minX: minX, minY: minY,
            heights: heights
        )
    }

    // MARK: - Helpers

    /// Re-sample a polyline to `count` points by cumulative length fraction.
    static func resample(_ points: [VectorPoint], samples: Int) -> [VectorPoint] {
        guard points.count >= 2 else { return points }
        let cumulative = cumulativeLengths(points)
        let total = cumulative.last ?? 1
        guard total > 1e-9 else { return points }
        var out: [VectorPoint] = []
        var seg = 0
        for k in 0..<samples {
            let target = total * Double(k) / Double(samples - 1)
            while seg < cumulative.count - 2 && cumulative[seg + 1] < target - 1e-12 {
                seg += 1
            }
            let segLen = cumulative[seg + 1] - cumulative[seg]
            let t = segLen > 1e-12 ? (target - cumulative[seg]) / segLen : 0
            let p0 = points[seg]
            let p1 = points[min(seg + 1, points.count - 1)]
            out.append(VectorPoint(
                x: p0.x + (p1.x - p0.x) * t,
                y: p0.y + (p1.y - p0.y) * t
            ))
        }
        return out
    }

    static func cumulativeLengths(_ points: [VectorPoint]) -> [Double] {
        var out: [Double] = [0]
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            out.append(out[i - 1] + sqrt(dx * dx + dy * dy))
        }
        return out
    }

    /// Distance from a point to a polyline (min over segments).
    static func distanceToPolyline(_ p: VectorPoint, _ poly: [VectorPoint]) -> Double {
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(poly.count - 1) {
            best = min(best, distanceToSegment(p, poly[i], poly[i + 1]))
        }
        return best
    }

    static func distanceToSegment(_ p: VectorPoint, _ a: VectorPoint, _ b: VectorPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 1e-12 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Midpoint polyline of the two rails (the sweep centerline).
    static func midpointPolyline(a: [VectorPoint], b: [VectorPoint]) -> [VectorPoint] {
        var out: [VectorPoint] = []
        for i in 0..<min(a.count, b.count) {
            out.append(VectorPoint(
                x: (a[i].x + b[i].x) / 2,
                y: (a[i].y + b[i].y) / 2
            ))
        }
        return out
    }

    /// Half-width of the strip at the cell's nearest centerline station:
    /// half the rail separation, interpolated at the projection index.
    static func localHalfWidth(at p: VectorPoint, centerline: [VectorPoint], a: [VectorPoint], b: [VectorPoint]) -> Double {
        guard centerline.count >= 2 else { return 1.0 }
        // Nearest centerline vertex index.
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, c) in centerline.enumerated() {
            let d = hypot(p.x - c.x, p.y - c.y)
            if d < bestD { bestD = d; best = i }
        }
        let ai = min(best, a.count - 1)
        let bi = min(best, b.count - 1)
        return max(0.001, hypot(a[ai].x - b[bi].x, a[ai].y - b[bi].y) / 2.0)
    }

    /// Even-odd ray-cast point-in-polygon.
    static func pointInPolygon(_ p: VectorPoint, _ poly: [VectorPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
