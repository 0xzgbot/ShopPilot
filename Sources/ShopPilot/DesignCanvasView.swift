import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

/// Canvas create tools (SPK-1120): select/move, rect, circle, line, polyline.
enum CanvasCreateTool: String, CaseIterable, Identifiable {
    case select
    case rect
    case circle
    case line
    case polyline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return "Select"
        case .rect: return "Rect"
        case .circle: return "Circle"
        case .line: return "Line"
        case .polyline: return "Polyline"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rect: return "rectangle"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .polyline: return "beziercurve"
        }
    }

    var hint: String {
        switch self {
        case .select:
            return "Click to select, drag a shape to move, drag empty space to pan"
        case .rect:
            return "Drag corner-to-corner to draw a rectangle"
        case .circle:
            return "Drag from center to rim to draw a circle"
        case .line:
            return "Drag from start to end to draw a line"
        case .polyline:
            return "Click to place vertices; double-click, click the start vertex, or press Finish to commit"
        }
    }
}

/// Design canvas: renders vectors, pan/zoom, and create tools that insert
/// undoable shapes into the session.
struct DesignCanvasView: View {
    @ObservedObject var session: AppSession
    @State private var scale: CGFloat = 2.0
    @State private var scaleBeforePinch: CGFloat = 2.0
    @State private var offset: CGSize = .zero
    @State private var selectedIndex: Int?
    @State private var dragStart: CGPoint?
    /// Active create tool — owned by the session so the left tool palette
    /// and the canvas share it; the canvas only reads it.
    private var tool: CanvasCreateTool { session.designTool }

    // Create-tool draft state (design/model coordinates).
    @State private var draftStart: CGPoint?
    @State private var draftCurrent: CGPoint?
    @State private var polylinePoints: [CGPoint] = []
    @State private var hoverLocation: CGPoint?
    @State private var lastTapTime: Date?

    // SPK-1101b: node-edit mode (drag vertices of a selected polyline).
    @State private var nodeEditMode = false
    @State private var nodeDrag: NodeDrag?
    // SPK-1101c: measure mode (click two points to read the distance).
    @State private var measureMode = false
    @State private var measureA: CGPoint?
    @State private var measureB: CGPoint?

    private let doubleTapWindow: TimeInterval = 0.35

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                ZStack {
                    Color(NSColor.textBackgroundColor)
                    gridLayer
                    keepOutLayer
                    shapesLayer
                    toolpathOverlayLayer
                    draftLayer
                    nodeEditLayer
                    measureLayer
                    hintLayer
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(activeGesture)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // Multiply from the scale captured when the pinch
                            // started — never set absolute scale from the
                            // gesture value (that would reset zoom to ~1×).
                            scale = max(0.3, min(8, scaleBeforePinch * value))
                        }
                        .onEnded { _ in
                            scaleBeforePinch = scale
                        }
                )
                .onContinuousHover { phase in
                    guard tool == .polyline else { return }
                    switch phase {
                    case .active(let loc):
                        hoverLocation = model(loc)
                    case .ended:
                        hoverLocation = nil
                    }
                }
                .onAppear { fitContent(in: geo.size) }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if tool == .polyline, polylinePoints.count >= 2 {
                Button("Finish (\(polylinePoints.count))") { commitPolyline() }
                    .help("Commit the polyline")
            }
            if tool == .polyline, !polylinePoints.isEmpty {
                Button {
                    resetDraft()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Discard in-progress polyline")
            }

            Spacer()

            // SPK-1101b: node-edit toggle — drag vertices of the selected polyline.
            Button {
                toggleNodeEdit()
            } label: {
                Image(systemName: "cursorarrow.click.2")
                    .foregroundStyle(nodeEditMode ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Node edit: drag vertices of the selected polyline")

            // SPK-1101c: measure toggle — click two points to read the distance.
            Button {
                toggleMeasure()
            } label: {
                Image(systemName: "ruler")
                    .foregroundStyle(measureMode ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Measure: click two points to read the distance")

            // UI-polish cluster: visibility chips (Vec / Keep-outs / Toolpaths).
            Divider().frame(height: 14)
            ForEach(0..<CanvasOverlayOptions.chips.count, id: \.self) { i in
                let chip = CanvasOverlayOptions.chips[i]
                let on = session.canvasOverlays.contains(chip.option)
                Button {
                    if on {
                        session.canvasOverlays.subtract(chip.option)
                    } else {
                        session.canvasOverlays.insert(chip.option)
                    }
                    CanvasOverlayStore.save(session.canvasOverlays)
                } label: {
                    Label(chip.label, systemImage: on ? chip.symbol : "circle")
                        .font(.caption)
                        .foregroundStyle(on ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Show/hide \(chip.label.lowercased()) on the canvas")
            }

            Button("Fit") { fitContent() }
            Text("Zoom \(Int(scale * 50))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .onChange(of: session.designTool) { _, _ in resetDraft() }
    }

    // MARK: - Layers

    private var gridLayer: some View {
        Canvas { context, size in
            // SPK-visual — design-anchored grid: lines move with the content
            // (offset + scale), so the sheet reads as a fixed world, and a
            // bold amber origin cross marks the (0,0) datum at any zoom.
            let step: CGFloat = 20 * scale
            guard step > 2 else { return }
            let origin = screen(0, 0)
            var path = Path()
            // Vertical lines.
            var x = origin.x.truncatingRemainder(dividingBy: step)
            if x < 0 { x += step }
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            // Horizontal lines.
            var y = origin.y.truncatingRemainder(dividingBy: step)
            if y < 0 { y += step }
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.gray.opacity(0.14)), lineWidth: 0.5)

            // Origin axes — amber datum cross at world (0,0).
            if origin.x >= -100, origin.x <= size.width + 100,
               origin.y >= -100, origin.y <= size.height + 100 {
                var axes = Path()
                let arm: CGFloat = 400
                axes.move(to: CGPoint(x: origin.x, y: max(0, origin.y - arm)))
                axes.addLine(to: CGPoint(x: origin.x, y: min(size.height, origin.y + arm)))
                axes.move(to: CGPoint(x: max(0, origin.x - arm), y: origin.y))
                axes.addLine(to: CGPoint(x: min(size.width, origin.x + arm), y: origin.y))
                context.stroke(axes, with: .color(SP.Tint.brand.opacity(0.45)), lineWidth: 1)
                // Small datum dot.
                let dot = CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(SP.Tint.brand.opacity(0.7)))
            }
        }
    }

    private var shapesLayer: some View {
        Canvas { context, _ in
            guard session.canvasOverlays.contains(.vectors) else { return }
            // SPK-1137: draw only shapes on visible layers — each layer's own
            // visibility flag, not just the active layer's.
            for idx in session.visibleShapeIndices {
                guard session.shapes.indices.contains(idx) else { continue }
                let path = path(for: session.shapes[idx])
                let selected = session.selectedShapeIndices.contains(idx)
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
    }

    /// UI-polish cluster — keep-out zones overlay, gated by the Keep-outs chip.
    private var keepOutLayer: some View {
        Canvas { context, _ in
            guard session.canvasOverlays.contains(.keepOuts) else { return }
            for zone in session.keepOutZones where zone.isActive {
                var p = Path()
                if let rectMinX = zone.rectMinX, let rectMinY = zone.rectMinY,
                   let rectMaxX = zone.rectMaxX, let rectMaxY = zone.rectMaxY {
                    let a = screen(rectMinX, rectMinY)
                    let b = screen(rectMaxX, rectMaxY)
                    p.addRect(CGRect(
                        x: min(a.x, b.x), y: min(a.y, b.y),
                        width: abs(b.x - a.x), height: abs(b.y - a.y)
                    ))
                } else if let c = zone.circleCenter, let r = zone.circleRadiusMm {
                    let s = screen(c.x, c.y)
                    p.addEllipse(in: CGRect(
                        x: s.x - r * scale, y: s.y - r * scale,
                        width: 2 * r * scale, height: 2 * r * scale
                    ))
                } else if let pts = zone.polygonPoints, pts.count >= 3 {
                    for (i, pt) in pts.enumerated() {
                        let s = screen(pt.x, pt.y)
                        if i == 0 { p.move(to: s) } else { p.addLine(to: s) }
                    }
                    p.closeSubpath()
                }
                context.fill(p, with: .color(Color.red.opacity(0.10)))
                context.stroke(p, with: .color(.red.opacity(0.55)), lineWidth: 1.5)
            }
        }
    }

    /// UI-polish cluster — toolpath wireframe overlay, gated by the Toolpaths
    /// chip. Reuses the same segment parser as the Preview stage.
    private var toolpathOverlayLayer: some View {
        Canvas { context, _ in
            guard session.canvasOverlays.contains(.toolpaths) else { return }
            let segments = WireframeRenderer.generateSegments(from: session.allToolpathGCode)
            for seg in segments {
                var p = Path()
                p.move(to: screen(seg.start.x, seg.start.y))
                p.addLine(to: screen(seg.end.x, seg.end.y))
                context.stroke(
                    p,
                    with: .color(seg.isRapid ? Color.blue.opacity(0.5) : Color.green.opacity(0.7)),
                    lineWidth: seg.isRapid ? 1.0 : 1.5
                )
            }
        }
    }

    @ViewBuilder
    private var draftLayer: some View {
        if let draft = draftShape {
            Canvas { context, _ in
                let path = path(for: draft)
                context.stroke(
                    path,
                    with: .color(Color.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
            }
            .allowsHitTesting(false)
        }
        if !polylinePoints.isEmpty {
            Canvas { context, _ in
                for p in polylinePoints {
                    let s = screen(p.x, p.y)
                    context.fill(
                        Path(ellipseIn: CGRect(x: s.x - 3, y: s.y - 3, width: 6, height: 6)),
                        with: .color(Color.accentColor)
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Node-edit + measure overlays (SPK-1101b / SPK-1101c)

    /// Small draggable handles at every vertex of the selected freehand shapes.
    @ViewBuilder
    private var nodeEditLayer: some View {
        if nodeEditMode {
            Canvas { context, _ in
                for idx in selectedIndices.sorted() {
                    guard session.shapes.indices.contains(idx) else { continue }
                    let pts: [VectorPoint]
                    if let drag = nodeDrag, drag.shapeIndex == idx {
                        pts = drag.points  // live preview while dragging
                    } else if case .freehand(let p) = session.shapes[idx] {
                        pts = p
                    } else {
                        continue
                    }
                    for pt in pts {
                        let s = screen(pt.x, pt.y)
                        let handle = Path(
                            ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)
                        )
                        context.fill(handle, with: .color(Color.accentColor))
                        context.stroke(handle, with: .color(.white), lineWidth: 1.5)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Measure overlay: line + distance label between the two clicked points.
    @ViewBuilder
    private var measureLayer: some View {
        if measureMode, let a = measureA, let b = measureB {
            Canvas { context, _ in
                let sa = screen(a.x, a.y)
                let sb = screen(b.x, b.y)
                var line = Path()
                line.move(to: sa)
                line.addLine(to: sb)
                context.stroke(line, with: .color(Color.accentColor), lineWidth: 1.5)
                let dx = b.x - a.x
                let dy = b.y - a.y
                let dist = sqrt(dx * dx + dy * dy)
                let mid = CGPoint(x: (sa.x + sb.x) / 2, y: (sa.y + sb.y) / 2)
                let text = String(format: "%.1f mm", dist)
                let labelSize = (text as NSString).size(
                    withAttributes: [.font: NSFont.systemFont(ofSize: 11)]
                )
                let pill = CGRect(
                    x: mid.x - labelSize.width / 2 - 4,
                    y: mid.y - labelSize.height / 2 - 2,
                    width: labelSize.width + 8,
                    height: labelSize.height + 4
                )
                context.fill(
                    Path(roundedRect: pill, cornerRadius: 3),
                    with: .color(Color.accentColor.opacity(0.85))
                )
                context.draw(
                    Text(text).font(.system(size: 11)).foregroundColor(.white),
                    at: mid
                )
            }
            .allowsHitTesting(false)
        }
    }

    private var hintLayer: some View {
        VStack {
            Spacer()
            HStack {
                Text(tool.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
            .padding(8)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gestures

    private var activeGesture: AnyGesture<DragGesture.Value> {
        // SPK-1137: lock/hide gating is per-shape (hit-test skips hidden and
        // locked shapes), so pan/zoom always work; no blanket active-layer gate.
        // Measure mode takes over the drag gesture (click-based).
        if measureMode {
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard hypot(value.translation.width, value.translation.height) < 6 else { return }
                        handleMeasureTap(at: value.location)
                    }
            )
        }
        // SPK-1101b: node-edit mode takes over the drag gesture (vertex drags).
        if nodeEditMode {
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(nodeDragChanged)
                    .onEnded(nodeDragEnded)
            )
        }
        switch tool {
        case .select:
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(selectDragChanged)
                    .onEnded(selectDragEnded)
            )
        case .rect, .circle, .line:
            return AnyGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if draftStart == nil { draftStart = model(value.startLocation) }
                        draftCurrent = model(value.location)
                    }
                    .onEnded { _ in commitDragShape() }
            )
        case .polyline:
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard hypot(value.translation.width, value.translation.height) < 6 else { return }
                        handlePolylineTap(at: value.location)
                    }
            )
        }
    }

    private func selectDragChanged(_ value: DragGesture.Value) {
        if dragStart == nil {
            dragStart = value.startLocation
            selectedIndex = hitTest(value.startLocation)
            // Publish to the session so Design ops act on the canvas selection
            // (SPK-1101d). ⌘/⇧-click toggles membership for multi-shape ops
            // (Weld/Subtract/Intersect/Join); plain click replaces; clicking
            // empty space clears.
            let flags = NSEvent.modifierFlags
            let isMulti = flags.contains(.command) || flags.contains(.shift)
            if let idx = selectedIndex {
                if isMulti {
                    session.selectedShapeIndices.formSymmetricDifference([idx])
                } else {
                    // SPK-1203 — smart part selection: a plain click grabs
                    // the whole connected part (touching/overlapping closed
                    // shapes), not just the one shape under the cursor.
                    _ = session.smartSelectPart(containing: idx)
                }
            } else if !isMulti {
                session.selectedShapeIndices = []
            }
        }
        guard let idx = selectedIndex, session.shapes.indices.contains(idx) else {
            offset = CGSize(
                width: offset.width + value.translation.width * 0.02,
                height: offset.height + value.translation.height * 0.02
            )
            return
        }
    }

    private func selectDragEnded(_ value: DragGesture.Value) {
        if let idx = selectedIndex, session.shapes.indices.contains(idx) {
            let dx = Double(value.translation.width / scale)
            let dy = Double(-value.translation.height / scale)
            session.moveShape(at: idx, by: dx, dy: dy)
        }
        dragStart = nil
    }

    // MARK: - Node-edit logic (SPK-1101b)

    /// Indices treated as selected: the session-shared selection plus the
    /// canvas-local selection picked up by the select tool.
    private var selectedIndices: Set<Int> {
        var set = session.selectedShapeIndices
        if let idx = selectedIndex { set.insert(idx) }
        return set
    }

    private func toggleNodeEdit() {
        nodeEditMode.toggle()
        if nodeEditMode {
            measureMode = false
            measureA = nil
            measureB = nil
            nodeDrag = nil
            var vertexCount = 0
            for idx in selectedIndices where session.shapes.indices.contains(idx) {
                if case .freehand(let pts) = session.shapes[idx] {
                    vertexCount += pts.count
                }
            }
            session.statusMessage = "Node edit: \(vertexCount) vertices"
        } else {
            nodeDrag = nil
        }
    }

    /// Grab a vertex handle at the given screen point (12 pt hit radius).
    /// Shapes on locked (or hidden) layers are skipped — node-edit is an edit
    /// (SPK-1137).
    private func hitTestVertex(_ point: CGPoint) -> NodeDrag? {
        for idx in selectedIndices.sorted().reversed()
        where session.shapes.indices.contains(idx) {
            guard session.isShapeVisible(at: idx), session.isShapeEditable(at: idx) else { continue }
            guard case .freehand(let pts) = session.shapes[idx] else { continue }
            for (vi, pt) in pts.enumerated() {
                let s = screen(pt.x, pt.y)
                if hypot(s.x - point.x, s.y - point.y) < 12 {
                    return NodeDrag(shapeIndex: idx, vertexIndex: vi, points: pts)
                }
            }
        }
        return nil
    }

    private func nodeDragChanged(_ value: DragGesture.Value) {
        if nodeDrag == nil {
            guard let hit = hitTestVertex(value.startLocation) else { return }
            nodeDrag = hit
            selectedIndex = hit.shapeIndex
            session.selectedShapeIndices = [hit.shapeIndex]
        }
        guard var drag = nodeDrag, drag.points.indices.contains(drag.vertexIndex) else { return }
        let p = model(value.location)
        drag.points[drag.vertexIndex] = VectorPoint(x: p.x, y: p.y)
        nodeDrag = drag
    }

    private func nodeDragEnded(_ value: DragGesture.Value) {
        guard let drag = nodeDrag else { return }
        nodeDrag = nil
        guard session.shapes.indices.contains(drag.shapeIndex) else { return }
        // Commit once per drag (same pattern as moveShape) so the undo stack
        // records a single entry; updateShape registers the undo point + dirty.
        session.updateShape(at: drag.shapeIndex, with: .freehand(points: drag.points))
    }

    // MARK: - Measure logic (SPK-1101c)

    private func toggleMeasure() {
        measureMode.toggle()
        if measureMode {
            nodeEditMode = false
            nodeDrag = nil
            measureA = nil
            measureB = nil
            session.statusMessage = "Measure: click the first point"
        } else {
            measureA = nil
            measureB = nil
        }
    }

    private func handleMeasureTap(at screenPoint: CGPoint) {
        let p = model(screenPoint)
        if measureB != nil {
            // Start a fresh measurement; the old overlay is cleared.
            measureA = p
            measureB = nil
            session.statusMessage = "Measure: click the second point"
        } else if measureA == nil {
            measureA = p
            session.statusMessage = "Measure: click the second point"
        } else if let a = measureA {
            measureB = p
            let dx = p.x - a.x
            let dy = p.y - a.y
            let dist = sqrt(dx * dx + dy * dy)
            session.statusMessage = String(format: "Distance: %.1f mm", dist)
        }
    }

    // MARK: - Create-tool logic

    /// The shape being drawn right now (live preview), in model coordinates.
    private var draftShape: VectorShape? {
        if let start = draftStart {
            guard let current = draftCurrent else { return nil }
            switch tool {
            case .rect: return CreateShapes.rect(from: vp(start), to: vp(current))
            case .circle: return CreateShapes.circle(center: vp(start), through: vp(current))
            case .line: return CreateShapes.line(from: vp(start), to: vp(current))
            default: return nil
            }
        }
        if tool == .polyline {
            var pts = polylinePoints.map(vp)
            if let hover = hoverLocation, !pts.isEmpty, pts.count < 500 {
                pts.append(vp(hover))  // rubber-band to the cursor
            }
            if pts.count >= 2 { return CreateShapes.polyline(pts) }
        }
        return nil
    }

    private func handlePolylineTap(at screenPoint: CGPoint) {
        let point = model(screenPoint)
        // Clicking near the first vertex closes the loop and commits.
        if let first = polylinePoints.first,
           hypot(point.x - first.x, point.y - first.y) < 10 / scale {
            polylinePoints.append(first)
            commitPolyline()
            return
        }
        // Double-click commits, using the second click as the last vertex.
        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) < doubleTapWindow {
            polylinePoints.append(point)
            lastTapTime = nil
            commitPolyline()
            return
        }
        lastTapTime = now
        polylinePoints.append(point)
    }

    private func commitDragShape() {
        guard let start = draftStart, let current = draftCurrent, start != current else {
            resetDraft()
            return
        }
        let shape: VectorShape
        switch tool {
        case .rect: shape = CreateShapes.rect(from: vp(start), to: vp(current))
        case .circle: shape = CreateShapes.circle(center: vp(start), through: vp(current))
        default: shape = CreateShapes.line(from: vp(start), to: vp(current))
        }
        session.addShapes([shape])
        resetDraft()
    }

    private func commitPolyline() {
        let pts = polylinePoints.map(vp)
        guard pts.count >= 2 else {
            resetDraft()
            return
        }
        session.addShapes([CreateShapes.polyline(pts)])
        resetDraft()
    }

    private func resetDraft() {
        draftStart = nil
        draftCurrent = nil
        polylinePoints = []
        hoverLocation = nil
        lastTapTime = nil
    }

    // MARK: - Coordinate mapping

    private func vp(_ p: CGPoint) -> VectorPoint {
        VectorPoint(x: p.x, y: p.y)
    }

    private func model(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - offset.width - 40) / scale,
            y: -(p.y - offset.height - 200) / scale
        )
    }

    private func screen(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * scale + offset.width + 40,
            y: CGFloat(-y) * scale + offset.height + 200
        )
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

    private func hitTest(_ point: CGPoint) -> Int? {
        // SPK-1137: shapes on hidden or locked layers are not selectable.
        for (idx, shape) in session.shapes.enumerated().reversed() {
            guard session.isShapeVisible(at: idx), session.isShapeEditable(at: idx) else { continue }
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
            scaleBeforePinch = 2
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
        scaleBeforePinch = scale
        offset = CGSize(
            width: size.width / 2 - CGFloat((minX + maxX) / 2) * scale,
            height: size.height / 2 + CGFloat((minY + maxY) / 2) * scale
        )
    }
}

/// In-flight vertex drag for node-edit mode (SPK-1101b): which vertex of which
/// shape is being dragged, plus the working copy of the point list so the
/// overlay can preview live before `session.updateShape` commits on drag end.
private struct NodeDrag {
    let shapeIndex: Int
    let vertexIndex: Int
    var points: [VectorPoint]
}
