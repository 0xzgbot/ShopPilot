import SwiftUI
import ShopPilotCore

/// SPK-1103a — Preview stage bound to AppSession toolpaths/vectors.
/// Wireframe overlay from session G-code; optional draft heightfield on demand (non-blocking).
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

    private var segments: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)] {
        WireframeRenderer.generateSegments(from: session.gcodeLines)
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

    /// SPK-1103c — legend/status line for the preview toolbar.
    private var selectionLegend: String {
        guard let node = selectedToolpathNode else { return "No toolpath selected" }
        guard let result = node.toolpathResult else { return "Selected: \(node.name) (no result)" }
        let lineCount = result.split(separator: "\n", omittingEmptySubsequences: true).count
        return "Selected: \(node.name) (\(lineCount) lines)"
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
            Text("G-code lines: \(session.gcodeLines.count) · Ops: \(session.toolpaths.count) · Vectors: \(session.vectors.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Button(isSimulating ? "Sim…" : "Draft sim") {
                    runDraftSimulation()
                }
                .disabled(session.gcodeLines.isEmpty || isSimulating)
                .buttonStyle(.bordered)

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
                Button("Continue to Machine") {
                    session.loadFixtureGCodeIfNeeded()
                    session.selectedStage = .machine
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { fitContent() }
        .onChange(of: session.gcodeLines.count) { _, _ in fitContent() }
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

        // Draft heightfield samples
        if (mode == .heightfield || mode == .combined), !heightSamples.isEmpty {
            for sample in heightSamples {
                let pt = worldToView(sample.x, sample.y, size: size)
                let t = max(0, min(1, sample.z / 10))
                let rect = CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.2, green: 0.6 + 0.3 * t, blue: 0.3)))
            }
        }

        if PreviewEmptyState.isEmpty(gcodeCount: session.gcodeLines.count, vectorCount: session.vectors.count),
           let copy = PreviewEmptyState.copy(gcodeCount: session.gcodeLines.count, vectorCount: session.vectors.count) {
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

    /// Non-blocking draft heightfield — coarse grid on a background task.
    private func runDraftSimulation() {
        let lines = session.gcodeLines
        guard !lines.isEmpty else { return }
        isSimulating = true
        simStatus = "Generating draft heightfield…"
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                ToolpathSimulator.draftHeightSamples(from: lines, cellSizeMm: 2.0, stockMm: 120)
            }.value
            heightSamples = outcome.samples
            isSimulating = false
            simStatus = "Draft sim ready (\(outcome.samples.count) samples, \(String(format: "%.2f", outcome.seconds))s)"
            if mode == .wireframe { mode = .combined }
        }
    }
}
