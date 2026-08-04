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
            // SPK-1104b: hand off the FULL toolpath tree (all ops, tree
            // order), not the last single-op gcodeLines overwrite.
            MachineConnectionView(pendingGCode: session.allToolpathGCode)
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
            Divider().frame(height: 14)
            // SPK-3D-spine-a: import an STL relief as a heightfield.
            Button("STL Relief…") { session.importSTLHeightfieldFromPanel() }
                .help("Import an ASCII STL model as a heightfield relief")
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
    /// SPK-1133 — selected tool in the grouped tool browser (left pane).
    @State private var selectedBrowserToolID: UUID?

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
                // SPK-1102d: all four v1 strategies add real tree ops from Cut.
                Menu {
                    Button("Profile") { session.generateProfileToolpath() }
                        .help("Cut along the vectors (on/out/in)")
                    Button("Pocket") { session.generatePocketToolpath() }
                        .help("Clear the inside of closed vectors")
                    Button("Drill") { session.generateDrillToolpath() }
                        .help("Peck-drill holes at the centers of closed vectors")
                    Button("V-Carve") { session.generateVCarveToolpath() }
                        .help("Engrave vectors with a V-bit")
                    Divider()
                    // SPK-3D-spine-b: relief strategies (need an imported STL).
                    Button("Rough 3D") { session.generateRough3DToolpath() }
                        .help("Z-level rough the imported STL relief (needs a relief)")
                    Button("Finish 3D") { session.generateFinish3DToolpath() }
                        .help("Surface-following finish of the imported STL relief (needs a relief)")
                } label: {
                    Label("Add Toolpath", systemImage: "plus.circle")
                }
                .menuStyle(.button)
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
                VStack(spacing: 0) {
                    ToolpathTreeView(session: session)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    Divider()
                    // SPK-1133: tool browser grouped by class (left pane).
                    ToolBrowserView(
                        database: session.toolDatabase,
                        selectedToolID: $selectedBrowserToolID
                    )
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300, minHeight: 140, maxHeight: 220)
                }

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

                // SPK-1136a: Profile strategy form — installer-verified §R2 fields.
                if node.isProfileOperation {
                    ScrollView {
                        ProfileParamsForm(node: node) { newParams in
                            _ = session.applyProfileParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136b: Pocket strategy form — installer-verified §M fields.
                if node.isPocketOperation {
                    ScrollView {
                        PocketParamsForm(node: node) { newParams in
                            _ = session.applyPocketParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136c: Drill strategy form — installer-verified §N fields.
                if node.isDrillOperation {
                    ScrollView {
                        DrillParamsForm(node: node) { newParams in
                            _ = session.applyDrillParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136d: V-Carve strategy form — installer-verified §O fields.
                if node.isVCarveOperation {
                    ScrollView {
                        VCarveParamsForm(node: node) { newParams in
                            _ = session.applyVCarveParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
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

// MARK: - Profile strategy form (SPK-1136a)

/// Editable form for the installer-verified §R2 Profile field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine (dirty badge clears because the result is
/// fresh).
private struct ProfileParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (ProfileToolpathParams) -> Void

    @State private var params: ProfileToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (ProfileToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.profileParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Cut") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Mode", selection: $params.cutMode) {
                        ForEach([ProfileCutMode.outCut, .inCut, .onCut], id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Picker("Direction", selection: $params.cutDirection) {
                        ForEach([ProfileCutDirection.climb, .conventional], id: \.self) { dir in
                            Text(dir.displayName).tag(dir)
                        }
                    }
                    Picker("Finish passes", selection: $params.finishPasses) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
                .labelsHidden()
            }

            GroupBox("Feeds & depth") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Feed (mm/min)", $params.feedRateMmPerMin)
                    numRow("Plunge (mm/min)", $params.plungeFeedRateMmPerMin)
                    numRow("Depth/pass (mm)", $params.maxDepthOfCutMm)
                    numRow("Tool Ø (mm)", $params.toolDiameterMm)
                }
            }

            GroupBox("Tabs") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Add tabs", isOn: $params.addTabs)
                    if params.addTabs {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                            numRow("Length (mm)", $params.tabLengthMm)
                            numRow("Thickness (mm)", $params.tabThicknessMm)
                            numRow("Spacing (mm)", $params.tabSpacingMm)
                        }
                        Toggle("3D tabs", isOn: $params.use3DTabs)
                    }
                }
            }

            GroupBox("Ramping") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Type", selection: $params.rampType) {
                        ForEach([ProfileRampType.none, .smooth, .zigZag, .spiral], id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        numRow("Ramp distance (mm)", $params.rampDistanceMm)
                    }
                }
            }

            GroupBox("Leads") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Lead-in", selection: $params.leadInType) {
                        ForEach([ProfileLeadType.none, .straightLine, .circularArc], id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        numRow("Lead-in length (mm)", $params.leadInDistanceMm)
                        numRow("Lead-in angle (°)", $params.leadInAngleDegrees)
                        numRow("Arc radius (mm)", $params.circularLeadRadiusMm)
                        numRow("Lead-out length (mm)", $params.leadOutDistanceMm)
                    }
                    Toggle("Lead out", isOn: $params.doLeadOut)
                }
            }

            GroupBox("Corners") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Sharp external corner", isOn: $params.sharpExternalCorner)
                    Toggle("Sharp internal corner", isOn: $params.sharpInternalCorner)
                }
            }

            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private func numRow(_ label: String, _ value: Binding<Double>) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

// MARK: - Pocket strategy form (SPK-1136b)

/// Editable form for the installer-verified §M Pocket field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine.
private struct PocketParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (PocketToolpathParams) -> Void

    @State private var params: PocketToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (PocketToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.pocketParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Clearing") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Strategy", selection: $params.clearanceMode) {
                        ForEach([PocketClearanceMode.zigzag, .spiralOut, .adaptive], id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    Picker("Direction", selection: $params.cutDirection) {
                        ForEach([CutDirection.climb, .conventional], id: \.self) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                    if params.clearanceMode == .zigzag {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                            numRow("Raster angle (°)", $params.rasterAngleDegrees)
                        }
                    }
                    Picker("Profile pass", selection: $params.profilePass) {
                        ForEach([PocketProfilePass.first, .last, .none], id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }
                .labelsHidden()
            }

            GroupBox("Depth & passes") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Start depth (mm)", $params.startDepthMm)
                    numRow("Depth/pass (mm)", $params.maxDepthOfCutMm)
                    numRow("Pocket allowance (mm)", $params.allowanceMm)
                    numRow("Safe Z (mm)", $params.safetyHeightMm)
                }
                Toggle("Exact step depth", isOn: $params.exactStepDepth)
            }

            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Feed (mm/min)", $params.feedRateMmPerMin)
                    numRow("Plunge (mm/min)", $params.plungeFeedRateMmPerMin)
                    numRow("Step-over (mm)", $params.stepOverMm)
                    numRow("Tool Ø (mm)", $params.toolDiameterMm)
                }
            }

            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Ramp plunge moves", isOn: $params.rampPlungeMoves)
                    Toggle("Use vector selection order", isOn: $params.useVectorSelectionOrder)
                }
            }

            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private func numRow(_ label: String, _ value: Binding<Double>) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

// MARK: - Drill strategy form (SPK-1136c)

/// Editable form for the installer-verified §N Drill field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine.
private struct DrillParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (DrillToolpathParams) -> Void

    @State private var params: DrillToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (DrillToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.drillParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Cycle") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Type", selection: $params.cycleType) {
                        ForEach(
                            [DrillCycleType.spotDrill, .peckDrill, .deepHolePeck, .counterbore, .countersink],
                            id: \.self
                        ) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    Toggle("Peck drilling", isOn: $params.peckDrilling)
                }
                .labelsHidden()
            }

            GroupBox("Depth") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Start depth (mm)", $params.startDepthMm)
                    numRow("Cut depth (mm)", $params.cutDepthMm)
                    numRow("Peck depth (mm)", $params.peckDepthMm)
                }
            }

            GroupBox("Retract") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Mode", selection: $params.retractMode) {
                        ForEach([DrillRetractMode.aboveCuttingStart, .abovePreviousPass], id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        numRow("Retract gap (mm)", $params.peckRetractGapMm)
                        numRow("Retract height (mm)", $params.retractHeightMm)
                        numRow("Safe Z (mm)", $params.safetyHeightMm)
                    }
                }
            }

            GroupBox("Dwell") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Dwell at bottom", isOn: $params.dwellAtBottom)
                    if params.dwellAtBottom {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                            numRow("Dwell time (s)", $params.dwellTimeSeconds)
                        }
                    }
                }
            }

            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Feed (mm/min)", $params.feedRateMmPerMin)
                    numRow("Plunge (mm/min)", $params.plungeFeedRateMmPerMin)
                    numRow("Tool Ø (mm)", $params.toolDiameterMm)
                }
            }

            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private func numRow(_ label: String, _ value: Binding<Double>) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

// MARK: - V-Carve strategy form (SPK-1136d)

/// Editable form for the installer-verified §O V-Carve field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine.
private struct VCarveParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (VCarveParams) -> Void

    @State private var params: VCarveParams

    init(node: ToolpathTreeNode, onApply: @escaping (VCarveParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.vcarveParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Tool") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("V-bit angle (°)", $params.vBitAngleDegrees)
                    numRow("Feed (mm/min)", $params.feedRateMmPerMin)
                    numRow("Plunge (mm/min)", $params.plungeFeedRateMmPerMin)
                    numRow("Step-over (mm)", $params.stepOverMm)
                }
            }

            GroupBox("Depth") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Start depth (mm)", $params.startDepthMm)
                    numRow("Cut depth (mm)", $params.maxDepthOfCutMm)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Flat-bottom mode", isOn: $params.flatBottomMode)
                    if params.flatBottomMode {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                            numRow("Flat depth limit (mm)", $params.flatDepthMm)
                        }
                    }
                }
            }

            GroupBox("Leads") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Lead-in (mm)", $params.leadInDistanceMm)
                    numRow("Lead-out (mm)", $params.leadOutDistanceMm)
                    numRow("Safe Z (mm)", $params.safeZHeightMm)
                }
            }

            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Corner sharpen", isOn: $params.cornerSharpen)
                    Toggle("Use vector start points", isOn: $params.useVectorStartPoints)
                    Toggle("Use vector selection order", isOn: $params.useVectorSelectionOrder)
                    Toggle("Ramp plunge moves", isOn: $params.rampPlungeMoves)
                }
            }

            // SPK-VCarveClear — clearance-tool pass before the V-bit.
            GroupBox("Clearance (before V-Bit)") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Clearance pass enabled", isOn: $params.clearancePassEnabled)
                    if params.clearancePassEnabled {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                            numRow("Tool dia (mm)", $params.clearanceToolDiameterMm)
                            numRow("Clear depth (mm)", $params.clearanceDepthMm)
                            numRow("Step-over × dia", $params.clearanceStepOverMm)
                        }
                    }
                }
            }

            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private func numRow(_ label: String, _ value: Binding<Double>) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

