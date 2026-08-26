import Foundation
import CoreGraphics
import ShopPilotCore

// MARK: - Design PDF export (SPK-1322)

/// Exports the design vectors as a real PDF document (vector strokes, not a
/// bitmap) so users can share or print their designs — professional CAD
/// exports PDF; ShopPilot previously only produced job-sheet PDFs.
///
/// Every `VectorShape` case is stroked as a Core Graphics path: lines and
/// arcs are open paths, rectangles/circles/ellipses/polygons/stars are closed
/// paths, and freehand polylines close only when their vertex list closes on
/// itself (matching `VectorShape.isClosedShape` and the app canvas).
public enum DesignPDFExporter {

    /// Render the design to a PDF document in memory.
    ///
    /// - Parameters:
    ///   - shapes: the design vectors, in millimetres, design space Y-up.
    ///   - pageSizeMm: output page size in millimetres (A4 landscape default).
    ///   - marginMm: margin from the page edge to the design origin, mm.
    ///   - lineWidth: stroke width in design millimetres (0.5 = hairline).
    /// - Returns: the PDF `Data` (starts with `%PDF`), or `nil` on any failure.
    ///
    /// Coordinate transform: design mm → PDF points at 72/inch, anchored at
    /// the bottom-left margin. PDF user space is Y-up (origin bottom-left),
    /// which matches the design's Y-up space, so the design renders upright on
    /// the page without an inversion — unlike the app canvas (SwiftUI is
    /// Y-down, which is why `DesignCanvasView.screen(_:_:)` negates Y there).
    /// Content outside the page is clipped by the PDF context, never crashes.
    public static func renderShapes(
        _ shapes: [VectorShape],
        pageSizeMm: (width: Double, height: Double) = (297, 210),
        marginMm: Double = 10,
        lineWidth: Double = 0.5
    ) -> Data? {
        let pointsPerMm = 72.0 / 25.4
        let pageWidthPt = pageSizeMm.width * pointsPerMm
        let pageHeightPt = pageSizeMm.height * pointsPerMm
        guard pageWidthPt > 0, pageHeightPt > 0,
              pageWidthPt.isFinite, pageHeightPt.isFinite,
              marginMm.isFinite, marginMm >= 0,
              lineWidth.isFinite, lineWidth >= 0 else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidthPt, height: pageHeightPt)
        guard let pdfData = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let consumer = CGDataConsumer(data: pdfData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        // Begin the page's content stream — without it, Quartz drops all
        // drawing ("No content stream. ... call CGPDFContextBeginPage first").
        ctx.beginPDFPage(nil)

        // White page background, in page space before the CTM changes.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(mediaBox)

        // Design mm → PDF points (72/inch). PDF user space is Y-up, so the
        // design's Y-up coordinates map directly; see doc comment above.
        ctx.translateBy(x: marginMm * pointsPerMm, y: marginMm * pointsPerMm)
        ctx.scaleBy(x: pointsPerMm, y: pointsPerMm)

        ctx.setLineWidth(lineWidth)          // in design mm (post-CTM units)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for shape in shapes {
            addPath(for: shape, to: ctx)
            ctx.strokePath()
        }

        ctx.closePDF()
        return pdfData as Data
    }

    /// Render the design to PDF and write it to `url`. Returns `false` on any
    /// failure (including an unwritable path) — never crashes.
    public static func export(
        _ shapes: [VectorShape],
        to url: URL,
        pageSizeMm: (width: Double, height: Double) = (297, 210),
        marginMm: Double = 10
    ) -> Bool {
        guard let data = renderShapes(shapes, pageSizeMm: pageSizeMm, marginMm: marginMm) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Path construction

    private static func addPath(for shape: VectorShape, to ctx: CGContext) {
        switch shape {
        case .line(let s, let e):
            ctx.move(to: CGPoint(x: s.x, y: s.y))
            ctx.addLine(to: CGPoint(x: e.x, y: e.y))

        case .rectangle(let o, let w, let h):
            ctx.addRect(CGRect(x: o.x, y: o.y, width: w, height: h))

        case .circle(let c, let r):
            guard r > 0 else { return }
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

        case .arc(let c, let r, let startAngle, let endAngle):
            guard r > 0 else { return }
            // Design arcs sweep from startAngle toward endAngle with increasing
            // angle (Kernel contains() semantics); clockwise: false = CCW in the
            // Y-up user space. Quartz adds 2π when endAngle < startAngle, so
            // arcs crossing the 0/2π boundary render through 0° correctly.
            ctx.move(to: CGPoint(
                x: c.x + r * cos(startAngle),
                y: c.y + r * sin(startAngle)
            ))
            ctx.addArc(
                center: CGPoint(x: c.x, y: c.y),
                radius: r,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )

        case .ellipse(let c, let rx, let ry, let rotation):
            guard rx > 0, ry > 0 else { return }
            // Sampled closed polyline (same 48-segment convention as the app
            // canvas via GeometryBridge.toCorePaths).
            addPolyline(
                sampledEllipse(center: c, rx: rx, ry: ry, rotation: rotation, count: 48),
                closed: true,
                to: ctx
            )

        case .polygon(let c, let r, let sides, let rotation):
            guard sides >= 3, r > 0 else { return }
            addPolyline(
                regularPolygon(center: c, radius: r, sides: sides, rotation: rotation),
                closed: true,
                to: ctx
            )

        case .star(let c, let outerRadius, let innerRadius, let points, let rotation):
            guard points >= 3, outerRadius > 0, innerRadius > 0 else { return }
            addPolyline(
                sampledStar(center: c, outer: outerRadius, inner: innerRadius, points: points, rotation: rotation),
                closed: true,
                to: ctx
            )

        case .freehand(let pts):
            let closed = pts.count >= 3 && pts.first == pts.last
            addPolyline(pts, closed: closed, to: ctx)
        }
    }

    private static func addPolyline(_ pts: [VectorPoint], closed: Bool, to ctx: CGContext) {
        guard pts.count >= 2 else { return }
        ctx.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for p in pts.dropFirst() {
            ctx.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        if closed, let first = pts.first, pts.last != first {
            ctx.addLine(to: CGPoint(x: first.x, y: first.y))
        }
    }

    // MARK: - Sampling (matches GeometryBridge conventions)

    private static func sampledEllipse(
        center: VectorPoint,
        rx: Double,
        ry: Double,
        rotation: Double,
        count: Int
    ) -> [VectorPoint] {
        (0...count).map { i in
            let t = Double(i) / Double(count) * 2 * .pi
            let lx = rx * cos(t)
            let ly = ry * sin(t)
            return VectorPoint(
                x: center.x + lx * cos(rotation) - ly * sin(rotation),
                y: center.y + lx * sin(rotation) + ly * cos(rotation)
            )
        }
    }

    private static func regularPolygon(
        center: VectorPoint,
        radius: Double,
        sides: Int,
        rotation: Double
    ) -> [VectorPoint] {
        var pts: [VectorPoint] = (0..<sides).map { i in
            let t = rotation + Double(i) / Double(sides) * 2 * .pi
            return VectorPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    private static func sampledStar(
        center: VectorPoint,
        outer: Double,
        inner: Double,
        points: Int,
        rotation: Double
    ) -> [VectorPoint] {
        var pts: [VectorPoint] = []
        for i in 0..<(points * 2) {
            let t = rotation + Double(i) / Double(points * 2) * 2 * .pi
            let r = i.isMultiple(of: 2) ? outer : inner
            pts.append(VectorPoint(x: center.x + r * cos(t), y: center.y + r * sin(t)))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }
}
