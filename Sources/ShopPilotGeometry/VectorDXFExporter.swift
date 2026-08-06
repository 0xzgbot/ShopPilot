import Foundation
import ShopPilotCore

// MARK: - DXF export (D24 lean slice)

/// Exports the design vectors as ASCII DXF R12 (mm). LINE, CIRCLE and ARC
/// map to native entities; every other shape (rect, polygon, star, ellipse,
/// freehand) is sampled to a closed POLYLINE (VERTEX/SEQEND). Files round-trip
/// through the ShopPilot DXF importer and standard CAD tools.
public enum VectorDXFExporter {

    /// ASCII DXF R12 text for a set of shapes. Layer 0; mm units (R12 has no
    /// unit declaration — document as mm).
    public static func dxfString(from shapes: [VectorShape]) -> String {
        var out = "0\nSECTION\n  2\nENTITIES\n"
        for shape in shapes {
            out += entityText(for: shape)
        }
        out += "  0\nENDSEC\n  0\nEOF\n"
        return out
    }

    private static func entityText(for shape: VectorShape) -> String {
        switch shape {
        case .line(let s, let e):
            return """
            0\nLINE\n  8\n0\n 10\n\(fmt(s.x))\n 20\n\(fmt(s.y))\n 30\n0.0\n 11\n\(fmt(e.x))\n 21\n\(fmt(e.y))\n 31\n0.0\n
            """
        case .circle(let c, let r):
            return """
            0\nCIRCLE\n  8\n0\n 10\n\(fmt(c.x))\n 20\n\(fmt(c.y))\n 30\n0.0\n 40\n\(fmt(r))\n
            """
        case .arc(let c, let r, let sa, let ea):
            return """
            0\nARC\n  8\n0\n 10\n\(fmt(c.x))\n 20\n\(fmt(c.y))\n 30\n0.0\n 40\n\(fmt(r))\n 50\n\(fmt(sa * 180 / .pi))\n 51\n\(fmt(ea * 180 / .pi))\n
            """
        case .rectangle(let o, let w, let h):
            let corners = [
                VectorPoint(x: o.x, y: o.y),
                VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h),
                VectorPoint(x: o.x, y: o.y + h),
            ]
            return polylineText(corners, closed: true)
        case .freehand(let pts):
            let closed = pts.count >= 3 && pts.first == pts.last
            return polylineText(closed ? Array(pts.dropLast()) : pts, closed: closed)
        case .ellipse(let c, let rx, let ry, let rot):
            return polylineText(sampledEllipse(center: c, rx: rx, ry: ry, rotation: rot), closed: true)
        case .polygon(let c, let r, let sides, let rot):
            return polylineText(sampledRegular(center: c, radius: r, sides: sides, rotation: rot), closed: true)
        case .star(let c, let or, let ir, let points, let rot):
            return polylineText(sampledStar(center: c, outer: or, inner: ir, points: points, rotation: rot), closed: true)
        }
    }

    private static func polylineText(_ pts: [VectorPoint], closed: Bool) -> String {
        var out = "0\nLWPOLYLINE\n  8\n0\n 90\n\(pts.count)\n 70\n\(closed ? "1" : "0")\n"
        for p in pts {
            out += " 10\n\(fmt(p.x))\n 20\n\(fmt(p.y))\n"
        }
        return out
    }

    private static func sampledEllipse(center: VectorPoint, rx: Double, ry: Double, rotation: Double) -> [VectorPoint] {
        let steps = 64
        let cosR = cos(rotation), sinR = sin(rotation)
        return (0..<steps).map { i in
            let a = 2 * .pi * Double(i) / Double(steps)
            let ex = rx * cos(a), ey = ry * sin(a)
            return VectorPoint(
                x: center.x + ex * cosR - ey * sinR,
                y: center.y + ex * sinR + ey * cosR
            )
        }
    }

    private static func sampledRegular(center: VectorPoint, radius: Double, sides: Int, rotation: Double) -> [VectorPoint] {
        guard sides >= 3 else { return [] }
        return (0..<sides).map { i in
            let a = rotation + 2 * .pi * Double(i) / Double(sides)
            return VectorPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
    }

    private static func sampledStar(center: VectorPoint, outer: Double, inner: Double, points: Int, rotation: Double) -> [VectorPoint] {
        guard points >= 2 else { return [] }
        var pts: [VectorPoint] = []
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = rotation + .pi * Double(i) / Double(points)
            pts.append(VectorPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)))
        }
        return pts
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
