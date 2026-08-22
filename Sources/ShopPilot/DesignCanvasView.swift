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
            return "Click to select, drag a shape to move, drag empty space to marquee-select, hold Space to pan"
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
    @State private var lastCanvasSize: CGSize = CGSize(width: 600, height: 400)
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

    /// SPK-1900b — when true, a plain canvas click rapids the machine to that
    /// model-space point (only fires when the machine is connected + idle).
    @State private var jogToMachineMode = false
    @State private var measureA: CGPoint?
    @State private var measureB: CGPoint?

    // SPK-1800a: snap toggle state — persists via @AppStorage.
    @AppStorage("shop_pilot_canvas_snap") private var snapToGridOn: Bool = false

    // SPK-1800b: marquee select state.
    @State private var isMarqueeDragging = false
    @State private var marqueeStart: CGPoint?
    @State private var marqueeEnd: CGPoint?
    // SPK-1800b: Space key tracker for Space+drag pan.
    @State private var spaceKeyDown = false
    // SPK-1800c: cursor location for DRO.
    @State private var cursorLocation: CGPoint?
    // SPK-1800d: canvas datum mode — "corner" or "center".
    @State private var canvasOriginMode: String = "corner"

    private let doubleTapWindow: TimeInterval = 0.35

    /// Extra translation baked into `screen`/`model` (legacy canvas padding).
    /// Fit MUST subtract these or the job sits in a corner.
    private let screenPadX: CGFloat = 40
    private let screenPadY: CGFloat = 200
    /// World-coordinate grid step shared by `gridLayer` and the snap helper
    /// (20 world units). Create tools and select-move snap to these intersections.
    private let canvasGridStep: CGFloat = 20

    /// SPK-1800a: instance wrapper around the pure snap helper.
    private func snapToGrid(_ p: CGPoint) -> CGPoint {
        CanvasSnap.snap(p, gridStep: canvasGridStep, on: snapToGridOn)
    }

    /// SPK-1800a: snap math — pure helper so the CLT can test it without SwiftUI.
    enum CanvasSnap {
        /// Round a world-coordinate point to the nearest grid intersection.
        /// When `on` is false, returns `p` unchanged.
        static func snap(_ p: CGPoint, gridStep: CGFloat, on: Bool) -> CGPoint {
            guard on else { return p }
            return CGPoint(
                x: round(p.x / gridStep) * gridStep,
                y: round(p.y / gridStep) * gridStep
            )
        }
    }

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
                    marqueeLayer
                    draftLayer
                    nodeEditLayer
                    measureLayer
                    cursorDROLayer
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
                .onKeyPress(.space) {
                    // SPK-1800b: toggle Space-pan mode (sticky — press once to
                    // pan on, press again to pan off; avoids key-up tracking).
                    spaceKeyDown.toggle()
                    return .ignored
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        // SPK-1800c: cursor DRO tracks hover for all tools.
                        if tool == .polyline {
                            hoverLocation = model(loc)
                        }
                        cursorLocation = model(loc)
                    case .ended:
                        hoverLocation = nil
                        cursorLocation = nil
                    }
                }
                .onAppear {
                    lastCanvasSize = geo.size
                    fitContent(in: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    lastCanvasSize = newSize
                    fitContent(in: newSize)
                }
                .onChange(of: session.shapes.count) { _, _ in
                    fitContent(in: geo.size)
                }
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

            // SPK-1800a: snap toggle — snap create/move to grid intersections.
            Button {
                snapToGridOn.toggle()
            } label: {
                Image(systemName: snapToGridOn ? "grid.circle.fill" : "grid.circle")
                    .foregroundStyle(snapToGridOn ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Snap to grid")
            .help(snapToGridOn ? "Snap: ON — shapes snap to grid" : "Snap: OFF — free placement")

            // SPK-1800d: sheet origin datum — corner vs center.
            // Design origin is the sheet drawing datum; Machine work zero / mPos / G54
            // live on the Machine stage and are not changed by this control.
            Divider().frame(height: 14)
            Text("Origin:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Canvas Origin", selection: $canvasOriginMode) {
                Text("Corner").tag("corner")
                    .help("Design origin at sheet corner (world 0,0)")
                Text("Center").tag("center")
                    .help("Design origin at sheet center")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .accessibilityLabel("Canvas origin")

            // SPK-1900f: pack selected (or all) vectors onto the sheet.
            Button {
                session.nestShapesOnSheet()
            } label: {
                Image(systemName: "rectangle.split.3x1")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Nest shapes")
            .accessibilityAddTraits(.isButton)
            .disabled(session.shapes.isEmpty)
            .help("Nest selection on the sheet (all shapes if nothing selected)")

            // SPK-1900b: click-to-jog mode + frame job bounds. Both only move
            // when the machine is connected AND idle; the buttons reflect that.
            Button {
                jogToMachineMode.toggle()
                if !jogToMachineMode { measureMode = false }
            } label: {
                Image(systemName: "arrow.uturn.down.circle")
                    .foregroundStyle(jogToMachineMode ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Jog-to mode")
            .accessibilityAddTraits(.isButton)
            .help("Click the canvas to rapid the machine there (connected + idle only)")

            Button {
                let sheet = session.activeSheet
                session.machine.frameJob(widthMm: sheet?.width ?? 0, heightMm: sheet?.depth ?? 0)
            } label: {
                Image(systemName: "rectangle.dashed")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Frame job")
            .accessibilityAddTraits(.isButton)
            .disabled(!(session.machine.canSendMotion))
            .help("Trace the job bounds in air at a safe height (connected + idle only)")

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

            Button("Fit") { fitContent(in: lastCanvasSize) }
            Text("Zoom \(Int(scale * 50))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .onChange(of: session.designTool) { _, _ in resetDraft() }
        .onChange(of: canvasOriginMode) { _, newMode in
            session.updateCanvasOrigin(newMode)
        }
        .onChange(of: session.activeSheetID) { _, _ in
            // SPK-1800d: load persisted datum mode from the job.
            if let mode = session.job.canvasOriginRaw {
                canvasOriginMode = mode
            }
        }
    }

    // MARK: - Layers

    private var gridLayer: some View {
        Canvas { context, size in
            // SPK-visual — design-anchored grid: lines move with the content
            // (offset + scale), so the sheet reads as a fixed world, and a
            // bold amber origin cross marks the (0,0) datum at any zoom.
            // SPK-1800d: sheet center for center-origin mode.
            let sheetCenterX = (session.activeSheet?.width ?? 0) / 2
            let sheetCenterY = (session.activeSheet?.depth ?? 0) / 2
            let useCenter = session.job.canvasOriginRaw == "center"
            let originX = useCenter ? sheetCenterX : 0
            let originY = useCenter ? sheetCenterY : 0

            let step: CGFloat = 20 * scale
            guard step > 2 else { return }
            let origin = screen(originX, originY)
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
    /// SPK-1800f: parse lead-in / lead-out segments from Profile G-code.
    /// Lead-in: first G1 cut move after the plunge in each pass.
    /// Lead-out: last G1 cut move before the rapid to safe Z.
    private func parseLeadSegments(from gcode: [String]) -> (leadIns: [(CGPoint, CGPoint)], leadOuts: [(CGPoint, CGPoint)]) {
        var leadIns: [(CGPoint, CGPoint)] = []
        var leadOuts: [(CGPoint, CGPoint)] = []
        var i = 0
        while i < gcode.count {
            let line = gcode[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("(Pass") {
                let passStart = i + 1
                var plungeIdx = -1
                var firstCutIdx = -1
                var lastCutIdx = -1
                for j in passStart..<gcode.count {
                    let l = gcode[j].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("(Pass") && j > passStart { break }
                    if plungeIdx < 0 && l.hasPrefix("G1 Z") { plungeIdx = j }
                    if plungeIdx >= 0 && firstCutIdx < 0 && l.hasPrefix("G1 X") { firstCutIdx = j }
                    if l.hasPrefix("G1 X") { lastCutIdx = j }
                }
                if firstCutIdx > plungeIdx && plungeIdx >= 0 {
                    var leadInStart: CGPoint?
                    if plungeIdx > 0 {
                        let rapidLine = gcode[plungeIdx - 1].trimmingCharacters(in: .whitespaces)
                        if rapidLine.hasPrefix("G0 X"), let p = WireframeRenderer.parseXY(from: rapidLine, previousX: nil, previousY: nil) {
                            leadInStart = CGPoint(x: p.x, y: p.y)
                        }
                    }
                    let cutLine = gcode[firstCutIdx].trimmingCharacters(in: .whitespaces)
                    if let cutPoint = WireframeRenderer.parseXY(from: cutLine, previousX: nil, previousY: nil), let start = leadInStart {
                        leadIns.append((start, CGPoint(x: cutPoint.x, y: cutPoint.y)))
                    }
                }
                if lastCutIdx >= 0 {
                    let cutLine = gcode[lastCutIdx].trimmingCharacters(in: .whitespaces)
                    if let cutPoint = WireframeRenderer.parseXY(from: cutLine, previousX: nil, previousY: nil) {
                        leadOuts.append((CGPoint(x: cutPoint.x, y: cutPoint.y), CGPoint(x: cutPoint.x + 5, y: cutPoint.y)))
                    }
                }
            }
            i += 1
        }
        return (leadIns, leadOuts)
    }

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

            // SPK-1800f: draw lead-in / lead-out segments (distinct stroke).
            let (leadIns, leadOuts) = parseLeadSegments(from: session.allToolpathGCode)
            for (start, end) in leadIns {
                var p = Path()
                p.move(to: screen(start.x, start.y))
                p.addLine(to: screen(end.x, end.y))
                context.stroke(p, with: .color(Color.orange.opacity(0.8)), lineWidth: 2.0)
            }
            for (start, end) in leadOuts {
                var p = Path()
                p.move(to: screen(start.x, start.y))
                p.addLine(to: screen(end.x, end.y))
                context.stroke(p, with: .color(Color.purple.opacity(0.8)), lineWidth: 2.0)
            }
        }
    }

    /// SPK-1800b: rubber-band marquee rectangle while marquee-selecting.
    @ViewBuilder
    private var marqueeLayer: some View {
        if isMarqueeDragging, let start = marqueeStart, let end = marqueeEnd {
            Canvas { context, _ in
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.1)))
                context.stroke(Path(rect), with: .color(Color.accentColor), lineWidth: 1.5)
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

    /// SPK-1800c: cursor DRO overlay — live X/Y in sheet mm while hovering.
    @ViewBuilder
    private var cursorDROLayer: some View {
        if let loc = cursorLocation {
            VStack {
                HStack {
                    Spacer()
                    Text(String(format: "X %.1f  Y %.1f", loc.x, loc.y))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel(String(format: "Cursor X %.1f Y %.1f", loc.x, loc.y))
                }
                Spacer()
            }
            .padding(8)
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
        // SPK-1900b: jog-to mode takes over plain clicks — rapid the machine
        // to the clicked model-space point (controller gates on connected+idle).
        if jogToMachineMode {
            return AnyGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard hypot(value.translation.width, value.translation.height) < 6 else { return }
                        let p = model(value.location)
                        session.machine.jogTo(xMm: Double(p.x), yMm: Double(p.y))
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
                    .onChanged { value in handleSelectDrag(value) }
                    .onEnded { value in handleSelectEnd(value) }
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

    /// SPK-1800b: select gesture — drag on a shape moves it, drag on empty
    /// canvas marquee-selects, Space+drag (or middle-button) pans.
    private func handleSelectDrag(_ value: DragGesture.Value) {
        if dragStart == nil {
            dragStart = value.startLocation
            selectedIndex = hitTest(value.startLocation)
            marqueeStart = nil
            marqueeEnd = nil
            isMarqueeDragging = false

            let flags = NSEvent.modifierFlags
            let isMulti = flags.contains(.command) || flags.contains(.shift)
            if let idx = selectedIndex {
                if isMulti {
                    session.selectedShapeIndices.formSymmetricDifference([idx])
                } else {
                    _ = session.smartSelectPart(containing: idx)
                }
            } else if !isMulti {
                session.selectedShapeIndices = []
            }
        }
        guard let idx = selectedIndex, session.shapes.indices.contains(idx) else {
            // Drag on empty canvas → marquee or pan.
            // Middle button (== otherMouse / button 2) or Space pans.
            let isPan = spaceKeyDown || NSEvent.pressedMouseButtons == 4
            if isPan {
                isMarqueeDragging = false
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
            } else {
                // SPK-1800b: rubber-band marquee.
                isMarqueeDragging = true
                if marqueeStart == nil { marqueeStart = value.startLocation }
                marqueeEnd = value.location
            }
            return
        }
    }

    /// SPK-1800b: select end — commit move (snapped if 18000a on) or marquee hit-test.
    private func handleSelectEnd(_ value: DragGesture.Value) {
        if isMarqueeDragging {
            // Commit marquee selection.
            if let start = marqueeStart, let end = marqueeEnd {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if rect.width > 3 || rect.height > 3 {
                    commitMarqueeSelection(rect)
                }
            }
            isMarqueeDragging = false
            marqueeStart = nil
            marqueeEnd = nil
            dragStart = nil
            return
        }
        if let idx = selectedIndex, session.shapes.indices.contains(idx) {
            var dx = Double(value.translation.width / scale)
            var dy = Double(-value.translation.height / scale)
            if snapToGridOn {
                dx = round(dx / Double(canvasGridStep)) * Double(canvasGridStep)
                dy = round(dy / Double(canvasGridStep)) * Double(canvasGridStep)
            }
            session.moveShape(at: idx, by: dx, dy: dy)
        }
        dragStart = nil
    }

    /// SPK-1800b: select all shapes whose bounds intersect the marquee rect.
    private func commitMarqueeSelection(_ rect: CGRect) {
        let flags = NSEvent.modifierFlags
        let isMulti = flags.contains(.command) || flags.contains(.shift)
        if !isMulti {
            session.selectedShapeIndices = []
        }
        var count = 0
        for (idx, shape) in session.shapes.enumerated() {
            guard session.isShapeVisible(at: idx), session.isShapeEditable(at: idx) else { continue }
            let pts = GeometryBridge.toCorePaths([shape]).first?.points ?? []
            let bbox = pts.reduce(into: CGRect?.none) { acc, pt in
                let s = screen(pt.x, pt.y)
                if let r = acc {
                    acc = r.union(CGRect(x: s.x, y: s.y, width: 0, height: 0))
                } else {
                    acc = CGRect(x: s.x, y: s.y, width: 0, height: 0)
                }
            }
            if let b = bbox, b.intersects(rect) {
                session.selectedShapeIndices.insert(idx)
                count += 1
            }
        }
        session.statusMessage = count == 0 ? "Marquee: no shapes" : "Marquee: \(count) shape\(count == 1 ? "" : "s")"
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
        // SPK-1800a: snap the tapped point to the grid when snap is on.
        let point = snapToGrid(model(screenPoint))
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
        // SPK-1800a: snap both endpoints to the grid when snap is on.
        let s = snapToGrid(start)
        let c = snapToGrid(current)
        switch tool {
        case .rect: shape = CreateShapes.rect(from: vp(s), to: vp(c))
        case .circle: shape = CreateShapes.circle(center: vp(s), through: vp(c))
        default: shape = CreateShapes.line(from: vp(s), to: vp(c))
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
            x: (p.x - offset.width - screenPadX) / scale,
            y: -(p.y - offset.height - screenPadY) / scale
        )
    }

    private func screen(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * scale + offset.width + screenPadX,
            y: CGFloat(-y) * scale + offset.height + screenPadY
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
        lastCanvasSize = size
        var minX = 0.0
        var minY = 0.0
        var maxX = session.activeSheet?.width ?? 100
        var maxY = session.activeSheet?.depth ?? 100
        if !session.shapes.isEmpty {
            let rects = session.shapes.map(\.boundingRect)
            minX = min(minX, rects.map(\.minX).min() ?? minX)
            maxX = max(maxX, rects.map(\.maxX).max() ?? maxX)
            minY = min(minY, rects.map(\.minY).min() ?? minY)
            maxY = max(maxY, rects.map(\.maxY).max() ?? maxY)
        }
        let w = max(maxX - minX, 1)
        let h = max(maxY - minY, 1)
        let sx = (size.width - 80) / CGFloat(w)
        let sy = (size.height - 80) / CGFloat(h)
        scale = max(0.3, min(sx, sy, 8))
        scaleBeforePinch = scale
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        // screen(x,y) = (x*scale + offset.w + padX, -y*scale + offset.h + padY)
        offset = CGSize(
            width: size.width / 2 - CGFloat(cx) * scale - screenPadX,
            height: size.height / 2 + CGFloat(cy) * scale - screenPadY
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
