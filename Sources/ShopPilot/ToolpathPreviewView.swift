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

    @State private var scale: CGFloat = 2.5
    @State private var baseScale: CGFloat = 2.5
    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var mode: PreviewMode = .wireframe
    @State private var simStatus: String = "Idle"
    @State private var heightSamples: [(x: Double, y: Double, z: Double)] = []
    @State private var isSimulating = false
    @State private var simTask: Task<Void, Never>?
    @State private var cancelFlag = PreviewSimCancelFlag()
    /// SPK-1008 — webcam overlay visibility in the Preview stage.
    @State private var showCamera = false

    private var segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] {
        WireframeRenderer.generateSegments(from: session.allToolpathGCode)
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

                Button("Fit") { fitContent() }
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

                Button("Generate profile if empty") {
                    if session.vectors.isEmpty { session.addDemoRectangle() }
                    session.generateProfileToolpath()
                    fitContent()
                }
                .buttonStyle(.borderedProminent)
            }

            GeometryReader { _ in
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Canvas { context, size in
                        drawPreview(context: context, size: size)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(0.4, min(12, baseScale * value))
                            }
                            .onEnded { _ in
                                baseScale = scale
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                pan = CGSize(
                                    width: dragStart.width + value.translation.width,
                                    height: dragStart.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragStart = pan
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
                // SPK-1008 — webcam overlay toggle (watch the stock while the
                // sim runs). Camera availability degrades gracefully.
                Toggle("Camera", isOn: $showCamera)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Show the live webcam feed over the preview (SPK-1008)")
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
        .onAppear { fitContent() }
        .onChange(of: session.allToolpathGCode.count) { _, _ in fitContent() }
    }

    private func worldToView(_ x: Double, _ y: Double, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + pan.width + CGFloat(x) * scale,
            y: size.height / 2 + pan.height - CGFloat(y) * scale
        )
    }

    private func drawPreview(context: GraphicsContext, size: CGSize) {
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

        // Toolpath wireframe
        if mode == .wireframe || mode == .combined {
            for seg in segments {
                var p = Path()
                p.move(to: worldToView(seg.start.x, seg.start.y, size: size))
                p.addLine(to: worldToView(seg.end.x, seg.end.y, size: size))
                let color: Color = seg.isRapid ? .orange.opacity(0.7) : .red
                context.stroke(p, with: .color(color), lineWidth: seg.isRapid ? 1 : 2)
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
                    let r = CGFloat(radius) * scale
                    let ellipse = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    context.fill(ellipse, with: .color(fill))
                    context.stroke(ellipse, with: .color(edge), style: dash)
                }
            case .polygon:
                break // polygon entry UI is a later pass; rect/circle cover v0
            }
        }

        // Draft heightfield samples
        if (mode == .heightfield || mode == .combined), !heightSamples.isEmpty {
            for sample in heightSamples {
                let pt = worldToView(sample.x, sample.y, size: size)
                let t = max(0, min(1, sample.z / 10))
                let rect = CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.2, green: 0.6 + 0.3 * t, blue: 0.3)))
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

    private func fitContent() {
        var xs: [Double] = []
        var ys: [Double] = []
        for path in session.vectors {
            for pt in path.points { xs.append(pt.x); ys.append(pt.y) }
        }
        for seg in segments {
            xs.append(seg.start.x); ys.append(seg.start.y)
            xs.append(seg.end.x); ys.append(seg.end.y)
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            scale = 2.5
            baseScale = 2.5
            pan = .zero
            dragStart = .zero
            return
        }
        let w = max(maxX - minX, 1)
        let h = max(maxY - minY, 1)
        scale = CGFloat(min(400 / w, 280 / h))
        baseScale = scale
        pan = .zero
        dragStart = .zero
    }

    /// SPK-1103e / SPK-0315: sheet-aware material sim on a background task —
    /// cancellable (Cancel button → per-line poll) and non-blocking. When the
    /// dirty-region tracker has a PARTIAL change (only some tree nodes dirty),
    /// only the dirty nodes' G-code is re-simulated and the status reports the
    /// delta; a full-tree change (or no dirty state) simulates everything.
    private func runMaterialSimulation() {
        let fullLines = session.allToolpathGCode
        guard !fullLines.isEmpty else { return }
        guard let sheet = session.job.sheets.first else { return }
        cancelFlag.cancelled = false
        isSimulating = true
        simStatus = "Simulating material…"
        let manager = session.dirtyRegionManager
        simTask = Task {
            let flag = cancelFlag
            let (samples, isPartial) = await manager.performResimulation(
                partialLines: session.dirtyToolpathGCode,
                fullLines: fullLines,
                sheetWidthMm: sheet.width,
                sheetDepthMm: sheet.depth,
                stockTopMm: sheet.height,
                cellSizeMm: 1.0,
                shouldCancel: { flag.cancelled }
            )
            heightSamples = samples
            isSimulating = false
            simTask = nil
            if flag.cancelled {
                simStatus = "Sim cancelled (\(samples.count) samples kept)"
            } else if isPartial {
                simStatus = "Dirty-region resim (\(samples.count) samples, changed nodes only)"
            } else {
                simStatus = "Material sim ready (\(samples.count) samples)"
            }
            if mode == .wireframe { mode = .combined }
        }
    }
}
