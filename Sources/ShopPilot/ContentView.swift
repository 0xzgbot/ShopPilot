import SwiftUI
import ShopPilotCore
import AppKit
import ShopPilotSerial
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("shop_pilot_pro_skip") private var proSkip = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StageRailView(selectedStage: $session.selectedStage) { _ in }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                HSplitView {
                    LeftPanelView(session: session)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

                    VStack(spacing: 0) {
                        stageBody
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !proSkip {
                            CoachPanelView(currentStage: session.selectedStage)
                                .padding(8)
                        }

                        statusBar
                    }

                    InspectorShell(session: session, currentStage: $session.selectedStage)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                }
            }

            if session.showCommandPalette {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { session.showCommandPalette = false }
                CommandPaletteView(
                    isOpen: $session.showCommandPalette,
                    onCommandSelected: { session.handleCommand($0) }
                )
            }
        }
        .sheet(isPresented: $session.showPreferences) {
            PreferencesView()
                .frame(width: 440, height: 320)
        }
        .sheet(isPresented: $session.showSafetyDisclaimer) {
            SafetyDisclaimerView {
                session.acceptSafety()
            }
        }
    }

    @ViewBuilder
    private var stageBody: some View {
        switch session.selectedStage {
        case .setup:
            SetupStageView(session: session)
        case .design:
            DesignStageView(session: session)
        case .model:
            ModelStageLockedView()
        case .cut:
            CutStageView(session: session)
        case .preview:
            ToolpathPreviewView(session: session)
        case .machine:
            MachineConnectionView(pendingGCode: session.gcodeLines)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(session.statusMessage)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(session.lastToolpathSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Stage panels

private struct SetupStageView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NewJobView(docVars: session.docVars) { job in
                    session.replaceJob(job)
                }
                MaterialSetupView(session: session)
                DocumentVariablesPanelView(model: session.docVars)
                    .frame(minHeight: 240)
            }
            .padding()
        }
    }
}

private struct DesignStageView: View {
    @ObservedObject var session: AppSession
    @State private var showOffsetDialog = false
    @State private var offsetDistance = "3.0"

    var body: some View {
        VStack(spacing: 0) {
            opsBar
            Divider()
            HSplitView {
                DesignCanvasView(session: session)
                ImportHubView { shapes in
                    session.addShapes(shapes)
                }
                .frame(minWidth: 280, idealWidth: 320)
            }
        }
        .alert("Offset Vectors", isPresented: $showOffsetDialog) {
            TextField("Distance (mm)", text: $offsetDistance)
            Button("Offset") { applyOffset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Positive = outward, negative = inward.")
        }
    }

    /// SPK-1101d: Design ops bar — Offset / Weld / Subtract / Intersect /
    /// Join / Close / Trim, all routed through the session apply* methods
    /// (undo-point + dirty + persist via syncLayerVectors).
    private var opsBar: some View {
        HStack(spacing: 8) {
            Text("Ops:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Offset…") { showOffsetDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Offset selected vectors by a distance (positive = outward)")
            Button("Weld") { _ = session.applyWeld() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Union selected vectors into one region")
            Button("Subtract") { _ = session.applySubtract() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Subtract the 2nd..nth selected shapes from the first")
            Button("Intersect") { _ = session.applyIntersect() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Keep the overlap of all selected shapes")
            Button("Join") { _ = session.applyJoin() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Join selected lines/polylines that share endpoints")
            Button("Close") { _ = session.applyClose() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Close selected open polylines")
            Button("Trim") { _ = session.applyTrimToSelection() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Clip open vectors to the selected closed shapes' bounds")
            Divider().frame(height: 14)
            // SPK-1101f: transforms — one-shot, selection-gated, undo+dirty.
            Button("Nudge X+1") { _ = session.applyNudgeX() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Move selected vectors +1 mm in X")
            Button("Flip H") { _ = session.applyFlipHorizontal() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Mirror selected vectors across the selection centerline")
            Button("Rotate 90°") { _ = session.applyRotate90() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Rotate selected vectors 90° CCW around the selection centroid")
            Button("Scale 1.1×") { _ = session.applyScale110() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Scale selected vectors 1.1× about the selection centroid")
            Spacer()
            Text("\(session.selectedShapeIndices.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .controlSize(.small)
    }

    private func applyOffset() {
        let normalized = offsetDistance.replacingOccurrences(of: ",", with: ".")
        guard let distance = Double(normalized) else {
            session.statusMessage = "Offset: enter a number"
            return
        }
        _ = session.applyOffset(distance: distance)
    }
}

private struct ModelStageLockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Model (3D relief)")
                .font(.title2.bold())
            Text("Requires Studio3D. Use Design + Cut for the v0 demo path.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CutStageView: View {
    @ObservedObject var session: AppSession

    /// Blocker instance whose expert override is confirmed via the dirty-toolpath alert.
    @State private var exportBlocker: ExportBlocker?
    @State private var showExportBlockAlert = false
    @State private var exportBlockMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cut")
                    .font(.title2.bold())
                Spacer()
                Text("Vectors: \(session.vectors.count) · Ops: \(session.toolpaths.count) · G-code lines: \(session.gcodeLines.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Generate Profile Toolpath") {
                    session.generateProfileToolpath()
                }
                .buttonStyle(.borderedProminent)

                // SPK-1102c: regenerate dirty ops with the real engine; badge
                // count doubles as the enable signal.
                Button("Recalculate Dirty (\(session.toolpathTree.dirtyNodeCount))") {
                    _ = session.recalculateDirtyToolpaths()
                }
                .disabled(session.toolpathTree.dirtyNodeCount == 0)
                .help("Regenerate dirty Profile toolpaths (out-of-scope ops stay dirty)")

                Button("Load Fixture / Built-in G-code") {
                    session.loadFixtureGCodeIfNeeded()
                }

                Button("Send to Machine Stage") {
                    session.sendToMachineStage()
                }

                Spacer()

                Button {
                    handleSaveToolpaths()
                } label: {
                    Label("Save Toolpaths…", systemImage: "square.and.arrow.up")
                }
                .help("Export GRBL G-code to a file")
            }

            HSplitView {
                ToolpathTreeView(session: session)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

                selectedDetail
            }

            Spacer(minLength: 0)
        }
        .padding()
        .alert(
            "Toolpaths are not up to date — recalculate before saving",
            isPresented: $showExportBlockAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Save Anyway (Expert)") {
                _ = exportBlocker?.overrideExportBlock()
                saveToolpaths()
            }
        } message: {
            Text(exportBlockMessage)
        }
    }

    // MARK: - Save toolpaths to file (SPK-1102b)

    /// Entry point for the "Save Toolpaths…" button: validate the toolpath
    /// tree for export, then either save immediately or ask for an expert
    /// override when dirty nodes would be exported.
    private func handleSaveToolpaths() {
        guard !session.allToolpathGCode.isEmpty else {
            session.statusMessage = "No G-code to save — generate a toolpath first"
            return
        }

        let blocker = ExportBlocker(treeManager: session.toolpathTree)
        let result = blocker.validateForExport()

        if result.isValid {
            saveToolpaths()
        } else {
            exportBlocker = blocker
            exportBlockMessage = "Recalculate before saving: \(result.dirtyNodes.joined(separator: ", "))"
            showExportBlockAlert = true
        }
    }

    /// Present the save panel, post-process the session G-code through
    /// CutToMachineBridge, and write the GRBL file to the chosen URL.
    private func saveToolpaths() {
        let gcode = session.allToolpathGCode
        guard !gcode.isEmpty else {
            session.statusMessage = "No G-code to save — generate a toolpath first"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "job.gcode"
        panel.canCreateDirectories = true
        panel.title = "Save Toolpaths"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return // User cancelled
        }

        do {
            let result = try CutToMachineBridge.export(
                gcodeLines: gcode,
                toolInfo: nil,
                machineProfile: grblProfile,
                fileName: destinationURL.deletingPathExtension().lastPathComponent
            )

            if let errorMessage = result.errorMessage {
                session.statusMessage = "Save failed: \(errorMessage)"
                return
            }
            guard let exportedURL = result.outputFileURL else {
                session.statusMessage = "Save failed: bridge produced no output file"
                return
            }

            // The bridge writes post-processed G-code to its temp export
            // directory; copy it to the user-chosen destination.
            let data = try Data(contentsOf: exportedURL)
            try data.write(to: destinationURL, options: .atomic)

            // Report the line count actually written to disk (the bridge's
            // lineCount counts post-processor output rows, which can differ
            // from the file's newline count).
            let writtenText = String(data: data, encoding: .utf8) ?? ""
            let writtenLineCount = writtenText.split(whereSeparator: \.isNewline).count

            session.statusMessage =
                "Saved \(destinationURL.lastPathComponent) (\(writtenLineCount) lines)"
            session.lastToolpathSummary =
                "\(result.postProcessorType.displayName) — \(writtenLineCount) lines"
        } catch {
            session.statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// GRBL machine profile used to post-process exported G-code.
    private var grblProfile: MachineProfile {
        MachineProfile(name: "GRBL", config: .simulator, machineType: .grbl)
    }

    /// The toolpath node currently selected in the tree, if any.
    private var selectedNode: ToolpathTreeNode? {
        guard let id = session.selectedToolpathID else { return nil }
        return session.toolpathTree.findNode(id: id)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let node = selectedNode {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(node.name)
                        .font(.headline)
                    if node.isDirty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .help("Needs recalculation")
                    }
                    Spacer()
                    Text(Self.timeString(node.estimatedTimeSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .operation = node.type {
                    HStack(spacing: 6) {
                        Text("Tool")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ToolPickerMenu(
                            selectedToolID: node.toolID,
                            tools: session.toolDatabase.tools(ofTypes: [.endMill, .vBit]),
                            onSelect: { session.assignTool($0, toToolpath: node.id) }
                        )
                        Spacer()
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }

                let lines = (node.toolpathResult ?? "")
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if lines.isEmpty {
                    Text("No G-code for this toolpath yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }
                Spacer()
            }
            .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session G-code")
                    .font(.headline)
                if session.gcodeLines.isEmpty {
                    Text("No toolpath yet. Add shapes in Design, then generate Profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(session.gcodeLines.prefix(120).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }
                Spacer()
            }
            .padding(10)
        }
    }

    private static func timeString(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }
}

