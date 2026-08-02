import SwiftUI
import ShopPilotGeometry

/// Minimal design canvas: renders vectors, supports pan/zoom, add rectangle, select/move.
struct DesignCanvasView: View {
    @ObservedObject var session: AppSession
    @State private var scale: CGFloat = 2.0
    @State private var offset: CGSize = .zero
    @State private var selectedIndex: Int?
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Design Canvas")
                    .font(.headline)
                Spacer()
                Button("Add Rectangle") { session.addDemoRectangle() }
                Button("Fit") { fitContent() }
                Text("Zoom \(Int(scale * 50))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)

            Divider()

            GeometryReader { geo in
                ZStack {
                    Color(NSColor.textBackgroundColor)

                    // Grid
                    Canvas { context, size in
                        let step: CGFloat = 20 * scale
                        var path = Path()
                        var x: CGFloat = 0
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            x += step
                        }
                        var y: CGFloat = 0
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += step
                        }
                        context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                    }

                    Canvas { context, size in
                        for (idx, shape) in session.shapes.enumerated() {
                            let path = path(for: shape)
                            let selected = selectedIndex == idx
                            context.stroke(
                                path,
                                with: .color(selected ? Color.accentColor : .primary),
                                lineWidth: selected ? 2.5 : 1.5
                            )
                            if selected {
                                context.fill(path, with: .color(Color.accentColor.opacity(0.08)))
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    selectedIndex = hitTest(value.startLocation)
                                }
                                guard let idx = selectedIndex, session.shapes.indices.contains(idx) else {
                                    offset = CGSize(
                                        width: offset.width + value.translation.width * 0.02,
                                        height: offset.height + value.translation.height * 0.02
                                    )
                                    return
                                }
                                let dx = Double(value.translation.width / scale)
                                let dy = Double(-value.translation.height / scale)
                                // Apply incremental translate from last frame via full reset from original — simplify: translate by small delta each event using translation delta
                                _ = dx; _ = dy
                            }
                            .onEnded { value in
                                if let idx = selectedIndex, session.shapes.indices.contains(idx) {
                                    let dx = Double(value.translation.width / scale)
                                    let dy = Double(-value.translation.height / scale)
                                    session.moveShape(at: idx, by: dx, dy: dy)
                                }
                                dragStart = nil
                            }
                    )
                    .gesture(
                        MagnificationGesture().onChanged { value in
                            scale = max(0.3, min(8, value))
                        }
                    )
                }
                .clipped()
                .onAppear { fitContent(in: geo.size) }
            }
        }
    }

    private func path(for shape: VectorShape) -> Path {
        var p = Path()
        let pts = GeometryBridge.toCorePaths([shape]).first?.points ?? []
        guard let first = pts.first else { return p }
        p.move(to: screen(first.x, first.y))
        for pt in pts.dropFirst() {
            p.addLine(to: screen(pt.x, pt.y))
        }
        return p
    }

    private func screen(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * scale + offset.width + 40,
            y: CGFloat(-y) * scale + offset.height + 200
        )
    }

    private func hitTest(_ point: CGPoint) -> Int? {
        for (idx, shape) in session.shapes.enumerated().reversed() {
            let pts = GeometryBridge.toCorePaths([shape]).first?.points ?? []
            for pt in pts {
                let s = screen(pt.x, pt.y)
                if hypot(s.x - point.x, s.y - point.y) < 12 { return idx }
            }
        }
        return nil
    }

    private func fitContent(in size: CGSize = CGSize(width: 600, height: 400)) {
        guard !session.shapes.isEmpty else {
            scale = 2
            offset = .zero
            return
        }
        let rects = session.shapes.map(\.boundingRect)
        let minX = rects.map(\.minX).min() ?? 0
        let maxX = rects.map(\.maxX).max() ?? 100
        let minY = rects.map(\.minY).min() ?? 0
        let maxY = rects.map(\.maxY).max() ?? 100
        let w = max(maxX - minX, 1)
        let h = max(maxY - minY, 1)
        let sx = (size.width - 80) / CGFloat(w)
        let sy = (size.height - 80) / CGFloat(h)
        scale = max(0.3, min(sx, sy, 6))
        offset = CGSize(
            width: size.width / 2 - CGFloat((minX + maxX) / 2) * scale,
            height: size.height / 2 + CGFloat((minY + maxY) / 2) * scale
        )
    }
}
