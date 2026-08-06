import Foundation

// MARK: - Fillet & Extend (SPK-0215)

/// Rounds the corners of selected vectors, Aspire-style.
///
/// Freehand polylines get every applicable interior vertex rounded (including
/// the wrap vertex on closed loops); rectangles convert to a rounded-corner
/// freehand polyline. The fillet arc is sampled as polyline points, so the
/// result flows through the existing toolpath engines unchanged.
public enum ShapeFilletEngine {

    /// Fillet every applicable corner of a shape. Circles, ellipses, arcs,
    /// polygons, stars and lines are returned unchanged.
    public static func fillet(_ shape: VectorShape, radius: Double) -> VectorShape {
        guard radius > 1e-9 else { return shape }
        switch shape {
        case .freehand(let pts):
            guard pts.count >= 3 else { return shape }
            return .freehand(points: filletPolyline(pts, radius: radius))
        case .rectangle(let o, let w, let h):
            let corners = [
                VectorPoint(x: o.x, y: o.y),
                VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h),
                VectorPoint(x: o.x, y: o.y + h),
            ]
            let rounded = filletPolyline(corners + [corners[0]], radius: radius)
            return .freehand(points: rounded)
        default:
            return shape
        }
    }

    /// Round every corner of a polyline. Closed loops (first == last) get the
    /// wrap vertex rounded too. A corner whose adjacent segments are too short
    /// for the requested radius has the radius clamped to fit (never fails).
    public static func filletPolyline(_ points: [VectorPoint], radius: Double) -> [VectorPoint] {
        guard points.count >= 3, radius > 1e-9 else { return points }
        let closed = points.first == points.last
        let n = closed ? points.count - 1 : points.count
        guard n >= 3 else { return points }

        // Fillet ONE corner: replace the vertex with [tA, arc…, tB].
        func filletCorner(prev: VectorPoint, cur: VectorPoint, next: VectorPoint) -> [VectorPoint]? {
            let ux = cur.x - prev.x, uy = cur.y - prev.y
            let vx = next.x - cur.x, vy = next.y - cur.y
            let lu = (ux * ux + uy * uy).squareRoot()
            let lv = (vx * vx + vy * vy).squareRoot()
            guard lu > 1e-9, lv > 1e-9 else { return nil }
            let u = (ux / lu, uy / lu)          // direction INTO the corner
            let v = (vx / lv, vy / lv)          // direction OUT of the corner
            let dotUV = max(-1.0, min(1.0, u.0 * v.0 + u.1 * v.1))
            let theta = acos(dotUV)             // angle between segments (0…π)
            // Skip nearly-straight (nothing to round) and hairpin (r/tan(π/2)=∞).
            guard theta > 0.05, theta < .pi - 0.05 else { return nil }
            var d = radius / tan(theta / 2)     // tangent distance from the corner
            // Clamp the radius so both tangents fit inside the segments.
            let maxD = min(lu, lv) * 0.49
            if d > maxD { d = maxD }
            guard d > 1e-6 else { return nil }
            let tA = VectorPoint(x: cur.x - d * u.0, y: cur.y - d * u.1)
            let tB = VectorPoint(x: cur.x + d * v.0, y: cur.y + d * v.1)
            // Center = intersection of the lines through tA ⟂ u and tB ⟂ v.
            let nx = -u.1, ny = u.0
            let mx = -v.1, my = v.0
            let denom = nx * my - ny * mx
            guard abs(denom) > 1e-12 else { return nil }
            let s = ((tB.x - tA.x) * my - (tB.y - tA.y) * mx) / denom
            let cx = tA.x + s * nx
            let cy = tA.y + s * ny
            let rC = ((tA.x - cx) * (tA.x - cx) + (tA.y - cy) * (tA.y - cy)).squareRoot()
            let a0 = atan2(tA.y - cy, tA.x - cx)
            let turn = u.0 * v.1 - u.1 * v.0     // cross(u, v): >0 = left turn
            let sweep = turn >= 0 ? theta : -theta
            let nArc = max(3, min(24, Int(ceil(theta / (.pi / 8))) + 1))
            var arc: [VectorPoint] = []
            for k in 1..<nArc {
                let a = a0 + sweep * Double(k) / Double(nArc)
                arc.append(VectorPoint(x: cx + rC * cos(a), y: cy + rC * sin(a)))
            }
            return [tA] + arc + [tB]
        }

        if closed {
            let loop = Array(points[0..<n])
            var out: [VectorPoint] = []
            for i in 0..<n {
                let prev = loop[(i - 1 + n) % n]
                let cur = loop[i]
                let next = loop[(i + 1) % n]
                if let arc = filletCorner(prev: prev, cur: cur, next: next) {
                    out.append(contentsOf: arc)
                } else {
                    out.append(cur)
                }
            }
            out.append(out[0])   // keep the first==last loop convention
            return out
        } else {
            var out: [VectorPoint] = [points[0]]
            for i in 1..<(n - 1) {
                if let arc = filletCorner(prev: points[i - 1], cur: points[i], next: points[i + 1]) {
                    out.append(contentsOf: arc)
                } else {
                    out.append(points[i])
                }
            }
            out.append(points[n - 1])
            return out
        }
    }
}

/// Extends the open ends of selected vectors by a distance, Aspire-style.
///
/// Lines extend at both ends; open freehand polylines extend their first and
/// last segments in the segment direction. Closed shapes are unchanged.
public enum ShapeExtendEngine {

    public static func extend(_ shape: VectorShape, distance: Double) -> VectorShape {
        guard distance > 1e-9 else { return shape }
        switch shape {
        case .line(let s, let e):
            let ux = e.x - s.x, uy = e.y - s.y
            let l = (ux * ux + uy * uy).squareRoot()
            guard l > 1e-9 else { return shape }
            return .line(
                start: VectorPoint(x: s.x - ux / l * distance, y: s.y - uy / l * distance),
                end: VectorPoint(x: e.x + ux / l * distance, y: e.y + uy / l * distance)
            )
        case .freehand(let pts):
            guard pts.count >= 2, pts.first != pts.last else { return shape }  // open only
            var out = pts
            let f = pts[0], s = pts[1]
            let ux = f.x - s.x, uy = f.y - s.y
            let lu = (ux * ux + uy * uy).squareRoot()
            if lu > 1e-9 {
                out[0] = VectorPoint(x: f.x + ux / lu * distance, y: f.y + uy / lu * distance)
            }
            let last = pts[pts.count - 1], sl = pts[pts.count - 2]
            let vx = last.x - sl.x, vy = last.y - sl.y
            let lv = (vx * vx + vy * vy).squareRoot()
            if lv > 1e-9 {
                out[out.count - 1] = VectorPoint(x: last.x + vx / lv * distance, y: last.y + vy / lv * distance)
            }
            return .freehand(points: out)
        default:
            return shape
        }
    }
}

// MARK: - XCTest compatibility surface

/// The API contract the ShopPilotTests fillet/extend tests were written
/// against: fillet ONE corner at a specific point, and extend a line TO a
/// point. Both return arrays of shapes. Implemented on top of the verified
/// `ShapeFilletEngine` / `ShapeExtendEngine` math.
public enum FilletExtendEngine {

    /// Fillet the corner of `shape` nearest to `cornerPoint` (single corner,
    /// unlike the batch `ShapeFilletEngine.fillet`). Returns the resulting
    /// outline exploded into individual line segments. Shapes with no fillet-
    /// able corner are returned as a single segment list.
    public static func fillet(shape: VectorShape, cornerPoint: VectorPoint, radius: Double) -> [VectorShape] {
        let loop: [VectorPoint]
        switch shape {
        case .freehand(let pts):
            guard pts.count >= 3 else { return [shape] }
            loop = pts
        case .rectangle(let o, let w, let h):
            loop = [
                VectorPoint(x: o.x, y: o.y),
                VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h),
                VectorPoint(x: o.x, y: o.y + h),
                VectorPoint(x: o.x, y: o.y),
            ]
        default:
            return [shape]
        }
        // Nearest REAL vertex to the target corner point.
        let n = loop.first == loop.last ? loop.count - 1 : loop.count
        var best = -1
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0..<n {
            let dx = loop[i].x - cornerPoint.x
            let dy = loop[i].y - cornerPoint.y
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = i }
        }
        guard best >= 0 else { return [shape] }
        let prev = loop[(best - 1 + n) % n]
        let cur = loop[best]
        let next = loop[(best + 1) % n]
        // Single-corner fillet via the verified 3-point window math.
        let window = ShapeFilletEngine.filletPolyline([prev, cur, next], radius: radius)
        guard window.count > 3 else { return [shape] }   // corner wasn't fillet-able
        var out = loop
        let replacement = Array(window[1..<(window.count - 1)])
        if loop.first == loop.last {
            // Closed loop: vertex `best` may be the wrap vertex 0.
            if best == 0 {
                out.replaceSubrange(0...0, with: replacement)
                out[out.count - 1] = out[0]   // keep first == last
            } else {
                out.replaceSubrange(best...best, with: replacement)
            }
        } else {
            out.replaceSubrange(best...best, with: replacement)
        }
        // Explode into line segments (drop the duplicated close point).
        let segCount = out.first == out.last ? out.count - 1 : out.count
        var segments: [VectorShape] = []
        for i in 0..<(segCount - 1) {
            segments.append(.line(start: out[i], end: out[i + 1]))
        }
        if out.first == out.last && segCount >= 2 {
            segments.append(.line(start: out[segCount - 1], end: out[0]))
        }
        return segments
    }

    /// Extend a line so one of its endpoints reaches `point` (the point is
    /// projected onto the line's direction; the end it extends is whichever
    /// side the projection falls beyond). Non-line shapes pass through.
    public static func extendLine(_ line: VectorShape, to point: VectorPoint) -> [VectorShape] {
        guard case .line(let s, let e) = line else { return [line] }
        let ux = e.x - s.x, uy = e.y - s.y
        let l = (ux * ux + uy * uy).squareRoot()
        guard l > 1e-9 else { return [line] }
        let u = (ux / l, uy / l)
        let projEnd = (point.x - s.x) * u.0 + (point.y - s.y) * u.1
        if projEnd > l {
            return [.line(start: s, end: point)]
        } else if projEnd < 0 {
            return [.line(start: point, end: e)]
        }
        return [line]
    }
}
