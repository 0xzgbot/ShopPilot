import Foundation

// MARK: - VectorBoundary (SPK-1321)

/// Vector boundary engine (Vectric's C17 "Vector Boundary").
///
/// Given a set of shapes, produces ONE closed outline that encloses them
/// all — the convex hull of a densely sampled point cloud — optionally
/// inflated outward (positive offset) or shrunk inward (negative offset).
/// Used for edge cleanup, tabs, and containment.
///
/// The offset is a simple, deterministic outward inflation: each hull vertex
/// is pushed away from the hull centroid by `offsetMm` along the
/// vertex-centroid ray. Positive offsets grow the boundary; negative offsets
/// pull it inward toward the centroid.
public enum VectorBoundary {

    /// Number of samples along a run of `length` mm at `perMm` samples/mm.
    /// Never fewer than 2 so endpoints always survive.
    private static func sampleCount(length: Double, perMm: Double) -> Int {
        guard length.isFinite, length > 0, perMm > 0 else { return 2 }
        return max(2, Int((length / perMm).rounded(.up)))
    }

    /// Sample a straight segment end-to-end (endpoints + interior).
    private static func sampleSegment(_ s: VectorPoint, _ e: VectorPoint, perMm: Double) -> [VectorPoint] {
        let dx = e.x - s.x, dy = e.y - s.y
        let len = (dx * dx + dy * dy).squareRoot()
        let n = sampleCount(length: len, perMm: perMm)
        return (0...n).map { k in
            let t = Double(k) / Double(n)
            return VectorPoint(x: s.x + t * dx, y: s.y + t * dy)
        }
    }

    /// Sample every edge of a closed polyline (last vertex wraps to first),
    /// corner points included once per incident edge.
    private static func sampleClosedPolyline(_ vertices: [VectorPoint], perMm: Double) -> [VectorPoint] {
        guard vertices.count >= 2 else { return vertices }
        var out: [VectorPoint] = []
        for i in 0..<vertices.count {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertices.count]
            out.append(a)
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            let n = sampleCount(length: len, perMm: perMm)
            if n > 1 {
                for k in 1..<n {
                    let t = Double(k) / Double(n)
                    out.append(VectorPoint(x: a.x + t * dx, y: a.y + t * dy))
                }
            }
        }
        return out
    }

    // MARK: - Point Cloud

    /// Sample every shape into a dense point cloud.
    ///
    /// - Circles/ellipses/arcs are sampled by angle; polygons/stars by their
    ///   vertices plus sampled edges; lines/rectangles by endpoints plus
    ///   sampled edges; freehand polylines pass through as-is.
    /// - `samplePerMm` controls density (samples per millimetre of perimeter/
    ///   length); 1.0 samples roughly every millimetre.
    /// - Empty shapes → `[]`.
    public static func points(from shapes: [VectorShape], samplePerMm: Double = 1.0) -> [VectorPoint] {
        guard !shapes.isEmpty else { return [] }
        let perMm = samplePerMm > 0 ? samplePerMm : 1.0
        var out: [VectorPoint] = []
        for shape in shapes {
            switch shape {
            case .line(let s, let e):
                out.append(contentsOf: sampleSegment(s, e, perMm: perMm))

            case .circle(let c, let r):
                let circumference = 2 * .pi * max(abs(r), 0)
                let n = max(8, sampleCount(length: circumference, perMm: perMm))
                for i in 0..<n {
                    let a = 2 * .pi * Double(i) / Double(n)
                    out.append(VectorPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                }

            case .rectangle(let o, let w, let h):
                let corners = [
                    o,
                    VectorPoint(x: o.x + w, y: o.y),
                    VectorPoint(x: o.x + w, y: o.y + h),
                    VectorPoint(x: o.x, y: o.y + h),
                ]
                out.append(contentsOf: sampleClosedPolyline(corners, perMm: perMm))

            case .arc(let c, let r, let sa, let ea):
                var sweep = ea - sa
                if abs(sweep) < 1e-12 { sweep = 2 * .pi } // degenerate → full circle
                let arcLength = abs(sweep) * max(abs(r), 0)
                let n = max(2, sampleCount(length: arcLength, perMm: perMm))
                for i in 0...n {
                    let t = Double(i) / Double(n)
                    let a = sa + sweep * t
                    out.append(VectorPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                }

            case .ellipse(let c, let rx, let ry, let rot):
                let a = abs(rx), b = abs(ry)
                let perimeter = (a + b) > 0
                    ? .pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
                    : 0
                let n = max(8, sampleCount(length: perimeter, perMm: perMm))
                let cr = cos(rot), sr = sin(rot)
                for i in 0..<n {
                    let t = 2 * .pi * Double(i) / Double(n)
                    let ct = cos(t), st = sin(t)
                    out.append(VectorPoint(
                        x: c.x + a * ct * cr - b * st * sr,
                        y: c.y + a * ct * sr + b * st * cr
                    ))
                }

            case .polygon(let c, let r, let sides, let rot):
                out.append(contentsOf: sampleClosedPolyline(
                    polygonVertices(center: c, radius: r, sides: sides, rotation: rot),
                    perMm: perMm
                ))

            case .star(let c, let or, let ir, let p, let rot):
                out.append(contentsOf: sampleClosedPolyline(
                    starVertices(center: c, outerRadius: or, innerRadius: ir, points: p, rotation: rot),
                    perMm: perMm
                ))

            case .freehand(let pts):
                out.append(contentsOf: pts)
            }
        }
        return out
    }

    // MARK: - Convex Hull

    /// Andrew's monotone chain convex hull.
    ///
    /// - Returns the hull vertices in counter-clockwise order (collinear
    ///   points removed — each hull edge is a true supporting line).
    /// - Exact/near-duplicate points are removed first.
    /// - Fewer than 3 distinct points → the points returned as-is.
    public static func convexHull(_ points: [VectorPoint]) -> [VectorPoint] {
        guard points.count >= 3 else { return points }

        // Sort lexicographically (x, then y) and drop duplicates.
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        var unique: [VectorPoint] = []
        for p in sorted {
            if let last = unique.last,
               abs(last.x - p.x) < 1e-9, abs(last.y - p.y) < 1e-9 {
                continue
            }
            unique.append(p)
        }
        guard unique.count >= 3 else { return unique }

        func cross(_ o: VectorPoint, _ a: VectorPoint, _ b: VectorPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [VectorPoint] = []
        for p in unique {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [VectorPoint] = []
        for p in unique.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast() // last of lower == first of upper
        upper.removeLast() // last of upper == first of lower
        return lower + upper // counter-clockwise
    }

    // MARK: - Boundary Path

    /// One closed outline enclosing all shapes: the convex hull of the
    /// sampled point cloud, then offset outward by `offsetMm`.
    ///
    /// The offset inflates each hull vertex away from the hull centroid along
    /// the vertex-centroid ray (deterministic, no self-intersection for
    /// positive offsets). Negative offsets shrink inward; 0 returns the hull
    /// untouched. Empty shapes → `[]`.
    public static func boundaryPath(for shapes: [VectorShape], offsetMm: Double = 0, samplePerMm: Double = 1.0) -> [VectorPoint] {
        let pts = points(from: shapes, samplePerMm: samplePerMm)
        guard !pts.isEmpty else { return [] }
        let hull = convexHull(pts)
        guard hull.count >= 3, offsetMm != 0 else { return hull }

        var cx = 0.0, cy = 0.0
        for p in hull { cx += p.x; cy += p.y }
        cx /= Double(hull.count)
        cy /= Double(hull.count)

        return hull.map { p in
            let dx = p.x - cx, dy = p.y - cy
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-12 else { return p } // degenerate (vertex == centroid)
            return VectorPoint(x: p.x + dx / len * offsetMm, y: p.y + dy / len * offsetMm)
        }
    }

    // MARK: - Area

    /// Shoelace area of a polygon; always non-negative (absolute value).
    /// A counter-clockwise polygon yields positive area. < 3 points → 0.
    public static func area(_ polygon: [VectorPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2.0
    }
}
