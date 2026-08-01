import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// Converts geometry-kernel shapes into Core `VectorPath`s for toolpath engines.
enum GeometryBridge {
    static func toCorePaths(_ shapes: [ShopPilotGeometry.VectorShape]) -> [ShopPilotCore.VectorPath] {
        shapes.enumerated().compactMap { index, shape in
            let pts = samplePoints(shape)
            guard pts.count >= 2 else { return nil }
            let closed: Bool
            switch shape {
            case .line, .arc:
                closed = false
            default:
                closed = true
            }
            return VectorPath(
                name: "Shape \(index + 1)",
                points: pts,
                isClosed: closed
            )
        }
    }

    private static func samplePoints(_ shape: ShopPilotGeometry.VectorShape) -> [ShopPilotCore.VectorPoint] {
        switch shape {
        case .line(let s, let e):
            return [core(s), core(e)]
        case .rectangle(let o, let w, let h):
            let p0 = core(o)
            return [
                p0,
                ShopPilotCore.VectorPoint(x: o.x + w, y: o.y),
                ShopPilotCore.VectorPoint(x: o.x + w, y: o.y + h),
                ShopPilotCore.VectorPoint(x: o.x, y: o.y + h),
                p0,
            ]
        case .circle(let c, let r):
            return circlePoints(center: c, radius: r, count: 48)
        case .ellipse(let c, let rx, let ry, let rotation):
            return ellipsePoints(center: c, rx: rx, ry: ry, rotation: rotation, count: 48)
        case .polygon(let c, let r, let sides, let rotation):
            return regularPolygon(center: c, radius: r, sides: max(3, sides), rotation: rotation)
        case .star(let c, let outer, let inner, let points, let rotation):
            return starPoints(center: c, outer: outer, inner: inner, points: max(3, points), rotation: rotation)
        case .arc(let c, let r, let sa, let ea):
            return arcPoints(center: c, radius: r, start: sa, end: ea, count: 24)
        case .freehand(let points):
            return points.map(core)
        }
    }

    private static func core(_ p: ShopPilotGeometry.VectorPoint) -> ShopPilotCore.VectorPoint {
        ShopPilotCore.VectorPoint(x: p.x, y: p.y)
    }

    private static func circlePoints(
        center: ShopPilotGeometry.VectorPoint,
        radius: Double,
        count: Int
    ) -> [ShopPilotCore.VectorPoint] {
        (0...count).map { i in
            let t = Double(i) / Double(count) * 2 * .pi
            return ShopPilotCore.VectorPoint(
                x: center.x + radius * cos(t),
                y: center.y + radius * sin(t)
            )
        }
    }

    private static func ellipsePoints(
        center: ShopPilotGeometry.VectorPoint,
        rx: Double,
        ry: Double,
        rotation: Double,
        count: Int
    ) -> [ShopPilotCore.VectorPoint] {
        (0...count).map { i in
            let t = Double(i) / Double(count) * 2 * .pi
            let lx = rx * cos(t)
            let ly = ry * sin(t)
            let x = center.x + lx * cos(rotation) - ly * sin(rotation)
            let y = center.y + lx * sin(rotation) + ly * cos(rotation)
            return ShopPilotCore.VectorPoint(x: x, y: y)
        }
    }

    private static func regularPolygon(
        center: ShopPilotGeometry.VectorPoint,
        radius: Double,
        sides: Int,
        rotation: Double
    ) -> [ShopPilotCore.VectorPoint] {
        var pts: [ShopPilotCore.VectorPoint] = (0..<sides).map { i in
            let t = rotation + Double(i) / Double(sides) * 2 * .pi
            return ShopPilotCore.VectorPoint(
                x: center.x + radius * cos(t),
                y: center.y + radius * sin(t)
            )
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    private static func starPoints(
        center: ShopPilotGeometry.VectorPoint,
        outer: Double,
        inner: Double,
        points: Int,
        rotation: Double
    ) -> [ShopPilotCore.VectorPoint] {
        var pts: [ShopPilotCore.VectorPoint] = []
        for i in 0..<(points * 2) {
            let t = rotation + Double(i) / Double(points * 2) * 2 * .pi
            let r = i.isMultiple(of: 2) ? outer : inner
            pts.append(ShopPilotCore.VectorPoint(
                x: center.x + r * cos(t),
                y: center.y + r * sin(t)
            ))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    private static func arcPoints(
        center: ShopPilotGeometry.VectorPoint,
        radius: Double,
        start: Double,
        end: Double,
        count: Int
    ) -> [ShopPilotCore.VectorPoint] {
        let sweep = end - start
        return (0...count).map { i in
            let t = start + sweep * Double(i) / Double(count)
            return ShopPilotCore.VectorPoint(
                x: center.x + radius * cos(t),
                y: center.y + radius * sin(t)
            )
        }
    }
}
