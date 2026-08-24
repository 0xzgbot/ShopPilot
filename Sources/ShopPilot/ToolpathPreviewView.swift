import SwiftUI
import ShopPilotCore

/// SPK-1103e — thread-safe cancel flag shared with the detached sim task so the
/// Cancel button can abort a long material sim mid-flight (polled per G-code line).
private final class PreviewSimCancelFlag: @unchecked Sendable {
    var cancelled = false
}

/// SPK-1103a — Preview stage bound to AppSession toolpaths/vectors.
/// Wireframe overlay from session G-code; optional sheet-aware material
/// heightfield on demand (non-blocking, cancellable — SPK-1103e).
struct ToolpathPreviewView: View {
    @ObservedObject var session: AppSession

    /// User zoom/pan on top of a per-frame Fit to the live Canvas size.
    /// Framing used stale @State size before, which left isometric stock
    /// in a corner (world origin at screen center, pan never applied).
    @State private var userZoom: CGFloat = 1
    @State private var userZoomAtPinch: CGFloat = 1
    @State private var userPan: CGSize = .zero
    @State private var userPanAtDrag: CGSize = .zero
    @State private var mode: PreviewMode = .combined
    @State private var simStatus: String = "Idle"
    /// SPK-1700a — the FULL dense simulated heightmap (every cell), drawn as
    /// a filled raster image at cell size (not the old /40 dot scatter).
    @State private var simHeightmap: Heightmap?
    /// Cached filled-raster image built from `simHeightmap` + the selected
    /// material palette (rebuilt when either changes).
    @State private var simImage: CGImage?
    @State private var isSimulating = false
    /// SPK-1700b — playhead over sim time (0…1 = G-code progress). Scrubbing
    /// shows the heightfield as of that toolpath prefix (cancellable
    /// prefix-sim); 1 reuses the cached full sim.
    @State private var playhead: Double = 1.0
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?
    @State private var scrubTask: Task<Void, Never>?
    /// The last FULL sim result (playhead 1 shows this without re-running).
    @State private var fullSimHeightmap: Heightmap?
    /// Lines + sheet footprint the last full sim ran on — the scrub
    /// prefix-sims over these.
    @State private var simLines: [String] = []
    @State private var simSheet: (width: Double, depth: Double, stock: Double)?
    /// SPK-1700b — cached wireframe parse. Playback re-renders the view at
    /// ~7 Hz; re-parsing the full G-code buffer (segments + per-node map +
    /// peck retracts) on EVERY render saturated the main thread on big jobs
    /// (5k+ lines) and starved the AX server. Invalidated only when the
    /// G-code buffer actually changes.
    @State private var wireCache: (signature: String,
                                   segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)],
                                   perNode: [UUID: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]],
                                   pecks: [(start: (x: Double, y: Double), end: (x: Double, y: Double))])?
    @State private var simTask: Task<Void, Never>?
    @State private var cancelFlag = PreviewSimCancelFlag()
    /// SPK-1008 — webcam overlay visibility in the Preview stage.
    @State private var showCamera = false
    /// SPK-1206 — view orientation (top/iso/front) + orthographic toggle.
    @State private var viewOrientation: ViewOrientation = .isometric
    @State private var orthographic = true
    /// SPK-1202 — material surface palette for the heightfield preview.
    @State private var materialPaletteName = MaterialSurfacePalette.presets[0].name

    private var segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] {
        cachedWire().segments
    }

    /// Cheap content signature for the G-code buffer (line count + total
    /// chars + first/last line) — O(n) but ~100× cheaper than re-parsing.
    private func wireSignature(_ lines: [String]) -> String {
        let chars = lines.reduce(0) { $0 + $1.count }
        return "\(lines.count)|\(chars)|\(lines.first ?? "")|\(lines.last ?? "")"
    }

    /// SPK-1700b — parsed wireframe data (segments, per-node map, peck
    /// retracts), cached across the high-frequency playback re-renders.
    /// Recomputes only when the G-code buffer actually changes.
    private func cachedWire() -> (segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)],
                                  perNode: [UUID: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]],
                                  pecks: [(start: (x: Double, y: Double), end: (x: Double, y: Double))]) {
        let lines = session.allToolpathGCode
        let sig = wireSignature(lines)
        if let cache = wireCache, cache.signature == sig {
            return (cache.segments, cache.perNode, cache.pecks)
        }
        let parsed = (
            segments: WireframeRenderer.generateSegments(from: lines),
            perNode: session.segmentsByToolpathNode,
            pecks: WireframeRenderer.detectPeckRetracts(from: lines)
        )
        wireCache = (sig, parsed.segments, parsed.perNode, parsed.pecks)
        return parsed
    }

    /// SPK-1103c — the currently selected toolpath tree node (recursive lookup,
    /// covers nested groups). nil when nothing is selected.
    private var selectedToolpathNode: ToolpathTreeNode? {
        guard let id = session.selectedToolpathID else { return nil }
        return session.toolpathTree.root.findNode(id: id)
    }

    /// SPK-1103c — G-code segments of the selected node only, parsed with the
    /// same renderer as the full wireframe. nil when no selection or no result.
    private var selectedSegments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]? {
        guard let node = selectedToolpathNode, let result = node.toolpathResult else { return nil }
        let lines = result.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return WireframeRenderer.generateSegments(from: lines)
    }

    /// SPK-0316 — ghost diff: when the selected node was regenerated, diff its
    /// previous G-code against the current one. The removed/moved geometry is
    /// rendered as a dashed cyan ghost overlay so the user sees what changed.
    private var ghostSegments: [(start: (x: Double, y: Double), end: (x: Double, y: Double))]? {
        guard let node = selectedToolpathNode,
              let old = node.previousResult,
              let new = node.toolpathResult else { return nil }
        let diff = PathDiffEngine.compareGCode(old, new)
        let ghost = PathDiffEngine.generateGhostData(from: diff)
        guard !ghost.movedLines.isEmpty || !ghost.removedPoints.isEmpty else { return nil }
        // Ghost lines: every moved pair becomes a line from old → new position.
        var lines = ghost.movedLines
        // Removed points get a short marker line from the point to itself+1mm
        // so they are visible as dots in the overlay.
        for pt in ghost.removedPoints {
            lines.append((pt, (pt.x + 1, pt.y)))
        }
        return lines
    }

    /// SPK-1103c — legend/status line for the preview toolbar.
    private var selectionLegend: String {
        guard let node = selectedToolpathNode else { return "No toolpath selected" }
        guard let result = node.toolpathResult else { return "Selected: \(node.name) (no result)" }
        let lineCount = result.split(separator: "\n", omittingEmptySubsequences: true).count
        var legend = "Selected: \(node.name) (\(lineCount) lines)"
        if node.previousResult != nil, ghostSegments != nil {
            legend += " · cyan dashed = changed since last regen"
        }
        return legend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.title2.bold())
                Spacer()
                if session.isDirty {
                    Text("Document dirty")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(session.lastToolpathSummary)
                .foregroundStyle(.secondary)
            Text("G-code lines: \(session.allToolpathGCode.count) · Ops: \(session.toolpaths.count) · Vectors: \(session.vectors.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            // SPK-0312: whole-job time estimate (TimeEstimator over the full
            // buffer), next to the per-op estimates on each tree row.
            if let estimate = session.fullJobTimeEstimate {
                Text("Estimated total: ~\(estimate.formattedTotalTime) (\(estimate.formattedCuttingTime) cutting · \(estimate.formattedTravelTime) travel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(simStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(selectionLegend)
                .font(.caption2)
                .foregroundStyle(selectedToolpathNode == nil ? Color.secondary : Color.accentColor)

            HStack {
                Picker("Mode", selection: $mode) {
                    Text("Wireframe").tag(PreviewMode.wireframe)
                    Text("Heightfield").tag(PreviewMode.heightfield)
                    Text("Combined").tag(PreviewMode.combined)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Button("Fit") { resetUserCamera() }
                if isSimulating {
                    Button("Cancel") {
                        cancelFlag.cancelled = true
                        simTask?.cancel()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Simulate") {
                        runMaterialSimulation()
                    }
                    .disabled(session.allToolpathGCode.isEmpty)
                    .buttonStyle(.bordered)
                }

                // SPK-1700b — playhead over sim time (0…1 = G-code progress).
                // Always visible (disabled until sim completes) so users see
                // playback is coming and AX can find it during UI walks.
                Button(isPlaying ? "Pause" : "Play") {
                    isPlaying ? pausePlayback() : startPlayback()
                }
                .disabled(simHeightmap == nil)
                .help("Play the cut simulation from start to end")
                Slider(value: $playhead, in: 0...1)
                    .frame(maxWidth: 160)
                    .disabled(simHeightmap == nil)
                    .help("Playhead — shows the heightfield as of this toolpath prefix")
                if simHeightmap != nil {
                    Text("\(Int(playhead * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                }

                // SPK-1920h (H-503) — LIVE playhead while streaming: the
                // streamer's line index drives the same progress readout so
                // the Preview mirrors the cut in real time. Hold pauses the
                // stream AND freezes this readout together (both derive from
                // streamer.currentLine, which stops advancing on Hold).
                if session.machine.streamer.isStreaming || session.machine.streamer.state.isPaused {
                    let total = max(1, session.machine.streamer.totalLines)
                    ProgressView(value: Double(session.machine.streamer.currentLine), total: Double(total))
                        .frame(maxWidth: 120)
                        .help("Live machine progress — line \(session.machine.streamer.currentLine) of \(total)")
                    Text("LIVE")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }

                Button("Generate profile if empty") {
                    if session.vectors.isEmpty { session.addDemoRectangle() }
                    session.generateProfileToolpath()
                    resetUserCamera()
                }
                .buttonStyle(.borderedProminent)
            }

            GeometryReader { geo in
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Canvas { context, size in
                        var ctx = context
                        drawPreview(context: &ctx, size: size)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                userZoom = max(0.4, min(8, userZoomAtPinch * value))
                            }
                            .onEnded { _ in
                                userZoomAtPinch = userZoom
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                userPan = CGSize(
                                    width: userPanAtDrag.width + value.translation.width,
                                    height: userPanAtDrag.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                userPanAtDrag = userPan
                            }
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
            }
            .frame(minHeight: 320)

            HStack {
                Button("Back to Cut") { session.selectedStage = .cut }
                Spacer()
                // SPK-1206 — view orientation preset picker + ortho toggle.
                Picker("View", selection: $viewOrientation) {
                    ForEach(ViewOrientation.allCases) { orientation in
                        Label(orientation.title, systemImage: orientation.icon).tag(orientation)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 260)
                .help("View orientation (⌘⌥1 top, ⌘⌥2 isometric, ⌘⌥3 front)")
                Toggle("Ortho", isOn: $orthographic)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Orthographic projection (SPK-1206)")
                // SPK-1202 — material surface picker (colors the heightfield
                // sim like the real stock: skin on top, base at depth).
                Picker("Material", selection: $materialPaletteName) {
                    ForEach(MaterialSurfacePalette.presets, id: \.name) { palette in
                        Text(palette.name).tag(palette.name)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 120)
                .help("Surface material for the heightfield preview (SPK-1202)")
                // SPK-1008 — optional camera overlay. SPK-1507: the copy is
                // honest — it is a separate overlay window over the sim, not
                // part of the cut simulation itself (and it may show nothing
                // when no camera is available).
                Toggle("Camera", isOn: $showCamera)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Show a camera view over the sim as a reference — the cut sim itself is the wireframe below (SPK-1008)")
                Button("Continue to Machine") {
                    session.loadFixtureGCodeIfNeeded()
                    session.selectedStage = .machine
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .overlay(alignment: .bottomTrailing) {
            WebcamOverlayView(isVisible: $showCamera)
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            // SPK-1206 — mini view gizmo: cube faces map to orientations.
            ViewGizmoView(orientation: $viewOrientation)
                .padding(12)
        }
        .onKeyPress { keyPress in
            // ⌘⌥1…3 — keyboard view presets (macOS onKeyPress).
            if keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.option),
               let char = keyPress.characters.first,
               let orientation = ViewOrientationShortcut.orientation(for: char) {
                viewOrientation = orientation
                return .handled
            }
            return .ignored
        }
        .onAppear {
            resetUserCamera()
            if simHeightmap == nil, !session.allToolpathGCode.isEmpty {
                runMaterialSimulation()
            }
        }
        // SPK-1700a — switching the material palette re-tints the filled raster.
        .onChange(of: materialPaletteName) { _, _ in rebuildSimImage() }
        // SPK-1700b — scrubbing/playing the playhead shows the heightfield
        // as of that toolpath prefix.
        .onChange(of: playhead) { _, newValue in
            scrubToPlayhead(newValue)
        }
    }

    private func worldToView(_ x: Double, _ y: Double, size: CGSize) -> CGPoint {
        // SPK-1206 — 2.5D projection: top = identity; iso shears X and
        // compresses Y; front collapses Y (edge-on).
        let cam = camera(for: size)
        let proj = ViewProjection.projection(for: viewOrientation, orthographic: orthographic)
        let mapped = proj.map(x: x, y: y)
        return CGPoint(
            x: size.width / 2 + cam.pan.width + CGFloat(mapped.x) * cam.scale,
            y: size.height / 2 + cam.pan.height - CGFloat(mapped.y) * cam.scale
        )
    }

    /// SPK-1316 — the active sheet as a soft stock block: translucent fill
    /// + a labeled edge, drawn FIRST so the toolpath wireframe sits "on" it.
    /// Uses the same world convention as the material sim (sheet spans
    /// [0, width] × [0, depth], origin at a corner).
    private func drawSheetStock(context: GraphicsContext, size: CGSize) {
        guard let sheet = session.activeSheet else { return }
        let p0 = worldToView(0, 0, size: size)
        let p1 = worldToView(sheet.width, sheet.depth, size: size)
        let rect = CGRect(x: p0.x, y: p1.y,
                          width: p1.x - p0.x, height: p0.y - p1.y)
        guard rect.width > 2, rect.height > 2 else { return }
        // Block fill: wood-ish tint in the heightfield/combined modes, a
        // faint slate in pure wireframe so it never drowns the cuts.
        let fill: Color = (mode == .heightfield || mode == .combined)
            ? Color(red: 0.55, green: 0.38, blue: 0.20).opacity(0.16)
            : Color.gray.opacity(0.06)
        context.fill(Path(rect), with: .color(fill))
        // Edge + dimension caption.
        context.stroke(Path(rect), with: .color(Color.secondary.opacity(0.5)),
                       lineWidth: 1)
        let caption = "\(Int(sheet.width)) × \(Int(sheet.depth)) mm · \(sheet.name)"
        context.draw(
            Text(caption)
                .font(.caption2)
                .foregroundColor(.secondary),
            at: CGPoint(x: rect.midX, y: rect.minY - 8),
            anchor: .center
        )
    }

    private func drawPreview(context: inout GraphicsContext, size: CGSize) {
        // SPK-1316 — sheet-aware stock: the ACTIVE sheet drawn as a soft
        // block under everything, so toolpaths read as cutting this piece.
        drawSheetStock(context: context, size: size)

        // Design vectors (session-owned)
        for path in session.vectors {
            guard path.points.count >= 2 else { continue }
            var p = Path()
            let first = path.points[0]
            p.move(to: worldToView(first.x, first.y, size: size))
            for pt in path.points.dropFirst() {
                p.addLine(to: worldToView(pt.x, pt.y, size: size))
            }
            if path.isClosed {
                p.addLine(to: worldToView(first.x, first.y, size: size))
            }
            context.stroke(p, with: .color(.blue.opacity(0.55)), lineWidth: 1.5)
        }

        // Toolpath wireframe — SPK-1210: when a Cut row is hovered, only
        // that op's segments draw at full strength (everything else dims);
        // peck retracts draw dashed. Node identity comes from the session's
        // per-node segment map (the tree knows which op each O= marker
        // belongs to — two Profiles are distinguishable there).
        if mode == .wireframe || mode == .combined {
            let hoverID = session.hoveredToolpathID
            let perNode = cachedWire().perNode
            for (nodeID, nodeSegments) in perNode {
                guard hoverID == nil || hoverID == nodeID else { continue }
                for seg in nodeSegments {
                    var p = Path()
                    p.move(to: worldToView(seg.start.x, seg.start.y, size: size))
                    p.addLine(to: worldToView(seg.end.x, seg.end.y, size: size))
                    let baseColor: Color = seg.isRapid ? .orange.opacity(0.7) : .red
                    context.stroke(p, with: .color(baseColor), lineWidth: seg.isRapid ? 1 : 2)
                }
            }
            // Peck retracts: dashed yellow ticks at the drill points.
            if mode == .combined || mode == .wireframe {
                let pecks = cachedWire().pecks
                for peck in pecks {
                    let pt = worldToView(peck.start.x, peck.start.y, size: size)
                    let rect = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                    var dash = Path(ellipseIn: rect)
                    context.stroke(dash, with: .color(.yellow.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
        }

        // SPK-1103c — selected toolpath highlight, drawn on top of the full wireframe.
        if (mode == .wireframe || mode == .combined), let selected = selectedSegments {
            for seg in selected {
                var p = Path()
                p.move(to: worldToView(seg.start.x, seg.start.y, size: size))
                p.addLine(to: worldToView(seg.end.x, seg.end.y, size: size))
                context.stroke(p, with: .color(Color.accentColor), lineWidth: 3)
            }
        }

        // SPK-0316 — ghost diff overlay: dashed cyan lines mark what changed
        // since the selected node was last regenerated.
        if (mode == .wireframe || mode == .combined), let ghost = ghostSegments {
            let dash = StrokeStyle(lineWidth: 2, dash: [5, 4])
            for seg in ghost {
                var p = Path()
                p.move(to: worldToView(seg.start.x, seg.start.y, size: size))
                p.addLine(to: worldToView(seg.end.x, seg.end.y, size: size))
                context.stroke(p, with: .color(.cyan.opacity(0.9)), style: dash)
            }
        }

        // SPK-0308 — keep-out zone overlay (translucent fill + dashed edge).
        for zone in session.keepOutZones {
            let fill = zone.isActive ? Color.red.opacity(0.25) : Color.red.opacity(0.08)
            let edge = zone.isActive ? Color.red : Color.red.opacity(0.4)
            let dash = StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            switch zone.type {
            case .rectangle:
                if let minX = zone.rectMinX, let minY = zone.rectMinY,
                   let maxX = zone.rectMaxX, let maxY = zone.rectMaxY {
                    let p0 = worldToView(minX, minY, size: size)
                    let p1 = worldToView(maxX, maxY, size: size)
                    let rect = CGRect(x: p0.x, y: p1.y, width: p1.x - p0.x, height: p0.y - p1.y)
                    context.fill(Path(rect), with: .color(fill))
                    context.stroke(Path(rect), with: .color(edge), style: dash)
                }
            case .circle:
                if let center = zone.circleCenter, let radius = zone.circleRadiusMm {
                    let c = worldToView(center.x, center.y, size: size)
                    let r = CGFloat(radius) * camera(for: size).scale
                    let ellipse = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    context.fill(ellipse, with: .color(fill))
                    context.stroke(ellipse, with: .color(edge), style: dash)
                }
            case .polygon:
                break // polygon entry UI is a later pass; rect/circle cover v0
            }
        }

        // SPK-1700a — filled heightfield raster: the FULL dense heightmap
        // drawn as an image at cell size (not the old /40 dot scatter),
        // tinted by the material palette (SPK-1202). Drawn under the same
        // 2.5D projection as the wireframe so top/iso/front all stay
        // geometrically consistent (sheet edges are exactly the sheet rect).
        if (mode == .heightfield || mode == .combined), let img = simImage, let sheet = session.activeSheet {
            let proj = ViewProjection.projection(for: viewOrientation, orthographic: orthographic)
            if proj.yScale > 0.01 {   // front view is edge-on — nothing to raster
                let cam = camera(for: size)
                let t = CGAffineTransform(
                    a: cam.scale, b: 0,
                    c: CGFloat(proj.xShear) * cam.scale, d: -CGFloat(proj.yScale) * cam.scale,
                    tx: size.width / 2 + cam.pan.width, ty: size.height / 2 + cam.pan.height
                )
                context.concatenate(t)
                context.draw(
                    Image(decorative: img, scale: 1),
                    in: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.depth)
                )
                context.concatenate(t.inverted())
            }
        }

        if PreviewEmptyState.isEmpty(gcodeCount: session.allToolpathGCode.count, vectorCount: session.vectors.count),
           let copy = PreviewEmptyState.copy(gcodeCount: session.allToolpathGCode.count, vectorCount: session.vectors.count) {
            context.draw(
                Text("\(copy.title)\n\(copy.message)")
                    .font(.caption)
                    .foregroundColor(.secondary),
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                anchor: .center
            )
        }
    }

    /// Fit the **sheet** (not G-code rapids) to this Canvas size, then apply
    /// the user's pinch/drag on top. Computed every draw so isometric stock
    /// stays centered even when GeometryReader state is stale.
    private func camera(for size: CGSize) -> (scale: CGFloat, pan: CGSize) {
        var pts: [(x: Double, y: Double)] = []
        if let sheet = session.activeSheet {
            pts.append((0, 0))
            pts.append((sheet.width, 0))
            pts.append((sheet.width, sheet.depth))
            pts.append((0, sheet.depth))
        } else {
            for path in session.vectors {
                for pt in path.points { pts.append((pt.x, pt.y)) }
            }
        }
        let proj = ViewProjection.projection(for: viewOrientation, orthographic: orthographic)
        let fitted = PreviewCameraFit.fit(
            worldPoints: pts,
            projection: proj,
            viewportWidth: Double(max(size.width, 1)),
            viewportHeight: Double(max(size.height, 1))
        )
        let z = userZoom
        return (
            scale: CGFloat(fitted.scale) * z,
            pan: CGSize(
                width: CGFloat(fitted.panX) * z + userPan.width,
                height: CGFloat(fitted.panY) * z + userPan.height
            )
        )
    }

    private func resetUserCamera() {
        userZoom = 1
        userZoomAtPinch = 1
        userPan = .zero
        userPanAtDrag = .zero
    }

    /// SPK-1103e / SPK-0315: sheet-aware material sim on a background task —
    /// cancellable (Cancel button → per-line poll) and non-blocking. When the
    /// dirty-region tracker has a PARTIAL change (only some tree nodes dirty),
    /// only the dirty nodes' G-code is re-simulated and the status reports the
    /// delta; a full-tree change (or no dirty state) simulates everything.
    /// SPK-1700a: the result is the FULL dense heightmap, rendered as a
    /// filled raster (not a dot scatter).
    private func runMaterialSimulation() {
        let fullLines = session.allToolpathGCode
        guard !fullLines.isEmpty else { return }
        guard let sheet = session.job.sheets.first else { return }
        cancelFlag.cancelled = false
        isSimulating = true
        simStatus = "Simulating material…"
        simLines = fullLines
        simSheet = (sheet.width, sheet.depth, sheet.height)
        let manager = session.dirtyRegionManager
        simTask = Task {
            let flag = cancelFlag
            let (heightmap, isPartial) = await manager.performResimulationHeightmap(
                partialLines: session.dirtyToolpathGCode,
                fullLines: fullLines,
                sheetWidthMm: sheet.width,
                sheetDepthMm: sheet.depth,
                stockTopMm: sheet.height,
                cellSizeMm: 1.0,
                toolRadiusMm: session.previewToolRadiusMm,
                shouldCancel: { flag.cancelled }
            )
            if let heightmap {
                fullSimHeightmap = heightmap
                simHeightmap = heightmap
                rebuildSimImage()
            }
            isSimulating = false
            simTask = nil
            let cellCount = simHeightmap.map { $0.width * $0.height } ?? 0
            // SPK-DOGFOOD-04 — never claim "ready" with no heightfield. A nil
            // map after a non-cancelled run means the simulation produced no
            // data (empty buffer race, recover-from-autosave invalidation);
            // the honest status tells the user to press Simulate.
            if flag.cancelled {
                simStatus = "Sim cancelled (\(cellCount) cells kept)"
            } else if simHeightmap == nil {
                simStatus = "Material sim empty — press Simulate"
            } else if isPartial {
                simStatus = "Dirty-region resim (\(cellCount) cells, changed nodes only)"
            } else {
                simStatus = "Material sim ready (\(cellCount) cells)"
            }
            if mode == .wireframe { mode = .combined }
            // SPK-1700b — a paused playhead stays where the user left it.
            if playhead < 1 { scrubToPlayhead(playhead) }
        }
    }

    /// SPK-1700b — show the heightfield AS OF the toolpath prefix at the
    /// playhead (0…1). Playhead 1 reuses the cached full sim; anything less
    /// runs a cancellable prefix-sim over the same lines/sheet the full sim
    /// used, so scrubbing feels like watching the cut happen.
    private func scrubToPlayhead(_ p: Double) {
        guard let sheet = simSheet, !simLines.isEmpty, !isSimulating else { return }
        scrubTask?.cancel()
        if p >= 0.999 {
            if let full = fullSimHeightmap {
                simHeightmap = full
                rebuildSimImage()
                simStatus = "Playhead 100% — full sim"
            }
            return
        }
        let lines = simLines
        let count = max(1, min(lines.count, Int(Double(lines.count) * p)))
        let prefix = Array(lines.prefix(count))
        let radius = session.previewToolRadiusMm
        let paletteName = materialPaletteName
        simStatus = "Scrubbing \(Int(p * 100))% (\(count)/\(lines.count) lines)…"
        // Task.detached: the sync prefix-sim AND the filled-raster image
        // build (240k+ pixels) must run OFF the main actor — a Task created
        // here inherits the view's main-actor isolation and would beachball
        // the UI on big jobs; results hop back to main.
        scrubTask = Task.detached(priority: .userInitiated) {
            let outcome = await ToolpathSimulator.simulateHeightmap(
                from: prefix,
                sheetWidthMm: sheet.width,
                sheetDepthMm: sheet.depth,
                stockTopMm: sheet.stock,
                cellSizeMm: 1.0,
                toolRadiusMm: radius,
                shouldCancel: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            let palette = MaterialSurfacePalette.preset(named: paletteName)
                ?? MaterialSurfacePalette.presets[0]
            let image = Self.heightfieldImage(from: outcome.heightmap, palette: palette)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                simHeightmap = outcome.heightmap
                simImage = image
                simStatus = "Playhead \(Int(p * 100))% · \(prefix.count)/\(lines.count) lines"
            }
        }
    }

    /// SPK-1700b — sweep the playhead 0 → 1 (~18s), re-prefix-simming on
    /// every tick via `scrubToPlayhead`. Resets to 0 first so a playhead
    /// left at 1.0 (default/full) still plays.
    private func startPlayback() {
        guard simHeightmap != nil else { return }
        isPlaying = true
        playTask = Task {
            playhead = 0
            while !Task.isCancelled && playhead < 1 {
                // Duration-based sleep — the deprecated nanoseconds variant
                // returned immediately in this context, racing 0 → 100%.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                playhead = min(1, playhead + 1.0 / 120.0)
            }
            isPlaying = false
        }
    }

    private func pausePlayback() {
        isPlaying = false
        playTask?.cancel()
    }

    /// SPK-1700a — (re)build the filled raster image from the current
    /// heightmap + material palette (one pixel per cell; row 0 = world max-Y
    /// so the image draws upright under the view's flipped projection).
    private func rebuildSimImage() {
        guard let hm = simHeightmap else {
            simImage = nil
            return
        }
        let palette = MaterialSurfacePalette.preset(named: materialPaletteName)
            ?? MaterialSurfacePalette.presets[0]
        simImage = Self.heightfieldImage(from: hm, palette: palette)
    }

    /// Build a filled CGImage of the heightmap at one pixel per cell, tinted
    /// by the material palette (skin color on top, base revealed at depth).
    private static func heightfieldImage(from hm: Heightmap, palette: MaterialSurfacePalette) -> CGImage? {
        let w = hm.width
        let h = hm.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for gy in 0..<h {
            let worldY = h - 1 - gy   // image row 0 = world max-Y
            for gx in 0..<w {
                let z = hm.getHeight(gx, worldY)
                let t = max(0, min(1, z / 10))
                let c = palette.color(atDepthFraction: t)
                let i = (gy * w + gx) * 4
                pixels[i] = UInt8(max(0, min(255, c.r * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, c.g * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, c.b * 255)))
                pixels[i + 3] = 255
            }
        }
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
