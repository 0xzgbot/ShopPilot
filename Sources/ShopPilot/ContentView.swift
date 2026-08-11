import SwiftUI
import ShopPilotCore
import AppKit
import ShopPilotSerial
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("shop_pilot_pro_skip") private var proSkip = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopChromeBar(session: session, controller: session.machine)

                Divider()

                MachineAlarmBanner(controller: session.machine) {
                    session.selectedStage = .machine
                }

                HSplitView {
                    LeftPanelView(session: session)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                        .spSidebar(edge: .trailing)

                    VStack(spacing: 0) {
                        stageBody
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !proSkip {
                            // SPK-0318 + SPK-1205: pass the follow-source state
                            // AND the live session snapshot so the coach strip
                            // reacts to what's on screen (rules beat static copy).
                            CoachPanelView(
                                currentStage: session.selectedStage,
                                followSourceMode: session.linkManager.followSourceMode,
                                activeFollowLinkCount: session.linkManager.activeFollowLinkCount,
                                context: CoachContext(
                                    stage: session.selectedStage.rawValue,
                                    hasVectors: !session.vectors.isEmpty,
                                    hasSelection: session.selectedToolpathID != nil
                                        || !session.selectedVectorIDs.isEmpty
                                        || !session.selectedShapeIndices.isEmpty,
                                    isDirty: session.isDirty,
                                    hasToolpaths: !session.toolpaths.isEmpty,
                                    hasBlockingIssue: session.toolpathTree.dirtyNodeCount > 0,
                                    hasSheets: !session.job.sheets.isEmpty,
                                    isConnected: session.machine.connection.connectionState == .connected
                                )
                            )
                        }
                    }
                    .frame(minWidth: 420)

                    InspectorShell(session: session, currentStage: $session.selectedStage)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                        .spSidebar(edge: .leading)
                }

                Divider()

                statusBar
            }

            if session.showCommandPalette {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { session.showCommandPalette = false }
                    .transition(.opacity)
                CommandPaletteView(
                    isOpen: $session.showCommandPalette,
                    onCommandSelected: { session.handleCommand($0) }
                )
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(SP.Motion.state, value: session.showCommandPalette)
        .sheet(isPresented: $session.showPreferences) {
            PreferencesView()
                .frame(width: 440, height: 320)
        }
        .sheet(isPresented: $session.showSafetyDisclaimer) {
            SafetyDisclaimerView {
                session.acceptSafety()
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheetView(session: session) {
                FirstRunGate.acknowledge()
                showWelcome = false
            }
        }
        .onAppear {
            if FirstRunGate.isFirstRun {
                showWelcome = true
            }
        }
    }

    /// UI-polish cluster — first-run onboarding sheet (shown once).
    @State private var showWelcome = false

    @ViewBuilder
    private var stageBody: some View {
        switch session.selectedStage {
        case .setup:
            SetupStageView(session: session)
        case .design:
            DesignStageView(session: session)
        case .model:
            ModelStageView(session: session)
        case .cut:
            CutStageView(session: session)
        case .preview:
            ToolpathPreviewView(session: session)
        case .machine:
            // SPK-1104b: hand off the FULL toolpath tree (all ops, tree
            // order), not the last single-op gcodeLines overwrite.
            MachineConnectionView(
                pendingGCode: session.allToolpathGCode,
                controller: session.machine
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: SP.Space.s) {
            Text(session.statusMessage)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: SP.Space.m)

            if session.isDirty {
                Label("Edited", systemImage: "circle.fill")
                    .labelStyle(DotLabelStyle())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(session.lastToolpathSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, SP.Space.m)
        .frame(height: 24)
        .background(.bar)
    }
}

// MARK: - Top chrome

/// Document identity on the left, the stage rail dead centre, machine state on
/// the right. Both flanks reserve the same width so the rail stays optically
/// centred as the job name and machine state change.
private struct TopChromeBar: View {
    @ObservedObject var session: AppSession
    @ObservedObject var controller: MachineController

    var body: some View {
        HStack(spacing: SP.Space.m) {
            // The document title is the only thing here allowed to shrink.
            // Safety controls never truncate, so the flanks flex rather than
            // sharing one fixed width.
            documentIdentity
                .frame(minWidth: 90, idealWidth: 210, maxWidth: 260, alignment: .leading)
                .layoutPriority(0)

            Spacer(minLength: SP.Space.s)

            StageRailView(selectedStage: $session.selectedStage) { _ in }
                .layoutPriority(2)

            Spacer(minLength: SP.Space.s)

            machineChrome
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, SP.Space.m)
        .frame(height: 46)
        .background(.bar)
    }

    private var documentIdentity: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.job.name.isEmpty ? "Untitled Job" : session.job.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(session.selectedStage.intent)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Safety Req #1: while the machine is live, Hold (or Resume) and Reset
    /// stay in the window chrome even when the Machine stage is not on screen.
    private var showsCompactSafety: Bool {
        controller.chromeState.isLive && session.selectedStage != .machine
    }

    private var machineChrome: some View {
        HStack(spacing: SP.Space.s) {
            if showsCompactSafety {
                CompactSafetyControls(controller: controller)
            }

            // With safety controls alongside it, the pill drops to its glyph so
            // the row can never squeeze Hold or Reset.
            MachineStatePill(state: controller.chromeState, compact: showsCompactSafety) {
                withAnimation(SP.Motion.stage) { session.selectedStage = .machine }
            }
        }
        .animation(SP.Motion.state, value: controller.chromeState)
    }
}

// MARK: - Alarm banner

/// Loud but calm: full-width, red, one plain-English line, one way out.
private struct MachineAlarmBanner: View {
    @ObservedObject var controller: MachineController
    let openMachine: () -> Void

    var body: some View {
        Group {
            if case .alarm(let message) = controller.chromeState {
                HStack(spacing: SP.Space.s) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.white)

                    Text(message.isEmpty ? "The machine reported an alarm — motion stopped." : message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: SP.Space.m)

                    Button("Open Machine", action: openMachine)
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .padding(.horizontal, SP.Space.m)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(SP.Tint.safety)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Machine alarm. \(message)")
            }
        }
        .animation(SP.Motion.alarm, value: controller.chromeState)
    }
}

/// Renders a label as its symbol followed by text at dot scale — used for the
/// unsaved-changes marker so it reads as punctuation, not a warning.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SP.Space.xs) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(SP.Tint.hold)
            configuration.title
        }
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
                // SPK-0800 — multi-sheet management: add / remove / switch
                // sheets. Session-backed so every change is undoable + dirty
                // and the design surface + toolpath stock follow the active
                // sheet.
                SheetListView(
                    sheets: Binding(
                        get: { session.job.sheets },
                        set: { session.job.sheets = $0 }
                    ),
                    selectedSheetId: Binding(
                        get: { session.activeSheetID ?? session.job.sheets.first?.id },
                        set: { id in
                            guard let id else { return }
                            session.selectSheet(id: id)
                        }
                    ),
                    onAddSheet: {
                        session.addSheet() ?? Sheet(name: "Sheet 1")
                    },
                    onRemoveSheet: { id in
                        _ = session.removeSheet(id: id)
                    }
                )
                .frame(minHeight: 160)
                DoubleSidedSetupView(session: session)
                RotarySetupView(session: session)
                MaterialSetupView(session: session)
                DocumentVariablesPanelView(model: session.docVars)
                    .frame(minHeight: 240)
                DrivenDimensionsPanelView(session: session)
                GoldenJobsPanelView(session: session)
            }
            .padding()
        }
    }
}

private struct DesignStageView: View {
    @ObservedObject var session: AppSession
    @State private var showOffsetDialog = false
    /// SPK-1301 — dogbone corner-relief dialog state.
    @State private var showDogboneDialog = false
    @State private var dogboneBitDiameter = 6.0
    @State private var offsetDistance = "3.0"
    @State private var showFilletDialog = false
    @State private var filletRadius = "3.0"
    @State private var showExtendDialog = false
    @State private var extendDistance = "10.0"
    @State private var showArrayDialog = false
    @State private var arrayCols = "3"
    @State private var arrayRows = "2"
    @State private var arraySpacingX = "25.0"
    @State private var arraySpacingY = "25.0"
    @State private var showCircularDialog = false
    @State private var circularCount = "6"
    @State private var circularRotate = false
    @State private var showNestDialog = false
    @State private var nestMargin = "5.0"
    @State private var showTilingDialog = false
    @State private var tilingRows = "2"
    @State private var tilingCols = "3"
    @State private var tilingGap = "2.0"
    @State private var showKeyholeDialog = false
    @State private var keyholeHeadDia = "10.0"
    @State private var keyholeShaftDia = "5.0"
    @State private var showSetSizeDialog = false
    @State private var setSizeWidth = "100.0"
    @State private var setSizeHeight = "100.0"
    @State private var setSizePreserveAspect = false
    @State private var showTextDialog = false
    @State private var textString = "ShopPilot"
    @State private var textFontSize = "72.0"
    @State private var textScale = "1.0"
    /// SPK-UI605: Import hub is a sheet / empty-canvas panel — not a permanent
    /// right rail that reappears on every Design entry when vectors exist.
    @State private var showImportHub = false
    /// SPK-0806: expanded validator results panel (Validate All button).
    @State private var showValidationPanel = false

    var body: some View {
        VStack(spacing: 0) {
            opsBar
            Divider()
            HSplitView {
                DesignCanvasView(session: session)
                    .overlay(alignment: .center) {
                        // Empty canvas: one calm sentence and one way in,
                        // rather than a permanent import rail. The prompt is
                        // decorative — it must not intercept the drags the
                        // canvas needs, or the message ("draw straight onto the
                        // sheet") would be a lie. Only the button takes hits.
                        if session.vectors.isEmpty {
                            VStack(spacing: SP.Space.m) {
                                VStack(spacing: SP.Space.xs) {
                                    Image(systemName: Stage.design.icon)
                                        .font(.system(size: 30, weight: .light))
                                        .foregroundStyle(.tertiary)

                                    Text("Nothing drawn yet")
                                        .font(SP.Typography.stageTitle)

                                    Text("Pick a tool above and draw straight onto the sheet, or bring in an SVG or DXF.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 340)
                                }
                                .allowsHitTesting(false)

                                Button("Import Artwork…") { showImportHub = true }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                            }
                            .padding(SP.Space.xl)
                        }
                    }

                if session.preflightPanelVisible {
                    PreflightDoctorView(session: session)
                        .frame(minWidth: 280, idealWidth: 320)
                }

                if showValidationPanel, let validation = session.lastVectorValidation {
                    VectorValidationPanel(result: validation)
                        .frame(minWidth: 280, idealWidth: 320)
                }
            }
        }
        .sheet(isPresented: $showImportHub) {
            ImportHubView(
                onShapesImported: { shapes in
                    session.addShapes(shapes)
                    showImportHub = false
                },
                onRecordRecent: { url in
                    // SPK-1209 — remember imports for the Recent rail.
                    session.recentFilesStore.record(url)
                },
                recentFiles: session.recentFilesStore.recent,
                clearRecent: {
                    session.recentFilesStore.clear()
                }
            )
            .frame(width: 420, height: 520)
        }
        .alert("Offset Vectors", isPresented: $showOffsetDialog) {
            TextField("Distance (mm)", text: $offsetDistance)
            Button("Offset") { applyOffset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Positive = outward, negative = inward.")
        }
        .alert("Dogbone Corner Relief", isPresented: $showDogboneDialog) {
            TextField("Bit Diameter (mm)", value: $dogboneBitDiameter, format: .number)
            Button("Add Reliefs") {
                _ = session.addDogboneReliefs(bitDiameter: dogboneBitDiameter)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds corner-relief circles so a round bit can cut the pocket's square corners.")
        }
        .alert("Fillet Corners", isPresented: $showFilletDialog) {
            TextField("Radius (mm)", text: $filletRadius)
            Button("Fillet") { applyFillet() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rounds every corner of the selected vectors (rectangles become rounded freehands).")
        }
        .alert("Extend Vectors", isPresented: $showExtendDialog) {
            TextField("Distance (mm)", text: $extendDistance)
            Button("Extend") { applyExtend() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Extends both open ends of the selected vectors.")
        }
        .alert("Array Copy", isPresented: $showArrayDialog) {
            TextField("Columns", text: $arrayCols)
            TextField("Rows", text: $arrayRows)
            TextField("Spacing X (mm)", text: $arraySpacingX)
            TextField("Spacing Y (mm)", text: $arraySpacingY)
            Button("Copy") { applyArrayCopy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copies the selection into a columns × rows grid.")
        }
        .alert("Circular Copy", isPresented: $showCircularDialog) {
            TextField("Copies", text: $circularCount)
            Toggle("Rotate each copy", isOn: $circularRotate)
            Button("Copy") { applyCircularCopy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copies the selection around its center.")
        }
        .alert("Nest", isPresented: $showNestDialog) {
            TextField("Margin (mm)", text: $nestMargin)
            Button("Nest") {
                let margin = Double(nestMargin) ?? 5.0
                _ = session.nestSelectedShapes(margin: margin)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Arranges copies of the selected shapes (or all shapes) into the sheet with the guillotine nest engine.")
        }
        .alert("Tile", isPresented: $showTilingDialog) {
            TextField("Rows", text: $tilingRows)
            TextField("Columns", text: $tilingCols)
            TextField("Gap (mm)", text: $tilingGap)
            Button("Tile") {
                let rows = Int(tilingRows) ?? 2
                let cols = Int(tilingCols) ?? 3
                let gap = Double(tilingGap) ?? 2.0
                _ = session.generateTiling(tilesPerRow: cols, tilesPerColumn: rows, tileGap: gap)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Repeats the selected shapes (or all shapes) across the sheet in a rows × columns grid.")
        }
        .alert("Keyhole", isPresented: $showKeyholeDialog) {
            TextField("Screw head Ø (mm)", text: $keyholeHeadDia)
            TextField("Shaft Ø (mm)", text: $keyholeShaftDia)
            Button("Add Keyhole") { applyKeyhole() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds a keyhole-slot vector for wall-hanging mounts, ready for a profile cut.")
        }
        .alert("Set Size", isPresented: $showSetSizeDialog) {
            TextField("Width (mm)", text: $setSizeWidth)
            TextField("Height (mm)", text: $setSizeHeight)
            Toggle("Lock aspect ratio", isOn: $setSizePreserveAspect)
            Button("Set") { applySetSize() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scales the selection's bounding box to the exact width/height (center preserved).")
        }
        .alert("Add Text", isPresented: $showTextDialog) {
            TextField("Text", text: $textString)
            TextField("Font size (pt)", text: $textFontSize)
            TextField("Scale (mm per pt)", text: $textScale)
            Button("Add Text") { applyText() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Renders text as editable glyph curves — engrave it with V-Carve or Quick Engrave.")
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
            Button("Fillet…") { showFilletDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Round the corners of selected vectors")
            // SPK-1301 — dogbone corner relief (joinery): add relief circles
            // so a round bit reaches a rectangle pocket's square corners.
            Button("Dogbone…") { showDogboneDialog = true }
                .disabled(!session.hasSelectedRectangle)
                .help("Add dogbone corner-relief circles to the selected rectangle pocket (joinery)")
            Button("Extend…") { showExtendDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Extend the open ends of selected vectors")
            Button("Fit Curves") { _ = session.applyFitCurves() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Smooth selected vectors into curves — corners sharper than 60° survive")
            Button("Array…") { showArrayDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Copy the selection into a columns × rows grid")
            Button("Circular…") { showCircularDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Copy the selection around its center")
            Button("Nest…") { showNestDialog = true }
                .disabled(session.shapes.isEmpty)
                .help("Arrange copies of the selection (or all shapes) into the sheet with the guillotine nest engine")
            Button("Tile…") { showTilingDialog = true }
                .disabled(session.shapes.isEmpty)
                .help("Repeat the selection (or all shapes) across the sheet in a rows × columns grid")
            Button("Keyhole…") { showKeyholeDialog = true }
                .help("Add a keyhole-slot vector for wall-hanging mounts")
            Button("Text…") { showTextDialog = true }
                .help("Add text as editable vector glyphs (ready for V-Carve)")
            Button("Trace…") { session.traceBitmapFromPanel() }
                .help("Trace a bitmap image into vector paths")
            Button("Export DXF…") { exportDXF() }
                .disabled(session.shapes.isEmpty)
                .help("Export the design vectors as ASCII DXF (mm)")
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
            Button("Set Size…") { showSetSizeDialog = true }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Scale the selection's bounding box to an exact width/height")
            Button("Group ⌘G") { _ = session.applyGroup() }
                .disabled(session.selectedShapeIndices.count < 2)
                .help("Group selected vectors so they move, scale and rotate together")
            Button("Ungroup ⇧⌘G") { _ = session.applyUngroup() }
                .disabled(session.selectedShapeIndices.isEmpty)
                .help("Dissolve groups touching the selection")
            Divider().frame(height: 14)
            // SPK-0211+0212: Vector Preflight Doctor — run before Cut.
            // SPK-UI605: Import is opt-in once the canvas has geometry.
            Button("Import…") { showImportHub = true }
                .help("Import SVG / DXF into the current job")
            Button("Check Vectors") {
                _ = session.runPreflight()
                session.preflightPanelVisible = true
            }
            .help("Detect open vectors, self-intersections, degenerate shapes and gaps — with fix actions (before cutting)")
            Button("Validate All") {
                _ = session.runVectorValidation()
                showValidationPanel = true
            }
            .help("SPK-0806: run the expanded batch validator (topology/geometry/precision, fix actions) over every vector")
            Divider().frame(height: 14)
            // SPK-3D-spine-a: import an STL relief as a heightfield.
            Button("STL Relief…") { session.importSTLHeightfieldFromPanel() }
                .help("Import an ASCII STL model as a heightfield relief")
            // Tier-2 import breadth: OBJ / 3MF reliefs + EPS vectors.
            Button("OBJ Relief…") { session.importOBJHeightfieldFromPanel() }
                .help("Import an OBJ mesh as a heightfield relief")
            Button("3MF Relief…") { session.import3MFHeightfieldFromPanel() }
                .help("Import a 3MF model as a heightfield relief")
            Button("EPS…") { session.importEPSFromPanel() }
                .help("Import an EPS drawing as vectors")
            Button("PDF…") { session.importPDFFromPanel() }
                .help("Import a PDF's vector content streams as vectors")
            Button("AI…") { session.importAIFromPanel() }
                .help("Import an Illustrator file (EPS or PDF flavor) as vectors")
            Button("DWG…") { session.importDWGFromPanel() }
                .help("Import an R12 (AC1009) DWG as vectors (LINE/CIRCLE/ARC/POINT)")
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

    private func applyFillet() {
        let normalized = filletRadius.replacingOccurrences(of: ",", with: ".")
        guard let radius = Double(normalized), radius > 0 else {
            session.statusMessage = "Fillet: enter a positive radius"
            return
        }
        _ = session.applyFillet(radius: radius)
    }

    private func applyExtend() {
        let normalized = extendDistance.replacingOccurrences(of: ",", with: ".")
        guard let distance = Double(normalized), distance > 0 else {
            session.statusMessage = "Extend: enter a positive distance"
            return
        }
        _ = session.applyExtend(distance: distance)
    }

    private func applySetSize() {
        let w = setSizeWidth.replacingOccurrences(of: ",", with: ".")
        let h = setSizeHeight.replacingOccurrences(of: ",", with: ".")
        guard let width = Double(w), let height = Double(h), width > 0, height > 0 else {
            session.statusMessage = "Set Size: enter positive width and height"
            return
        }
        _ = session.applySetSize(width: width, height: height, preserveAspect: setSizePreserveAspect)
    }

    private func applyArrayCopy() {
        let cols = Int(arrayCols) ?? 0
        let rows = Int(arrayRows) ?? 0
        let sx = Double(arraySpacingX.replacingOccurrences(of: ",", with: ".")) ?? 0
        let sy = Double(arraySpacingY.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard cols > 0, rows > 0, sx > 0, sy > 0 else {
            session.statusMessage = "Array copy: positive columns, rows and spacing required"
            return
        }
        _ = session.applyArrayCopy(columns: cols, rows: rows, spacingX: sx, spacingY: sy)
    }

    private func applyCircularCopy() {
        let count = Int(circularCount) ?? 0
        guard count >= 2 else {
            session.statusMessage = "Circular copy: enter a count of at least 2"
            return
        }
        _ = session.applyCircularCopy(count: count, center: nil, rotateCopies: circularRotate)
    }

    private func applyKeyhole() {
        let head = Double(keyholeHeadDia.replacingOccurrences(of: ",", with: ".")) ?? 0
        let shaft = Double(keyholeShaftDia.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard head > 0, shaft > 0, shaft < head else {
            session.statusMessage = "Keyhole: shaft Ø must be smaller than the head Ø"
            return
        }
        _ = session.addKeyhole(screwHeadDiameterMm: head, shaftDiameterMm: shaft)
    }

    private func applyText() {
        let size = Double(textFontSize.replacingOccurrences(of: ",", with: ".")) ?? 0
        let scale = Double(textScale.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard size > 0, scale > 0 else {
            session.statusMessage = "Text: enter a positive font size and scale"
            return
        }
        _ = session.addText(text: textString, fontSizePoints: size, scaleMmPerPoint: scale)
    }

    private func exportDXF() {
        let panel = NSSavePanel()
        panel.title = "Export DXF"
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data]
        panel.nameFieldStringValue = "design.dxf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = session.exportDXF(to: url)
    }
}

private struct CutStageView: View {
    @ObservedObject var session: AppSession

    /// SPK-1201 — which cut overview is shown in the left pane.
    private enum CutViewMode: String, CaseIterable, Identifiable {
        case layers
        case tree
        var id: String { rawValue }
    }

    /// Blocker instance whose expert override is confirmed via the dirty-toolpath alert.
    @State private var exportBlocker: ExportBlocker?
    @State private var showExportBlockAlert = false
    /// SPK-1134 — post template applied on Save Toolpaths (nil = legacy post).
    @State private var selectedPostTemplateID: String = "grbl-mm"
    /// SPK-1000 — Post Studio sheet (template editor + variable blocks).
    @State private var showPostStudio = false
    /// SPK-1201 — cut overview mode: Layers table (default) or Tree.
    @State private var cutLayersViewMode: CutViewMode = .layers
    @State private var exportBlockMessage = ""

    /// Toolpath preflight gate (SPK-FM-R013): error issues block save with a
    /// plain-English CTA before the NSSavePanel opens.
    @State private var toolpathPreflightIssues: [ToolpathPreflightIssue] = []
    @State private var showToolpathPreflightAlert = false
    /// SPK-1133 — selected tool in the grouped tool browser (left pane).
    @State private var selectedBrowserToolID: UUID?
    /// SPK-0803 — array-copy dialogs (linear row / circular ring).
    @State private var showArrayCopyDialog = false
    @State private var arrayCopyCount = "3"
    @State private var arrayCopySpacing = "20.0"
    @State private var showCircularArrayDialog = false
    @State private var circularCount = "6"
    @State private var circularRadius = "50.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cut")
                    .font(SP.Typography.stageTitle)
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
                    Button("Drill Bank") { session.generateDrillBankToolpath() }
                        .help("A W×H grid of uniquely-numbered holes (through or brad-point)")
                    Button("V-Carve") { session.generateVCarveToolpath() }
                        .help("Engrave vectors with a V-bit")
                    Divider()
                    Button("Wrapped Fluting") { session.generateWrappedFluting() }
                        .help("Flute lines around the rotary axis (X axial, Y wraps to A degrees)")
                    // SPK-0900/0802 lean slices: specialty strategies.
                    Button("Prism") { session.generatePrismToolpath() }
                        .help("Parallel V-grooves across closed vectors (prismatic sign effect)")
                    Button("Fluting") { session.generateFlutingToolpath() }
                        .help("Grooves along the selected vectors (draw parallel lines for a ribbed board)")
                    Button("Chamfer") { session.generateChamferToolpath() }
                        .help("V-bevel the selected edges")
                    Button("Inlay Pocket") { session.generateInlayToolpath(variant: .pocket) }
                        .help("Female half of a V-inlay: flat-bottom recess with sloped walls")
                    Button("Inlay Plug") { session.generateInlayToolpath(variant: .plug) }
                        .help("Male half of a V-inlay: cut around the shape at inlay depth")
                    Button("Quick Engrave") { session.generateQuickEngraveToolpath() }
                        .help("Single-pass V-bit engraving along vectors — fast sign lettering")
                    Button("Drag Knife") { session.generateDragKnifeToolpath() }
                        .help("Blade-offset cutting with corner pivots (drag knife)")
                    Button("Photo V-Carve") { session.generatePhotoVCarveToolpath() }
                        .help("Fine V-bit raster over the imported image/STL relief (brightness → depth)")
                    Button("Sketch Carve") { session.generateSketchCarveToolpath() }
                        .help("Edge-gated V-bit raster — only strong brightness transitions carve (sketch look)")
                    Button("Texture") { session.generateTextureToolpath() }
                        .help("Parallel or crosshatch grooves clipped inside closed vectors")
                    Button("Rotary Wrap") { session.generateRotaryWrapToolpath() }
                        .help("Wrap the selected vectors around a rotary axis (X → A degrees, Y stays axial)")
                    Button("Thread Mill") { session.generateThreadMillingToolpath() }
                        .help("Cut a thread inside the selected closed vector with one helical pass (real G2 helix)")
                    Divider()
                    // SPK-0803 — array-copy + merge the selected operation's G-code.
                    Button("Array Copy…") { showArrayCopyDialog = true }
                        .help("Copy the selected toolpath operation in a linear row (real G-code transform)")
                    Button("Circular Array…") { showCircularArrayDialog = true }
                        .help("Copy the selected toolpath operation around a circle")
                    Button("Merge All Ops") { session.generateMergedToolpath() }
                        .help("Concatenate every computed operation into one program (markers preserved)")
                    Divider()
                    // SPK-3D-spine-b: relief strategies (need an imported STL).
                    Button("Rough 3D") { session.generateRough3DToolpath() }
                        .help("Z-level rough the imported STL relief (needs a relief)")
                    Button("Finish 3D") { session.generateFinish3DToolpath() }
                        .help("Surface-following finish of the imported STL relief (needs a relief)")
                    Button("Rest Machine") { session.generateRestMachiningToolpath() }
                        .help("Clear leftover material the rough pass left behind (needs a relief)")
                } label: {
                    Label("Add Toolpath", systemImage: "plus.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)

                // SPK-0319 lite: optional Follow-source link mode (default
                // OFF). When ON, editing vectors marks linked toolpaths dirty
                // (export blocks; recalc badge counts) — never a silent recalc.
                Toggle("Follow Source", isOn: Binding(
                    get: { session.linkManager.followSourceMode == .autoFollow },
                    set: { session.setFollowSourceMode($0 ? .autoFollow : .manual) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("When ON: editing vectors marks linked toolpaths dirty instead of silently recalculating")
                if session.linkManager.hasStaleToolpaths {
                    Text("\(session.linkManager.staleToolpathIds.count) stale")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Linked toolpaths need recalculation after the art edit")
                }

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
                Button {
                    exportJobSheet()
                } label: {
                    Label("Job Sheet…", systemImage: "doc.text")
                }
                .help("Export an A4 HTML job sheet (rendered to PDF) with job, tool and toolpath details")
                // SPK-1000 — Post Studio: manage user post templates + the
                // document-variable blocks they resolve at export.
                Button {
                    showPostStudio = true
                } label: {
                    Label("Post Studio…", systemImage: "text.badge.plus")
                }
                .help("Create and edit post templates with $variable blocks")
                // SPK-1008 — multi-file job queue: enqueue the current cut
                // plan as one program in the sequential run queue.
                Button {
                    let gcode = session.allToolpathGCode
                    guard !gcode.isEmpty else {
                        session.statusMessage = "Queue: no G-code to enqueue — generate toolpaths first"
                        return
                    }
                    session.jobQueue.enqueue(name: session.job.name, gcode: gcode)
                    session.statusMessage = "Queued “\(session.job.name)” (\(gcode.count) lines) — \(session.jobQueue.programs.count) program(s) in queue"
                } label: {
                    Label("Enqueue", systemImage: "list.number")
                }
                .help("Add the current cut plan to the multi-file run queue")
            }

            HSplitView {
                VStack(spacing: 0) {
                    // SPK-1201 — Cut-Layers table is the primary overview;
                    // the tree stays for grouping/params. Toggle between them.
                    Picker("View", selection: $cutLayersViewMode) {
                        Text("Layers").tag(CutViewMode.layers)
                        Text("Tree").tag(CutViewMode.tree)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    if cutLayersViewMode == .layers {
                        CutLayersTableView(session: session)
                            .frame(minWidth: 200, idealWidth: 280, maxWidth: 340)
                    } else {
                        ToolpathTreeView(session: session)
                            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    }
                    Divider()
                    // SPK-1133: tool browser grouped by class (left pane).
                    ToolBrowserView(
                        database: session.toolDatabase,
                        selectedToolID: $selectedBrowserToolID
                    )
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300, minHeight: 140, maxHeight: 220)
                    Divider()
                    // SPK-0308: keep-out zone management (create/edit/toggle).
                    KeepOutZonesPanel(session: session)
                    Divider()
                    // SPK-1008: multi-file job queue (sequential programs).
                    JobQueuePanelView(session: session)
                    Divider()
                    // SPK-1006 loadable ABI: discovered plugins (sample
                    // dot-grid engrave ships in fixtures; users drop their
                    // own plugin dirs into Application Support/ShopPilot/Plugins).
                    PluginsPanelView(session: session)
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
        .alert(
            "Toolpath preflight — this cut needs attention",
            isPresented: $showToolpathPreflightAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Warn Only") {
                for issue in toolpathPreflightIssues {
                    session.dismissPunchThrough(nodeID: issue.nodeID)
                }
            }
            if toolpathPreflightIssues.contains(where: { $0.fix.isFlatDepthFix }) {
                Button("Set Flat Depth") {
                    for issue in toolpathPreflightIssues {
                        session.applyFlatDepthFix(nodeID: issue.nodeID)
                    }
                }
            }
            if toolpathPreflightIssues.contains(where: { $0.fix.isAddTabsFix }) {
                Button("Add Tabs") {
                    for issue in toolpathPreflightIssues {
                        session.applyAddTabsFix(nodeID: issue.nodeID)
                    }
                }
            }
            if toolpathPreflightIssues.contains(where: { $0.fix.isUseMeasuredValueFix }) {
                Button("Use Measured Value") {
                    session.applyMeasuredThickness()
                }
            }
            if toolpathPreflightIssues.contains(where: { $0.fix.isSplitFilesFix }) {
                Button("Split to Multiple Files") {
                    splitToolpaths()
                }
            }
        } message: {
            Text(toolpathPreflightMessage)
        }
        .alert("Linear Array Copy", isPresented: $showArrayCopyDialog) {
            TextField("Copies", text: $arrayCopyCount)
            TextField("Spacing (mm)", text: $arrayCopySpacing)
            Button("Copy") {
                let count = Int(arrayCopyCount) ?? 3
                let spacing = Double(arrayCopySpacing) ?? 20.0
                _ = session.generateArrayCopyToolpath(count: count, spacing: spacing, angle: 0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copy the selected operation's G-code in a row along X. Select an operation in the tree first.")
        }
        .alert("Circular Array Copy", isPresented: $showCircularArrayDialog) {
            TextField("Copies", text: $circularCount)
            TextField("Radius (mm)", text: $circularRadius)
            Button("Copy") {
                let count = Int(circularCount) ?? 6
                let radius = Double(circularRadius) ?? 50.0
                let sheet = session.activeSheet
                let cx = (sheet?.width ?? 600) / 2
                let cy = (sheet?.depth ?? 400) / 2
                _ = session.generateCircularArrayCopyToolpath(count: count, radius: radius,
                                                              centerX: cx, centerY: cy)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copy the selected operation's G-code around the sheet center. Select an operation in the tree first.")
        }
        .sheet(isPresented: $showPostStudio) {
            PostStudioView(session: session)
                .frame(width: 640, height: 560)
        }
    }

    /// Plain-English summary of the blocking toolpath preflight issues.
    private var toolpathPreflightMessage: String {
        toolpathPreflightIssues.map { "• \($0.message)" }.joined(separator: "\n")
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

        if !result.isValid {
            exportBlocker = blocker
            exportBlockMessage = "Recalculate before saving: \(result.dirtyNodes.joined(separator: ", "))"
            showExportBlockAlert = true
            return
        }

        // SPK-FM-R013: toolpath preflight rules run after the dirty gate and
        // before the save panel — error issues (e.g. V-Carve punch-through)
        // block with a plain-English CTA.
        let preflight = session.exportPreflightIssues()
        if !preflight.isEmpty {
            toolpathPreflightIssues = preflight
            showToolpathPreflightAlert = true
            return
        }

        saveToolpaths()
    }

    /// Present the save panel, post-process the session G-code through
    /// CutToMachineBridge (optionally through the SPK-1134 post template
    /// selected in the post picker), and write the GRBL file to the URL.
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

        // SPK-1134 + SPK-1000: post picker accessory — choose the post
        // template applied on export (shipped GRBL set + user Post Studio
        // templates). The accessory also carries a summary of each template.
        let postPicker = PostTemplatePickerView(
            templates: session.postTemplateStore.allTemplates,
            selectedID: selectedPostTemplateID
        ) { id in
            selectedPostTemplateID = id
        }
        let accessory = NSHostingView(rootView: postPicker)
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return // User cancelled
        }

        do {
            let postTemplate = session.postTemplateStore.template(byID: selectedPostTemplateID)
            let result = try CutToMachineBridge.export(
                gcodeLines: gcode,
                toolInfo: nil,
                machineProfile: activeMachineProfile,
                fileName: destinationURL.deletingPathExtension().lastPathComponent,
                postTemplate: postTemplate,
                postVariables: session.postTemplateVariables
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

    /// SPK-1135 — export the job sheet: fill the bundled A4 HTML template
    /// from the live document, render it to PDF via WebKit's `createPDF`,
    /// and write it where the user chose. Falls back to writing the HTML
    /// file itself if the PDF render fails.
    @MainActor
    private func exportJobSheet() {
        let html = session.jobSheetHTML()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(sanitizedFileName(session.job.name))-job-sheet.pdf"
        panel.canCreateDirectories = true
        panel.title = "Export Job Sheet"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        webView.loadHTMLString(html, baseURL: nil)

        // createPDF(configuration:) is async; give the page a moment to lay
        // out, then render. Use a small poll for the document to finish
        // loading so the table/CSS is present in the render.
        Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                let pdfData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    webView.createPDF(configuration: WKPDFConfiguration()) { result in
                        switch result {
                        case .success(let data): cont.resume(returning: data)
                        case .failure(let error): cont.resume(throwing: error)
                        }
                    }
                }
                try pdfData.write(to: destinationURL, options: .atomic)
                session.statusMessage = "Job sheet saved to \(destinationURL.lastPathComponent)"
            } catch {
                // Honest fallback: write the HTML so the sheet is never lost.
                do {
                    try html.write(to: destinationURL.deletingPathExtension().appendingPathExtension("html"), atomically: true, encoding: .utf8)
                    session.statusMessage = "PDF render failed — saved \(destinationURL.deletingPathExtension().lastPathComponent).html instead"
                } catch {
                    session.statusMessage = "Job sheet export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// R019 split CTA: write each per-tool G-code group as its own
    /// post-processed file (`<base>-<n>-<tool>.gcode`) in the destination
    /// folder, in tree order. One save panel seeds the folder + base name.
    private func splitToolpaths() {
        let groups = session.toolpathGroupsByTool()
        guard !groups.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "job-\(sanitizedFileName(groups[0].toolName)).gcode"
        panel.canCreateDirectories = true
        panel.title = "Split Toolpaths (first file)"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        let directory = destinationURL.deletingLastPathComponent()
        let base = destinationURL.deletingPathExtension().lastPathComponent

        var written = 0
        for (index, group) in groups.enumerated() {
            let fileName = "\(base)-\(index + 1)-\(sanitizedFileName(group.toolName)).gcode"
            let destination = directory.appendingPathComponent(fileName)
            do {
                let result = try CutToMachineBridge.export(
                    gcodeLines: group.gcode,
                    toolInfo: nil,
                    machineProfile: activeMachineProfile,
                    fileName: fileName
                )
                if let errorMessage = result.errorMessage {
                    session.statusMessage = "Split failed: \(errorMessage)"
                    return
                }
                guard let exportedURL = result.outputFileURL else {
                    session.statusMessage = "Split failed: bridge produced no output"
                    return
                }
                let data = try Data(contentsOf: exportedURL)
                try data.write(to: destination, options: .atomic)
                written += 1
            } catch {
                session.statusMessage = "Split failed: \(error.localizedDescription)"
                return
            }
        }
        session.statusMessage = "Split into \(written) ordered per-tool file(s) in \(directory.lastPathComponent)"
        session.lastToolpathSummary = "\(written) per-tool file(s) written"
    }

    /// Filesystem-safe token for tool names in split file names.
    private func sanitizedFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "tool" : cleaned
    }

    /// Machine profile used to post-process exported G-code (SPK-0415): the
    /// active profile from the persisted store auto-selects the post type
    /// (GRBL vs Universal) and units (G21 vs G20); falls back to the GRBL
    /// simulator profile when the store is empty.
    private var activeMachineProfile: MachineProfile {
        session.machineProfiles.profiles.first ?? MachineProfile.simulatorProfile
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
                        ProfileParamsForm(node: node, variables: session.docVars.variables) { newParams in
                            _ = session.applyProfileParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136b: Pocket strategy form — installer-verified §M fields.
                if node.isPocketOperation {
                    ScrollView {
                        PocketParamsForm(node: node, variables: session.docVars.variables) { newParams in
                            _ = session.applyPocketParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136c: Drill strategy form — installer-verified §N fields.
                if node.isDrillOperation {
                    ScrollView {
                        DrillParamsForm(node: node, variables: session.docVars.variables) { newParams in
                            _ = session.applyDrillParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-1136d: V-Carve strategy form — installer-verified §O fields.
                if node.isVCarveOperation {
                    ScrollView {
                        VCarveParamsForm(node: node, variables: session.docVars.variables) { newParams in
                            _ = session.applyVCarveParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0900: Prism strategy form.
                if node.strategyKind == .prism {
                    ScrollView {
                        PrismParamsForm(node: node) { newParams in
                            _ = session.applyPrismParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0900: Fluting strategy form.
                if node.strategyKind == .fluting {
                    ScrollView {
                        FlutingParamsForm(node: node) { newParams in
                            _ = session.applyFlutingParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0900: Chamfer strategy form.
                if node.strategyKind == .chamfer {
                    ScrollView {
                        ChamferParamsForm(node: node) { newParams in
                            _ = session.applyChamferParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0802: Inlay strategy form.
                if node.strategyKind == .inlay {
                    ScrollView {
                        InlayParamsForm(node: node) { newParams in
                            _ = session.applyInlayParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // F07: Quick Engrave strategy form.
                if node.strategyKind == .quickEngrave {
                    ScrollView {
                        QuickEngraveParamsForm(node: node) { newParams in
                            _ = session.applyQuickEngraveParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0901: Photo V-Carve strategy form.
                if node.strategyKind == .photoVCarve {
                    ScrollView {
                        PhotoVCarveParamsForm(node: node) { newParams in
                            _ = session.applyPhotoVCarveParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0907: Drag Knife strategy form.
                if node.strategyKind == .dragKnife {
                    ScrollView {
                        DragKnifeParamsForm(node: node) { newParams in
                            _ = session.applyDragKnifeParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0900: Texture strategy form.
                if node.strategyKind == .texture {
                    ScrollView {
                        TextureParamsForm(node: node) { newParams in
                            _ = session.applyTextureParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0901: Sketch Carve strategy form.
                if node.strategyKind == .sketchCarve {
                    ScrollView {
                        SketchCarveParamsForm(node: node) { newParams in
                            _ = session.applySketchCarveParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0904: Rotary Wrap strategy form.
                if node.strategyKind == .rotaryWrap {
                    ScrollView {
                        RotaryWrapParamsForm(node: node) { newParams in
                            _ = session.applyRotaryWrapParams(newParams, to: node.id)
                        }
                    }
                    .frame(maxHeight: 320)
                }

                // SPK-0902: Thread Mill strategy form.
                if node.strategyKind == .threadMill {
                    ScrollView {
                        ThreadMillParamsForm(node: node) { newParams in
                            _ = session.applyThreadMillParams(newParams, to: node.id)
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
    /// SPK-0209 — document variables available to calculation edit boxes.
    let variables: [DocumentVariable]
    /// SPK-0209 — last expression error (shown under the form).
    @State private var calcMessage = ""

    init(node: ToolpathTreeNode, variables: [DocumentVariable], onApply: @escaping (ProfileToolpathParams) -> Void) {
        self.node = node
        self.variables = variables
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
                    // SPK-UI603c: disambiguate from engine depth/Z pass count in the summary.
                    Text("Finish passes = cleanup cuts. Depth/Z passes come from stock ÷ depth/pass.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .labelsHidden()
            }

            GroupBox("Feeds & depth") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    numRow("Feed (mm/min)", $params.feedRateMmPerMin)
                    numRow("Plunge (mm/min)", $params.plungeFeedRateMmPerMin)
                    calcRow("Depth/pass (mm)", $params.maxDepthOfCutMm, variables: variables, $calcMessage)
                    calcRow("Tool Ø (mm)", $params.toolDiameterMm, variables: variables, $calcMessage)
                }
                if !calcMessage.isEmpty {
                    Text(calcMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
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

    /// SPK-0209 — calculation edit box: the user may type a plain number OR
    /// an expression (`2*pi*r`, `$width/2`, `sheetWidth*0.75`). On commit the
    /// expression resolves against the document variables; invalid input
    /// leaves the binding untouched and flags a message.
    private func calcRow(
        _ label: String,
        _ value: Binding<Double>,
        variables: [DocumentVariable],
        _ message: Binding<String>
    ) -> some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(
                "",
                text: Binding(
                    get: { String(format: "%.3f", value.wrappedValue) },
                    set: { newText in
                        let trimmed = newText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        // Plain number → commit directly.
                        if let plain = Double(trimmed) {
                            value.wrappedValue = plain
                            return
                        }
                        // Expression → resolve; only commit when valid.
                        if let resolved = ExpressionCalculator.evaluate(trimmed, variables: variables) {
                            value.wrappedValue = resolved
                        } else {
                            message.wrappedValue = "Invalid expression: \(trimmed)"
                        }
                    }
                )
            )
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        }
    }
}

// MARK: - Pocket strategy form (SPK-1136b)

/// SPK-1001 — calculation edit row shared by the strategy forms: plain
/// number OR an expression (`2*pi*r`, `$width/2`) resolved against the
/// document variables on commit (same contract as SPK-0209's Profile calcRow).
private struct DocVarCalcRow: View {
    let label: String
    @Binding var value: Double
    let variables: [DocumentVariable]
    @Binding var message: String

    var body: some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(
                "",
                text: Binding(
                    get: { String(format: "%.3f", value) },
                    set: { newText in
                        let trimmed = newText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        if let plain = Double(trimmed) {
                            value = plain
                            return
                        }
                        if let resolved = ExpressionCalculator.evaluate(trimmed, variables: variables) {
                            value = resolved
                        } else {
                            message = "Invalid expression: \(trimmed)"
                        }
                    }
                )
            )
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        }
    }
}

/// Editable form for the installer-verified §M Pocket field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine.
private struct PocketParamsForm: View {
    let node: ToolpathTreeNode
    let variables: [DocumentVariable]
    let onApply: (PocketToolpathParams) -> Void

    @State private var params: PocketToolpathParams
    @State private var calcMessage = ""

    init(node: ToolpathTreeNode, variables: [DocumentVariable] = [],
         onApply: @escaping (PocketToolpathParams) -> Void) {
        self.node = node
        self.variables = variables
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
                    DocVarCalcRow(label: "Depth/pass (mm)", value: $params.maxDepthOfCutMm,
                                  variables: variables, message: $calcMessage)
                    numRow("Pocket allowance (mm)", $params.allowanceMm)
                    numRow("Safe Z (mm)", $params.safetyHeightMm)
                }
                if !calcMessage.isEmpty {
                    Text(calcMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
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
    let variables: [DocumentVariable]
    let onApply: (DrillToolpathParams) -> Void

    @State private var params: DrillToolpathParams
    @State private var calcMessage = ""

    init(node: ToolpathTreeNode, variables: [DocumentVariable] = [],
         onApply: @escaping (DrillToolpathParams) -> Void) {
        self.node = node
        self.variables = variables
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
                    DocVarCalcRow(label: "Cut depth (mm)", value: $params.cutDepthMm,
                                  variables: variables, message: $calcMessage)
                    numRow("Peck depth (mm)", $params.peckDepthMm)
                }
                if !calcMessage.isEmpty {
                    Text(calcMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
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
    let variables: [DocumentVariable]
    let onApply: (VCarveParams) -> Void

    @State private var params: VCarveParams
    @State private var calcMessage = ""

    init(node: ToolpathTreeNode, variables: [DocumentVariable] = [],
         onApply: @escaping (VCarveParams) -> Void) {
        self.node = node
        self.variables = variables
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
                    DocVarCalcRow(label: "Cut depth (mm)", value: $params.maxDepthOfCutMm,
                                  variables: variables, message: $calcMessage)
                }
                if !calcMessage.isEmpty {
                    Text(calcMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
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


// MARK: - Post Template Picker (SPK-1134)

/// Save-panel accessory: pick which post template the export runs through
/// (GRBL mm / GRBL inch / GRBL rotary wrap Y2A) or the legacy post. Shows a
/// summary line per template.
struct PostTemplatePickerView: View {
    let templates: [PostTemplate]
    @Binding var selectedID: String
    let onSelect: (String) -> Void

    init(templates: [PostTemplate], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.templates = templates
        self._selectedID = Binding(get: { selectedID }, set: { onSelect($0) })
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Post Processor")
                .font(.headline)
            Picker("Post", selection: $selectedID) {
                Text("Legacy (GRBL wrapper)").tag("")
                ForEach(templates) { template in
                    Text(template.name).tag(template.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if let template = templates.first(where: { $0.id == selectedID }) {
                Text(template.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Legacy GRBL post — header, G21/G20 from the machine profile, moves, M2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 400, alignment: .leading)
    }
}
