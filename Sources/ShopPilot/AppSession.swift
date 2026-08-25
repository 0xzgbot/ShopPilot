import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ShopPilotCore
import ShopPilotGeometry
import ShopPilotSerial

/// Shared document + toolpath session for the main window.
///
/// AppSession is the single source of truth for the open document:
/// it owns the `Job` (and its sheets/layers), the design `shapes` and derived
/// `vectors` list, the `toolpathTree` (toolpaths list), the current `selection`,
/// the `isDirty` flag, and the undo/redo stack hooks. Stages read from this
/// object instead of keeping parallel ad-hoc state.
@MainActor
final class AppSession: ObservableObject, AutosaveSessionLike, SampleLoadingSession, SnapshotSession, ProfileGeneratingSession, FixtureLoadingSession {
    @Published var selectedStage: Stage = .setup
    /// Active Design-stage create tool — lifted from the canvas so the left
    /// tool palette and the canvas share one source of truth.
    @Published var designTool: CanvasCreateTool = .select
    @Published var job: Job
    @Published var shapes: [VectorShape] = []

    /// Per-shape layer membership, index-aligned with `shapes` (SPK-1137).
    /// Kept in lockstep by every shape mutation so the canvas can honor each
    /// layer's hide/lock and save/open can keep each layer's own vectors.
    /// Internal setter: `SnapshotSession` conformance (SPK-1403b) restores
    /// layer ids on undo.
    @Published var shapeLayerIDs: [UUID] = []
    @Published var gcodeLines: [String] = []
    @Published var lastToolpathSummary: String = "No toolpath generated"
    @Published var statusMessage: String = "Ready"
    @Published var showCommandPalette = false
    @Published var showSafetyDisclaimer = true
    @Published var safetyAccepted = false

    /// App-lifetime owner of the transport, streamer and machine session. Held
    /// here rather than by the Machine stage so a connection — and the window
    /// chrome's Hold / Resume / Reset — survives switching stages.
    let machine = MachineController()

    /// Toolpath operations tree — the session-owned toolpaths list.
    @Published var toolpathTree = ToolpathTreeManager()

    /// All G-code from every computed toolpath node in the tree, in tree order
    /// (concatenated). Falls back to the single-op `gcodeLines` when the tree
    /// has no computed results yet.
    var allToolpathGCode: [String] {
        let nodeLines = toolpathTree.allNodes
            .filter { $0.toolpathResult != nil }
            .flatMap { node -> [String] in
                (node.toolpathResult ?? "")
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        return nodeLines.isEmpty ? gcodeLines : nodeLines
    }

    /// SPK-1210 — per-node wireframe segments: each operation node's G-code
    /// rendered to segments keyed by node id. The Preview canvas uses this
    /// to highlight exactly one op when its Cut row is hovered.
    var segmentsByToolpathNode: [UUID: [(start: (x: Double, y: Double),
                                          end: (x: Double, y: Double),
                                          isRapid: Bool)]] {
        var map: [UUID: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]] = [:]
        for node in toolpathTree.allNodes where node.toolpathResult != nil {
            let lines = (node.toolpathResult ?? "")
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let segs = WireframeRenderer.generateSegments(from: lines)
            if !segs.isEmpty {
                map[node.id] = segs
            }
        }
        return map
    }

    /// SPK-0315 — G-code of the DIRTY operation nodes only (the partial-resim
    /// line set). Empty when nothing is dirty.
    var dirtyToolpathGCode: [String] {
        toolpathTree.root.allDirtyNodes
            .filter { $0.toolpathResult != nil }
            .flatMap { node -> [String] in
                (node.toolpathResult ?? "")
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
    }

    /// SPK-0315 — dirty-region tracker for selective resimulation. Views mark
    /// regions via `markVectorModified`/`markFullTreeDirty`; the Preview stage
    /// runs `performResimulation(partialLines:fullLines:…)` and renders the
    /// delta when the change was partial.
    let dirtyRegionManager = DirtyRegionManager()

    /// SPK-1700c — the cutter radius the material sim should stamp with:
    /// the largest assigned tool's diameter/2 across the toolpath tree
    /// (nil when no tool is assigned → the simulator's documented 1.5mm
    /// fallback). Resolved from the tool DATABASE, not parsed params.
    var previewToolRadiusMm: Double? {
        let diameters = toolpathTree.allNodes.compactMap { node -> Double? in
            guard let toolID = node.toolID else { return nil }
            return toolDatabase.tool(withID: toolID)?.diameter
        }
        return diameters.max().map { $0 / 2 }
    }

    /// Session tool database — the tool picker reads and assigns from here.
    @Published var toolDatabase = ToolDatabase()

    /// SPK-1133b — machine profile name used to resolve per-machine cut data
    /// during recalc (nil = no machine override; material cut-data applies).
    /// Wired by the machine stage when a profile is active.
    @Published var activeMachineName: String? = nil

    /// Current selection (vector path IDs) — session-owned, not view-local.
    @Published var selectedVectorIDs: Set<UUID> = []

    /// Design-canvas selection: indices into `shapes` (session-owned so the
    /// canvas and the ops toolbar share one selection state).
    @Published var selectedShapeIndices: Set<Int> = []

    /// UI-polish cluster — vector groups as index lists into `shapes`
    /// (mirrors `Job.shapeGroups` for the live document). Transforms expand
    /// the selection to group members so grouped vectors move together.
    @Published var shapeGroups: [[Int]] = []

    /// UI-polish cluster — canvas visibility chips (Vec / Keep-outs /
    /// Toolpaths / Bitmaps). Persisted in UserDefaults, not the document.
    @Published var canvasOverlays: CanvasOverlayOptions = .all

    /// Selection expanded to whole groups: when any member of a group is
    /// selected, every member is included in transforms (UI-polish cluster).
    var expandedSelectionIndices: Set<Int> {
        ShapeGroupEngine.expandedSelection(
            selected: selectedShapeIndices,
            groups: shapeGroups
        )
    }

    /// SPK-0211+0212 — last vector preflight report (nil until first run).
    @Published var lastPreflightReport: PreflightReport?

    /// SPK-0806 — last expanded vector validation batch (nil until first run).
    @Published var lastVectorValidation: BatchVectorValidationResult?

    /// SPK-0604 — true when the V-Carve preflight gate has blocked a carve and
    /// routed to Design; the Design panel auto-opens to show the fix CTAs.
    @Published var preflightPanelVisible = false

    /// SPK-0319 lite — optional Follow-source link mode (default OFF/manual).
    /// When ON, art edits mark linked toolpaths stale + dirty (export blocks,
    /// recalc badge counts them) — never a silent recalc.
    @Published var linkManager = ToolpathLinkManager()

    /// SPK-0415 — machine profiles persisted in UserDefaults; the active
    /// profile's machine type + units auto-select the post processor
    /// (GRBL vs Universal, G21 vs G20) at export.
    let machineProfiles = MachineProfileStore()

    /// SPK-1000 — Post Studio: shipped + user post templates persisted in
    /// UserDefaults, with document-variable blocks at export.
    let postTemplateStore = PostTemplateStore()

    /// SPK-1008 — multi-file job queue + network bridge store.
    let jobQueue = JobQueue()
    let networkBridgeStore = NetworkBridgeStore()

    /// SPK-1209 — recent imports for the Import hub rail.
    let recentFilesStore = RecentFilesStore()

    /// SPK-1006 loadable ABI — discovered plugins (Application Support +
    /// bundled sample plugin).
    lazy var pluginStore: PluginStore = {
        var dirs = PluginStore.appSearchDirectories()
        // Repo-dev: also discover the bundled sample plugin from fixtures.
        let repoPlugins = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("fixtures/plugins")
        if FileManager.default.fileExists(atPath: repoPlugins.path) {
            dirs.append(repoPlugins)
        }
        return PluginStore(searchDirectories: dirs)
    }()

    /// Document variables for post-template blocks (SPK-1000): filled from
    /// the live document so `$jobName` / `$sheetWidth` style tokens in a
    /// user template resolve at export.
    var postTemplateVariables: [String: String] {
        var vars: [String: String] = [:]
        vars["jobName"] = job.name
        if let sheet = activeSheet {
            vars["sheetWidth"] = String(format: "%.1f", sheet.width)
            vars["sheetDepth"] = String(format: "%.1f", sheet.depth)
            vars["sheetHeight"] = String(format: "%.1f", sheet.height)
            vars["materialName"] = sheet.material?.name ?? ""
        }
        if let node = selectedOperationNode, let toolID = node.toolID,
           let tool = toolDatabase.tool(withID: toolID) {
            vars["toolName"] = tool.name
            vars["feedRate"] = String(format: "%.0f", node.paramFeedRate ?? 0)
            vars["spindleRpm"] = String(format: "%.0f", node.paramSpindleRpm ?? 0)
        }
        return vars
    }

    /// Inspector/browser selection type (job, sheet, layer, toolpath).
    @Published var selection: SelectionType = .none

    /// Currently selected toolpath tree node id (nil = none).
    /// The toolpath tree UI mirrors this; the inspector reads it too.
    @Published var selectedToolpathID: UUID?
    /// SPK-1210 — the toolpath row currently hovered in the Cut overview;
    /// the Preview canvas highlights exactly its segments.
    @Published var hoveredToolpathID: UUID?

    /// Whether the document has unsaved changes.
    @Published private(set) var isDirty = false
    /// SPK-1314 — a background recalc is in flight (UI shows a spinner).
    @Published var isRecalculating = false
    /// SPK-UI-BUG-03 — a single-op Cut generate is computing off the main
    /// thread (UI shows a spinner + disables the generate buttons).
    @Published var isGeneratingToolpath = false

    /// Undo/redo stack hooks for document mutations.
    let undoManager = UndoManager()

    let docVars = DocumentVariablesModel()

    /// SPK-0808 — production golden job runs against the real engines.
    let goldenJobManager = ProductionGoldenJobManager()

    /// SPK-0705 — interactive shape handles for 3D components.
    let handleManager = ShapeHandleManager()

    /// SPK-0707 — STL import orientation wizard state.
    @Published var stlImportURL: URL?
    @Published var showSTLOrientationWizard = false
    @Published var stlConfig = STLImportConfig()

    /// SPK-0707 — Import the STL at the wizard URL using the current config.
    func importSTLWithConfig() {
        guard let url = stlImportURL else { return }
        do {
            let result = try importSTLHeightfield(from: url)
            selectedStage = .model
            if result.success, let hf = result.heightfield {
                statusMessage = "STL relief: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
            } else {
                statusMessage = "STL import failed: \(result.errorMessage ?? "unknown error")"
            }
        } catch {
            statusMessage = "STL import failed: \(error.localizedDescription)"
        }
    }

    /// Last saved/opened package URL (if any).
    /// Internal setter: `SampleLoadingSession` conformance lets the sample
    /// loader clear it (SPK-1403a).
    var packageURL: URL?

    private let documentSaver = DocumentSaver()
    private let documentLoader = DocumentLoader()

    enum SelectionType: Equatable {
        case none
        case job
        case sheet(UUID)
        case layer(UUID)
        case toolpath(UUID)
    }

    // MARK: - Autosave (SPK-1402a)

    /// The running Autosaver for the current document. Started at launch and
    /// restarted whenever the document is replaced (open / sample / recipe),
    /// so recovery files always follow the current job.
    private(set) var autosaver: Autosaver?

    /// Newest autosave snapshot found at launch, if any — the surface a
    /// launch-time "Recover unsaved work?" offer reads.
    private(set) var pendingRecovery: RecoverySnapshot?

    /// Start (or restart) autosaving the current job into the recovery
    /// directory.
    private func startAutosaverForCurrentJob() {
        autosaver?.stop()
        autosaver = RecoveryCoordinator.startAutosaver(for: self)
    }

    /// Load the pending autosave (if any) into the session and clear the
    /// artifact — the accepting action behind "Recover unsaved work?".
    /// Returns false when there is nothing to recover.
    @discardableResult
    func recoverFromPendingAutosave() throws -> Bool {
        guard let snapshot = pendingRecovery else { return false }
        try openPackage(from: snapshot.url)
        try? FileManager.default.removeItem(at: snapshot.url)
        pendingRecovery = nil
        return true
    }

    /// Dismiss the recovery offer WITHOUT loading: clear the pending snapshot
    /// and remove the artifact, so launch never offers the same file again.
    /// The accepting action behind "Discard" in the recovery sheet (SPK-1402d).
    func discardPendingRecovery() {
        guard let snapshot = pendingRecovery else { return }
        try? FileManager.default.removeItem(at: snapshot.url)
        pendingRecovery = nil
    }

    // AutosaveSessionLike — the live document + dirty flag the Autosaver reads.
    var autosaveJob: Job { job }
    var isAutosaveDirty: Bool { isDirty }
    /// Full package for recovery (Bugbot High fix): autosave must carry
    /// toolpaths + doc vars + groups, not a Job-only payload.
    var autosavePayload: ShopPilotPackagePayload? { makePackagePayload() }

    // SampleLoadingSession (SPK-1403a) — the hooks SampleProjectLoader drives.
    func setStatusMessage(_ message: String) {
        statusMessage = message
    }

    init() {
        var job = Job(name: "Untitled Project")
        _ = job.ensureSingleSheet()
        self.job = job
        self.safetyAccepted = UserDefaults.standard.bool(forKey: "shop_pilot_safety_accepted")
        self.showSafetyDisclaimer = !self.safetyAccepted
        self.canvasOverlays = CanvasOverlayStore.load()
        // SPK-1402a — wire the Autosaver: recovery writes for the current
        // document, and record whether launch should offer recovery.
        self.pendingRecovery = RecoveryCoordinator.latestSnapshot()
        startAutosaverForCurrentJob()
    }

    // MARK: - Derived document access

    /// SPK-0800 — the sheet the session's design surface + toolpaths target.
    /// Defaults to the first sheet; `selectSheet(id:)` changes it.
    @Published var activeSheetID: UUID?

    /// Index of the active sheet in `job.sheets` (0 when unset/stale).
    var activeSheetIndex: Int {
        guard let id = activeSheetID,
              let idx = job.sheets.firstIndex(where: { $0.id == id }) else { return 0 }
        return idx
    }

    /// The active sheet (falls back to the first sheet).
    var activeSheet: Sheet? {
        job.sheets.indices.contains(activeSheetIndex) ? job.sheets[activeSheetIndex] : nil
    }

    /// The job's layers, read from the active sheet. Owned by the job, exposed here.
    var layers: [Layer] {
        activeSheet?.layers ?? []
    }

    /// Flat list of all vector paths in the document (derived from design
    /// shapes), each carrying its layer id (SPK-1137).
    var vectors: [VectorPath] {
        GeometryBridge.toCorePaths(shapes, layerIDs: shapeLayerIDs)
    }

    /// Toolpaths list: operation nodes owned by the session's toolpath tree.
    var toolpaths: [ToolpathTreeNode] {
        toolpathTree.root.children
    }

    var sheetCount: Int { job.sheets.count }
    var layerCount: Int {
        activeSheet?.layers.count ?? 0
    }

    /// Whole-job time estimate (SPK-0312): `TimeEstimator` over the full-tree
    /// G-code buffer — the number Cut/Preview show, including travel/rapids.
    /// nil when there is nothing computed yet.
    var fullJobTimeEstimate: TimeEstimateResult? {
        let buffer = allToolpathGCode
        guard !buffer.isEmpty else { return nil }
        return TimeEstimator.estimate(gcodeLines: buffer)
    }

    // MARK: - Dirty / undo hooks

    func markDirty() {
        isDirty = true
        // SPK-0315 — any document change invalidates the material sim; the
        // Preview Simulate button re-simulates from the fresh tree. (The
        // manager was previously never marked from the app — Simulate
        // short-circuited with 0 cells.)
        dirtyRegionManager.markFullTreeDirty()
    }

    func markClean() {
        isDirty = false
    }

    @discardableResult
    func undo() -> Bool {
        guard undoManager.canUndo else { return false }
        undoManager.undo()
        return true
    }

    /// SPK-1606 — Edit menu enabled state.
    var canUndo: Bool { undoManager.canUndo }

    @discardableResult
    func redo() -> Bool {
        guard undoManager.canRedo else { return false }
        undoManager.redo()
        return true
    }

    /// SPK-1606 — Edit menu enabled state.
    var canRedo: Bool { undoManager.canRedo }

    func clearUndoStack() {
        undoManager.removeAllActions()
    }

    // MARK: - Snapshot undo support (SPK-1403b)

    /// Capture the current document slice (delegated to Core SessionUndoStack).
    private func captureSnapshot() -> SessionSnapshot {
        SessionUndoStack.capture(from: self)
    }

    /// SPK-1403c — internal (not private) as the `ProfileGeneratingSession`
    /// witness. Behavior unchanged.
    func registerUndoPoint() {
        let snapshot = captureSnapshot()
        undoManager.registerUndo(withTarget: self) { target in
            target.performUndoRestore(snapshot)
        }
    }

    private func performUndoRestore(_ snapshot: SessionSnapshot) {
        let forward = captureSnapshot()
        undoManager.registerUndo(withTarget: self) { target in
            target.performUndoRestore(forward)
        }
        // SPK-1403b — field transfer is Core-owned (SessionUndoStack.restore).
        SessionUndoStack.restore(snapshot, into: self)
        markDirty()
    }

    // MARK: - Package persist

    /// Build the current session state as a package payload.
    func makePackagePayload() -> ShopPilotPackagePayload {
        var payloadJob = job
        payloadJob.documentVariables = docVars.variables
        payloadJob.shapeGroups = shapeGroups
        syncLayerVectors(into: &payloadJob)
        let toolpaths = ShopPilotPackagePayload.toolpaths(from: toolpathTree)
        return ShopPilotPackagePayload(job: payloadJob, toolpaths: toolpaths)
    }

    /// Save the session to a `.shoppilot` package at the given URL.
    func savePackage(to url: URL) throws {
        try documentSaver.save(makePackagePayload(), to: url)
        packageURL = url
        markClean()
        clearUndoStack()
        // SPK-1611 — a successful save feeds Open Recent.
        RecentPackagesStore.record(url)
        // SPK-1402a — an explicit save supersedes the recovery artifact, so
        // launch no longer offers to recover this document.
        try? FileManager.default.removeItem(at: RecoveryCoordinator.recoveryURL(for: job))
        pendingRecovery = nil
        statusMessage = "Saved “\(job.name)”"
    }

    /// SPK-1611 — open a package from the Open Recent submenu (same loader
    /// as File ▸ Open, with friendly status on failure).
    func openRecentPackage(url: URL) {
        do {
            try openPackage(from: url)
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    /// Open a `.shoppilot` package from the given URL into this session.
    func openPackage(from url: URL) throws {
        let payload = try documentLoader.loadPayload(from: url)
        applyPackagePayload(payload)
        packageURL = url
        markClean()
        clearUndoStack()
        // SPK-1611 — a successful open feeds Open Recent.
        RecentPackagesStore.record(url)
        statusMessage = "Opened “\(payload.job.name)”"
    }

    /// Apply a loaded payload to session state (used by open and tests).
    func applyPackagePayload(_ payload: ShopPilotPackagePayload) {
        job = payload.job
        activeSheetID = payload.job.activeSheetID
        docVars.variables = payload.job.documentVariables
        let restored = Self.shapesFromLayerVectors(payload.job)
        shapes = restored.shapes
        shapeLayerIDs = restored.layerIDs
        shapeGroups = ShapeGroupEngine.sanitized(payload.job.shapeGroups ?? [], shapeCount: shapes.count)
        gcodeLines = []
        selectedVectorIDs = []
        selection = .job
        selectedToolpathID = nil
        toolpathTree = ShopPilotPackagePayload.restoreToolpathTree(from: payload.toolpaths)
        if let firstResult = payload.toolpaths.compactMap(\.toolpathResult).first {
            gcodeLines = firstResult
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            lastToolpathSummary = "Restored \(payload.toolpaths.count) toolpath(s)"
        } else {
            lastToolpathSummary = "No toolpath generated"
        }
        selectedStage = .design
        // SPK-1402a — the document was replaced; autosave follows the new job.
        startAutosaverForCurrentJob()
    }

    private func syncLayerVectors(into job: inout Job) {
        guard !job.sheets.isEmpty else { return }
        if job.sheets[0].layers.isEmpty {
            job.sheets[0].layers.append(Layer(name: "Layer 1"))
        }
        // Convert shapes with their per-shape layer ids, re-homing any shape
        // whose recorded layer no longer exists to the first layer so nothing
        // silently disappears from the saved document.
        let paths = GeometryBridge.toCorePaths(shapes, layerIDs: shapeLayerIDs).map { path -> VectorPath in
            guard let firstLayerID = job.sheets[0].layers.first?.id,
                  !job.sheets[0].layers.contains(where: { $0.id == path.layerId }) else { return path }
            var rehomed = path
            rehomed.layerId = firstLayerID
            return rehomed
        }
        // Layer-faithful sync: every layer keeps exactly the paths that carry
        // its id (no cross-layer clobber, no duplication).
        LayerVisibility.distribute(paths, into: &job.sheets[0].layers)
    }

    /// Push the current design shapes into the session's sheets so the
    /// persisted document and Cut stage always see the live vectors, with each
    /// layer holding only its own shapes (SPK-1137).
    private func syncLayerVectors() {
        syncLayerVectors(into: &job)
        // SPK-0319 lite: every art edit funnels through here — in follow-source
        // mode, mark linked toolpaths stale + dirty (never silent recalc).
        linkManager.sourcesDidChange(toolpathTree: toolpathTree)
    }

    /// SPK-0319 lite — link a freshly generated toolpath node to the source
    /// vectors it was computed from, so follow-source mode can track it.
    private func linkToolpathToSources(_ node: ToolpathTreeNode) {
        let vectorIDs = vectors.map(\.id)
        linkManager.createLink(
            forToolpathId: node.id.uuidString,
            sourceVectorIds: vectorIDs
        )
    }

    /// Index of the active layer within `layers` — the layer selected in the
    /// layer panel, or 0 when no layer is selected / the selection is stale.
    private func activeLayerIndex(in layers: [Layer]) -> Int {
        if case .layer(let id) = selection,
           let index = layers.firstIndex(where: { $0.id == id }) {
            return index
        }
        return 0
    }

    /// The layer currently selected in the layer panel (nil when none).
    var activeLayer: Layer? {
        guard case .layer(let id) = selection else { return nil }
        return layers.first { $0.id == id }
    }

    // MARK: - Per-shape layer access (SPK-1137)

    /// Whether the shape at `index` sits on a visible layer (canvas draws it).
    func isShapeVisible(at index: Int) -> Bool {
        LayerVisibility.isVisible(index: index, shapeLayerIDs: shapeLayerIDs, layers: layers)
    }

    /// Whether the shape at `index` sits on an unlocked layer (canvas may
    /// select/edit it).
    func isShapeEditable(at index: Int) -> Bool {
        !LayerVisibility.isLocked(index: index, shapeLayerIDs: shapeLayerIDs, layers: layers)
    }

    /// Indices of shapes on visible layers — exactly what the canvas draws.
    var visibleShapeIndices: [Int] {
        LayerVisibility.visibleIndices(count: shapes.count, shapeLayerIDs: shapeLayerIDs, layers: layers)
    }

    /// SPK-0319 lite — flip the follow-source mode; persisted on the job.
    func setFollowSourceMode(_ mode: FollowSourceMode) {
        linkManager.setFollowSourceMode(mode)
        job.followSourceModeRaw = mode == .autoFollow ? "autoFollow" : "manual"
        statusMessage = mode == .autoFollow
            ? "Follow Source ON — editing vectors will mark linked toolpaths dirty (no silent recalc)"
            : "Follow Source OFF — toolpaths are independent of later art edits"
        markDirty()
    }

    // MARK: - Driven dimensions (SPK-0807, parametric-lite)

    /// Add a driven dimension: an expression that resolves against the
    /// document variables, persisted on the Job (survives save/open).
    @discardableResult
    func addDrivenDimension(key: String, expression: String,
                            category: String = DrivenDimension.defaultCategory) -> DrivenDimension? {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        let trimmedExpr = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty, !trimmedExpr.isEmpty else {
            statusMessage = "Driven dimension needs a key and an expression"
            return nil
        }
        // Validate the expression against current variables before accepting.
        guard DrivenDimensionResolver.resolve(expression: trimmedExpr, variables: docVars.variables) != nil else {
            statusMessage = "Driven dimension: expression doesn't resolve — check variables/operators"
            return nil
        }
        registerUndoPoint()
        let dim = DrivenDimension(key: trimmedKey, expression: trimmedExpr, category: category)
        job.drivenDimensions.append(dim)
        markDirty()
        statusMessage = "Driven dimension “\(trimmedKey)” = \(resolvedValueText(dim))"
        return dim
    }

    /// Remove a driven dimension by id.
    @discardableResult
    func removeDrivenDimension(id: UUID) -> Bool {
        guard job.drivenDimensions.contains(where: { $0.id == id }) else { return false }
        registerUndoPoint()
        job.drivenDimensions.removeAll { $0.id == id }
        markDirty()
        statusMessage = "Driven dimension removed"
        return true
    }

    /// Update a driven dimension's expression (re-validated on commit).
    @discardableResult
    func updateDrivenDimension(id: UUID, expression: String) -> Bool {
        guard let index = job.drivenDimensions.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              DrivenDimensionResolver.resolve(expression: trimmed, variables: docVars.variables) != nil else {
            statusMessage = "Driven dimension: expression doesn't resolve"
            return false
        }
        registerUndoPoint()
        job.drivenDimensions[index].expression = trimmed
        markDirty()
        statusMessage = "Driven dimension updated"
        return true
    }

    /// Resolve a driven dimension to its numeric value (nil = doesn't resolve).
    func drivenDimensionValue(_ dim: DrivenDimension) -> Double? {
        DrivenDimensionResolver.resolve(expression: dim.expression, variables: docVars.variables)
    }

    private func resolvedValueText(_ dim: DrivenDimension) -> String {
        if let value = drivenDimensionValue(dim) {
            return String(format: "%.3f", value)
        }
        return "?"
    }

    /// Reconstruct design shapes + their per-shape layer membership from
    /// persisted layer vectors (freehand polylines), flattening in layer
    /// order. Each shape's layer id is the layer it was saved on (SPK-1137).
    static func shapesFromLayerVectors(_ job: Job) -> (shapes: [VectorShape], layerIDs: [UUID]) {
        var shapes: [VectorShape] = []
        var layerIDs: [UUID] = []
        for layer in job.sheets.flatMap(\.layers) {
            for path in layer.vectors {
                let pts = path.points.map { ShopPilotGeometry.VectorPoint(x: $0.x, y: $0.y) }
                shapes.append(VectorShape.freehand(points: pts))
                layerIDs.append(path.layerId)
            }
        }
        return (shapes, layerIDs)
    }

    // MARK: - Job lifecycle

    func acceptSafety() {
        safetyAccepted = true
        showSafetyDisclaimer = false
        UserDefaults.standard.set(true, forKey: "shop_pilot_safety_accepted")
    }

    func replaceJob(_ newJob: Job) {
        job = newJob
        activeSheetID = newJob.activeSheetID
        // SPK-0319 lite: restore the persisted follow-source mode.
        if let raw = newJob.followSourceModeRaw {
            linkManager.setFollowSourceMode(raw == "autoFollow" ? .autoFollow : .manual)
        } else {
            linkManager.setFollowSourceMode(.manual)
        }
        keepOutZones = newJob.keepOutZones ?? []
        docVars.variables = newJob.documentVariables
        // Materialize the job's layer vectors into the session design canvas —
        // mirrors the open path (shapesFromLayerVectors). Without this, recipe
        // jobs (Signage glyphs, borders) open with a blank canvas.
        let layerShapes = Self.shapesFromLayerVectors(newJob)
        shapes = layerShapes.shapes
        shapeLayerIDs = layerShapes.layerIDs
        gcodeLines = []
        selectedVectorIDs = []
        selection = .job
        selectedToolpathID = nil
        toolpathTree = ToolpathTreeManager()
        lastToolpathSummary = "No toolpath generated"
        statusMessage = "Job “\(newJob.name)” ready"
        selectedStage = .design
        packageURL = nil
        // SPK-1106a: materialize the sign recipe's precomputed V-Carve as a
        // real tree node (visible in Cut, preview, and the machine handoff).
        if let vcarveGCode = newJob.vcarveGCode, !vcarveGCode.isEmpty {
            let node = toolpathTree.addOperation("V-Carve 1 (Recipe)")
            node.toolpathResult = vcarveGCode.joined(separator: "\n")
            node.estimatedTimeSeconds = newJob.vcarveTimeSeconds
            node.paramsJSON = newJob.vcarveParamsJSON
            // The result is fresh from the recipe's engine run — clean.
            node.clearDirty()
            gcodeLines = vcarveGCode
            lastToolpathSummary =
                "Recipe V-Carve ready (\(vcarveGCode.count) lines, \(Int(newJob.vcarveTimeSeconds))s)"
            statusMessage = lastToolpathSummary
        }
        markClean()
        clearUndoStack()
        // SPK-1402a — recipe jobs replace the document; autosave follows.
        startAutosaverForCurrentJob()
    }

    // MARK: - New Job (SPK-1601)

    /// File New Job: discard the current document and start a blank Untitled
    /// project. SPK-1601 — this REPLACES the session (shapes/toolpaths/tree
    /// cleared via `replaceJob`), not just a stage switch. Dirty documents
    /// get a confirm-discard alert (no save prompt — Save is ⌘S / 1600).
    /// Returns false when the user cancelled the dirty-confirm.
    @discardableResult
    func newJob() -> Bool {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Discard unsaved changes?"
            alert.informativeText = "Start a new Untitled Project and discard the current design?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        replaceJob(Job(name: "Untitled Project"))
        // New Job lands on Setup (replaceJob itself selects Design for recipe
        // jobs — File New is a blank start, so Setup is the first step).
        selectedStage = .setup
        return true
    }

    // MARK: - Layer mutations

    @discardableResult
    func addLayer(_ layer: Layer = Layer()) -> Layer? {
        guard var sheet = activeSheet else { return nil }
        registerUndoPoint()
        sheet.addLayer(layer)
        job.sheets[activeSheetIndex] = sheet
        markDirty()
        return layer
    }

    func renameLayer(id: UUID, to newName: String) {
        guard var sheet = activeSheet,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        registerUndoPoint()
        sheet.layers[index].name = newName
        job.sheets[activeSheetIndex] = sheet
        markDirty()
    }

    @discardableResult
    func removeLayer(id: UUID) -> Bool {
        guard var sheet = activeSheet else { return false }
        guard sheet.layers.contains(where: { $0.id == id }) else { return false }
        registerUndoPoint()
        sheet.removeLayer(id: id)
        job.sheets[activeSheetIndex] = sheet
        // Drop the shapes that lived on the removed layer — their vectors are
        // gone, so keeping them would re-home ghosts on the next save (SPK-1137).
        var keptShapes: [VectorShape] = []
        var keptLayerIDs: [UUID] = []
        for (index, shape) in shapes.enumerated() {
            if shapeLayerIDs.indices.contains(index), shapeLayerIDs[index] == id { continue }
            keptShapes.append(shape)
            keptLayerIDs.append(shapeLayerIDs.indices.contains(index) ? shapeLayerIDs[index] : UUID())
        }
        shapes = keptShapes
        shapeLayerIDs = keptLayerIDs
        selectedShapeIndices = []
        selectedVectorIDs = selectedVectorIDs.filter { id in
            layers.contains { $0.vectors.contains { $0.id == id } }
        }
        if case .layer(let selectedID) = selection, selectedID == id {
            selection = .none
        }
        markDirty()
        return true
    }

    /// Toggle layer visibility (eye icon) through the session sheet.
    func setLayerVisible(id: UUID, isVisible: Bool) {
        guard var sheet = activeSheet,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        guard sheet.layers[index].isVisible != isVisible else { return }
        registerUndoPoint()
        sheet.layers[index].isVisible = isVisible
        job.sheets[activeSheetIndex] = sheet
        markDirty()
    }

    /// Toggle layer lock (lock icon) through the session sheet. Locking also
    /// drops selection of that layer's shapes (locked shapes are not editable).
    func setLayerLocked(id: UUID, isLocked: Bool) {
        guard var sheet = activeSheet,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        guard sheet.layers[index].isLocked != isLocked else { return }
        registerUndoPoint()
        sheet.layers[index].isLocked = isLocked
        job.sheets[activeSheetIndex] = sheet
        if isLocked {
            selectedShapeIndices = Set(selectedShapeIndices.filter { idx in
                !(shapeLayerIDs.indices.contains(idx) && shapeLayerIDs[idx] == id)
            })
        }
        markDirty()
    }

    /// Move a layer to an absolute index (0-based) within the session sheet.
    @discardableResult
    func moveLayer(id: UUID, toIndex: Int) -> Bool {
        guard var sheet = activeSheet,
              let from = sheet.layers.firstIndex(where: { $0.id == id }) else { return false }
        let clamped = min(max(toIndex, 0), sheet.layers.count - 1)
        guard from != clamped else { return false }
        registerUndoPoint()
        sheet.moveLayer(from: from, to: clamped)
        job.sheets[activeSheetIndex] = sheet
        markDirty()
        return true
    }

    /// Move a layer one position up in the sheet's layer list.
    @discardableResult
    func moveLayerUp(id: UUID) -> Bool {
        guard let from = activeSheet?.layers.firstIndex(where: { $0.id == id }) else { return false }
        return moveLayer(id: id, toIndex: from - 1)
    }

    /// Move a layer one position down in the sheet's layer list.
    @discardableResult
    func moveLayerDown(id: UUID) -> Bool {
        guard let from = activeSheet?.layers.firstIndex(where: { $0.id == id }) else { return false }
        return moveLayer(id: id, toIndex: from + 1)
    }

    /// Add a named layer; returns the created layer (nil if no sheet).
    @discardableResult
    func addLayer(named name: String) -> Layer? {
        addLayer(Layer(name: name))
    }

    // MARK: - Sheet / material mutations (bound to the session sheet)

    /// Update stock W/D/H (mm) of the session's first sheet.
    func updateSheetDimensions(width: Double, depth: Double, height: Double) {
        guard var sheet = activeSheet else { return }
        registerUndoPoint()
        sheet.width = width
        sheet.depth = depth
        sheet.height = height
        job.sheets[activeSheetIndex] = sheet
        markDirty()
    }

    /// Set the material of the session's first sheet (nil = no material).
    func setSheetMaterial(_ material: ShopPilotCore.Material?) {
        guard var sheet = activeSheet else { return }
        registerUndoPoint()
        sheet.material = material
        job.sheets[activeSheetIndex] = sheet
        markDirty()
    }

    /// Apply a stock sheet preset to the session's first sheet (SPK-1132):
    /// sets the sheet name + W/D/H and records the preset name so it
    /// survives save/open. Undoable + dirty.
    func applyStockPreset(_ preset: StockSheetPreset) {
        guard var sheet = activeSheet else { return }
        registerUndoPoint()
        StockSheetPresets.apply(preset, to: &sheet)
        job.sheets[activeSheetIndex] = sheet
        statusMessage = "Stock: \(preset.name)"
        markDirty()
    }

    /// SPK-1800d: persist the Design canvas datum (corner/center) on the job.
    func updateCanvasOrigin(_ mode: String) {
        registerUndoPoint()
        job.canvasOriginRaw = mode
        job.updatedAt = .now
        markDirty()
    }

    // MARK: - Sheet CRUD (SPK-0800 multi-sheet management)

    /// Add a new sheet (default 600×400×25 stock) and make it active.
    @discardableResult
    func addSheet(named name: String? = nil) -> Sheet? {
        registerUndoPoint()
        var sheet = Sheet(name: name ?? "Sheet \(job.sheets.count + 1)")
        sheet.layers = [Layer(name: "Layer 1")]
        job.addSheet(sheet)
        activeSheetID = sheet.id
        selection = .sheet(sheet.id)
        statusMessage = "Added sheet “\(name)” — \(job.sheets.count) total"
        markDirty()
        return sheet
    }

    /// Remove a sheet by id. The active sheet is never removed while it holds
    /// the design surface — switching to another sheet first is the caller's
    /// job (UI keeps at least one sheet). Returns false when removal is
    /// impossible (last sheet / id missing).
    @discardableResult
    func removeSheet(id: UUID) -> Bool {
        guard job.sheets.count > 1,
              job.sheets.contains(where: { $0.id == id }) else { return false }
        registerUndoPoint()
        let removed = job.removeSheet(id: id)
        if activeSheetID == id {
            activeSheetID = job.sheets.first?.id
        }
        // Drop shapes that lived on the removed sheet's layers (SPK-1137
        // discipline: never keep ghosts that would re-home on save).
        let removedLayerIDs = Set(removed ? removedSheetLayerIDs(id: id) : [])
        if !removedLayerIDs.isEmpty {
            var keptShapes: [VectorShape] = []
            var keptLayerIDs: [UUID] = []
            for (index, shape) in shapes.enumerated() {
                if shapeLayerIDs.indices.contains(index), removedLayerIDs.contains(shapeLayerIDs[index]) { continue }
                keptShapes.append(shape)
                keptLayerIDs.append(shapeLayerIDs.indices.contains(index) ? shapeLayerIDs[index] : UUID())
            }
            shapes = keptShapes
            shapeLayerIDs = keptLayerIDs
            selectedShapeIndices = []
        }
        selection = .job
        statusMessage = "Removed sheet — \(job.sheets.count) remain"
        markDirty()
        return true
    }

    private func removedSheetLayerIDs(id: UUID) -> [UUID] {
        guard let sheet = job.sheets.first(where: { $0.id == id }) else { return [] }
        return sheet.layers.map(\.id)
    }

    // MARK: - Sheet duplication + toolpath transfer (SPK-1208)

    /// Duplicate a sheet: deep copy (new sheet + layer ids, same dims/
    /// material/preset/vectors), make it active, add a matching toolpath
    /// group to the tree. Undoable + dirty.
    @discardableResult
    func duplicateSheet(id: UUID) -> Bool {
        guard let sheet = job.sheets.first(where: { $0.id == id }) else {
            statusMessage = "Sheet to duplicate not found"
            return false
        }
        registerUndoPoint()
        let copy = SheetOperations.duplicate(sheet)
        job.addSheet(copy)
        // A fresh toolpath group so the copy starts clean (toolpaths are
        // NOT auto-copied — they belong to the original's ops until moved).
        _ = toolpathTree.addGroup(SheetOperations.toolpathGroupName(for: copy))
        activeSheetID = copy.id
        selection = .sheet(copy.id)
        statusMessage = "Duplicated “\(sheet.name)” → “\(copy.name)”"
        markDirty()
        return true
    }

    /// Move a toolpath node to another sheet's group. Guards: target exists,
    /// not already there, node is an operation. The move re-homes the node
    /// under the target group (creating the group when needed).
    @discardableResult
    func moveToolpathToSheet(nodeID: UUID, targetSheetID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              case .operation = node.type,
              let target = job.sheets.first(where: { $0.id == targetSheetID }) else {
            statusMessage = "Move failed — toolpath or target sheet not found"
            return false
        }
        if let reason = SheetOperations.validateToolpathMove(
            targetSheetID: targetSheetID,
            sheets: job.sheets
        ) {
            statusMessage = "Move failed — \(reason)"
            return false
        }
        // Find the node's current parent to remove it from.
        guard let currentParent = toolpathTree.parent(of: nodeID) else {
            statusMessage = "Move failed — toolpath has no parent"
            return false
        }
        registerUndoPoint()
        let groupName = SheetOperations.toolpathGroupName(for: target)
        // Find or create the target sheet's group under root.
        let targetGroup: ToolpathTreeNode
        if let existing = toolpathTree.root.children.first(where: { node in
            if case .group(let label) = node.type { return label == groupName }
            return false
        }) {
            targetGroup = existing
        } else {
            targetGroup = toolpathTree.addGroup(groupName)
        }
        // Remove from the old parent and append under the target group
        // (preserving the node's result/params — it stays computed).
        _ = currentParent.removeChild(id: nodeID)
        targetGroup.addChild(node)
        statusMessage = "Moved “\(node.name)” to “\(target.name)”"
        markDirty()
        return true
    }

    /// Switch the design surface + toolpath stock to another sheet.
    func selectSheet(id: UUID) {
        guard job.sheets.contains(where: { $0.id == id }) else { return }
        registerUndoPoint()
        activeSheetID = id
        selection = .sheet(id)
        statusMessage = "Sheet: \(activeSheet?.name ?? "?")"
        markDirty()
    }

    // MARK: - Double-sided job (SPK-0801)

    /// The front-side sheet id of the double-sided config, if any.
    var doubleSidedFrontSheetID: UUID? { job.doubleSidedConfig?.frontSheetID }

    /// The back-side sheet id of the double-sided config, if any.
    var doubleSidedBackSheetID: UUID? { job.doubleSidedConfig?.backSheetID }

    /// The sheet the OTHER side of a double-sided job designs against: given
    /// the active sheet, returns its counterpart (nil for single-sided).
    func counterpartSheet(of sheetID: UUID) -> UUID? {
        guard let cfg = job.doubleSidedConfig else { return nil }
        if cfg.frontSheetID == sheetID { return cfg.backSheetID }
        if cfg.backSheetID == sheetID { return cfg.frontSheetID }
        return nil
    }

    /// Establish (or update) the double-sided pairing of two sheets.
    /// Registers the config on the job (persisted via .shoppilot) and marks
    /// the job dirty. Undoable.
    @discardableResult
    func setDoubleSided(frontSheetID: UUID, backSheetID: UUID,
                        alignmentMethod: AlignmentMethod = .registrationMarks,
                        backSideRotation: Double = 0.0,
                        backSideFlipX: Bool = false,
                        backSideFlipY: Bool = false) -> Bool {
        guard job.sheets.contains(where: { $0.id == frontSheetID }),
              job.sheets.contains(where: { $0.id == backSheetID }),
              frontSheetID != backSheetID else {
            statusMessage = "Double-sided: pick two different sheets"
            return false
        }
        registerUndoPoint()
        let cfg = DoubleSidedJobConfig(
            frontSheetID: frontSheetID,
            backSheetID: backSheetID,
            alignmentMethod: alignmentMethod,
            backSideZOffset: -(activeSheet(for: backSheetID)?.height ?? 0),
            backSideRotation: backSideRotation,
            backSideFlipX: backSideFlipX,
            backSideFlipY: backSideFlipY
        )
        job.doubleSidedConfig = cfg
        statusMessage = "Double-sided job: front + back paired (\(alignmentMethod.displayName))"
        markDirty()
        return true
    }

    private func activeSheet(for id: UUID) -> Sheet? {
        job.sheets.first(where: { $0.id == id })
    }

    /// Remove the double-sided pairing (back to single-sided). The back sheet
    /// stays in the document — the user can delete it via sheet CRUD.
    func clearDoubleSided() {
        guard job.doubleSidedConfig != nil else { return }
        registerUndoPoint()
        job.doubleSidedConfig = nil
        statusMessage = "Double-sided pairing removed — job is single-sided"
        markDirty()
    }

    /// Flip the design surface to the counterpart side of a double-sided job
    /// (front ⇄ back). No-op for single-sided jobs.
    func flipJobSide() {
        guard let cfg = job.doubleSidedConfig else { return }
        let target = activeSheetID == cfg.frontSheetID ? cfg.backSheetID : cfg.frontSheetID
        selectSheet(id: target)
        statusMessage = target == cfg.frontSheetID
            ? "Side: Front"
            : "Side: Back (Z offset \(String(format: "%.1f", cfg.backSideZOffset))mm)"
    }

    // MARK: - Rotary job setup (SPK-0903)

    /// The job's rotary stock configuration (nil = no rotary job setup).
    var rotaryConfig: RotaryConfig? { job.rotaryConfig }

    /// The rotary stock diameter the wrap/fluting strategies default to:
    /// job-level config when set, else the per-op/engine default.
    var rotaryStockDiameter: Double {
        job.rotaryConfig?.diameter ?? 50.0
    }

    /// Establish (or update) the job-level rotary setup: stock diameter,
    /// axis length, direction and wrap behavior. Persisted via .shoppilot.
    @discardableResult
    func setRotaryConfig(diameter: Double, axisLength: Double,
                         direction: RotaryDirection = .clockwise,
                         wrapEnabled: Bool = true, wrapOverlap: Double = 5.0) -> Bool {
        guard diameter > 0, axisLength > 0 else {
            statusMessage = "Rotary setup: diameter and axis length must be positive"
            return false
        }
        registerUndoPoint()
        var config = RotaryConfig(mode: .cylinder, diameter: diameter, axisLength: axisLength,
                                  direction: direction, wrapEnabled: wrapEnabled,
                                  wrapOverlap: wrapOverlap)
        config.zeroAngle = job.rotaryConfig?.zeroAngle ?? 0
        config.startAngle = job.rotaryConfig?.startAngle ?? 0
        config.endAngle = job.rotaryConfig?.endAngle ?? 360
        job.rotaryConfig = config
        statusMessage = String(
            format: "Rotary: Ø%.1fmm × %.1fmm (%@, wrap %@)",
            diameter, axisLength,
            direction == .clockwise ? "CW" : "CCW",
            wrapEnabled ? "on" : "off"
        )
        markDirty()
        return true
    }

    /// Remove the rotary job setup (back to flat machining).
    func clearRotaryConfig() {
        guard job.rotaryConfig != nil else { return }
        registerUndoPoint()
        job.rotaryConfig = nil
        statusMessage = "Rotary setup removed — flat machining"
        markDirty()
    }

    // MARK: - Shape / vector mutations

    func addShapes(_ newShapes: [VectorShape]) {
        registerUndoPoint()
        shapes.append(contentsOf: newShapes)
        let layerID: UUID
        if var sheet = activeSheet {
            if sheet.layers.isEmpty {
                sheet.layers.append(Layer(name: "Layer 1"))
            }
            // New shapes land on the active layer (or the first layer when no
            // layer is selected) so per-layer membership is preserved (SPK-1137).
            let targetIndex = activeLayerIndex(in: sheet.layers)
            layerID = sheet.layers[targetIndex].id
            let converted = GeometryBridge.toCorePaths(newShapes, layerIDs: Array(repeating: layerID, count: newShapes.count))
            for path in converted {
                sheet.layers[targetIndex].addVector(path)
            }
            job.sheets[activeSheetIndex] = sheet
        } else {
            layerID = UUID()
        }
        shapeLayerIDs.append(contentsOf: Array(repeating: layerID, count: newShapes.count))
        statusMessage = "Added \(newShapes.count) shape(s) — \(vectors.count) path(s) total"
        selectedStage = .design
        markDirty()
    }

    func moveShape(at index: Int, by dx: Double, dy: Double) {
        guard shapes.indices.contains(index) else { return }
        // Group-aware: moving one member moves the whole group (UI-polish cluster).
        let targets = ShapeGroupEngine.expandedSelection(
            selected: [index],
            groups: shapeGroups
        ).sorted()
        registerUndoPoint()
        for target in targets where shapes.indices.contains(target) {
            shapes[target] = shapes[target].translated(by: dx, dy)
        }
        syncLayerVectors()
        markDirty()
    }

    // MARK: - SPK-1900f (nesting)

    /// Design-stage "Nest Selection": pack the selected shapes (or all shapes
    /// when nothing is selected) onto the active sheet with the AABB skyline
    /// packer. Translation-only placement (rotation reserved for a follow-up
    /// card): each shape moves so its bounding box lands at the packer slot,
    /// preserving intra-shape geometry. Undoable; reports utilization.
    @discardableResult
    func nestShapesOnSheet(spacingMm: Double = 6.0) -> Bool {
        guard let sheet = activeSheet else {
            statusMessage = "Nest: no sheet — set one up in Setup first"
            return false
        }
        let indices: [Int]
        if selectedShapeIndices.isEmpty {
            indices = Array(shapes.indices)
        } else {
            indices = ShapeGroupEngine.expandedSelection(
                selected: Set(selectedShapeIndices),
                groups: shapeGroups
            ).sorted()
        }
        guard !indices.isEmpty else {
            statusMessage = "Nest: nothing to nest — draw or select some vectors first"
            return false
        }
        let parts = indices.compactMap { idx -> NestingPart? in
            guard shapes.indices.contains(idx) else { return nil }
            let bb = shapes[idx].boundingRect
            return NestingPart(
                id: UUID(),
                widthMm: bb.width,
                heightMm: bb.height,
                allowRotation: false
            )
        }
        guard !parts.isEmpty else {
            statusMessage = "Nest: selected shapes have no measurable bounds"
            return false
        }
        let options = NestingOptions(
            sheetWidthMm: sheet.width,
            sheetHeightMm: sheet.depth,
            spacingMm: spacingMm,
            allowRotationGlobally: false
        )
        switch NestingEngine.nest(parts: parts, options: options) {
        case .success(let placements, let usedFraction):
            registerUndoPoint()
            // Placements are sorted by the packer's deterministic part order;
            // pair each placement back to its shape via the part id.
            var idToShapeIndex: [UUID: Int] = [:]
            for (slot, idx) in indices.enumerated() where slot < parts.count {
                idToShapeIndex[parts[slot].id] = idx
            }
            for placement in placements {
                guard let shapeIndex = idToShapeIndex[placement.partID],
                      shapes.indices.contains(shapeIndex) else { continue }
                let bb = shapes[shapeIndex].boundingRect
                let dx = placement.xMm - bb.minX
                let dy = placement.yMm - bb.minY
                shapes[shapeIndex] = shapes[shapeIndex].translated(by: dx, dy)
            }
            syncLayerVectors()
            markDirty()
            statusMessage = "Nest: \(placements.count) of \(parts.count) parts placed, \(String(format: "%.0f", usedFraction * 100))% sheet used"
            return true
        case .doesNotFit(let unplacedIDs):
            if unplacedIDs.count == parts.count {
                statusMessage = "Nest: parts do not fit on \(Int(sheet.width))×\(Int(sheet.depth))mm sheet — enlarge the sheet or reduce spacing"
            } else {
                statusMessage = "Nest: \(parts.count - unplacedIDs.count) placed, \(unplacedIDs.count) did not fit"
            }
            return false
        }
    }

    // MARK: - Design ops (SPK-1101)

    /// Replace the shape at `index` with a new shape (undoable, dirty).
    func updateShape(at index: Int, with shape: VectorShape) {
        guard shapes.indices.contains(index) else { return }
        registerUndoPoint()
        shapes[index] = shape
        syncLayerVectors()
        markDirty()
    }

    /// Remove shapes at the given indices (undoable, dirty). Indices may be
    /// in any order; they are removed highest-first so earlier indices stay valid.
    func deleteShapes(at indices: [Int]) {
        let unique = Set(indices).sorted(by: >)
        guard !unique.isEmpty, unique.allSatisfy({ shapes.indices.contains($0) }) else { return }
        registerUndoPoint()
        for index in unique {
            shapes.remove(at: index)
            shapeLayerIDs.remove(at: index)
        }
        shapeGroups = ShapeGroupEngine.removing(indices: Set(unique), from: shapeGroups)
        selectedShapeIndices = []
        syncLayerVectors()
        markDirty()
    }

    // MARK: - Group / Ungroup / Set Size (UI-polish cluster)

    /// Group the selected shapes: any group touching the selection folds in,
    /// and the selection itself forms (or joins) one group. Selection becomes
    /// the whole group so subsequent transforms act on every member.
    @discardableResult
    func applyGroup() -> Bool {
        let selected = selectedShapeIndices.filter { shapes.indices.contains($0) }
        guard selected.count >= 2 else {
            statusMessage = "Group needs ≥2 selected shapes"
            return false
        }
        registerUndoPoint()
        shapeGroups = ShapeGroupEngine.grouping(
            selected: Set(selected),
            existing: shapeGroups,
            shapeCount: shapes.count
        )
        selectedShapeIndices = Set(ShapeGroupEngine.expandedSelection(
            selected: Set(selected),
            groups: shapeGroups
        ))
        statusMessage = "Grouped \(selected.count) shapes — transforms now move them together"
        syncLayerVectors()
        markDirty()
        return true
    }

    /// Ungroup: dissolve every group that touches the selection. Members
    /// become independent shapes again.
    @discardableResult
    func applyUngroup() -> Bool {
        let selected = selectedShapeIndices.filter { shapes.indices.contains($0) }
        guard !selected.isEmpty else {
            statusMessage = "Ungroup needs a selected shape"
            return false
        }
        registerUndoPoint()
        shapeGroups = ShapeGroupEngine.ungrouping(selected: Set(selected), existing: shapeGroups)
        statusMessage = "Ungrouped — shapes are independent again"
        syncLayerVectors()
        markDirty()
        return true
    }

    /// Set the exact bounding-box width/height of the selection (reference
    /// "Set size" dialog). Undoable + dirty.
    @discardableResult
    func applySetSize(width: Double, height: Double, preserveAspect: Bool = false) -> Bool {
        let indices = ShapeGroupEngine.expandedSelection(
            selected: selectedShapeIndices,
            groups: shapeGroups
        ).sorted()
        guard !indices.isEmpty, indices.allSatisfy({ shapes.indices.contains($0) }) else {
            statusMessage = "Set Size needs a selected shape"
            return false
        }
        let sel = indices.map { shapes[$0] }
        let output = ShapeTransformer().setSize(
            shapes: sel,
            width: max(width, 0.001),
            height: max(height, 0.001),
            preserveAspect: preserveAspect
        )
        registerUndoPoint()
        for (offset, index) in indices.enumerated() where shapes.indices.contains(index) {
            shapes[index] = output[offset]
        }
        selectedShapeIndices = Set(indices)
        syncLayerVectors()
        markDirty()
        statusMessage = String(format: "Set size: %.2f × %.2f mm", max(width, 0.001), max(height, 0.001))
        return true
    }

    /// Replace the selected shapes with the op results. The originals are
    /// removed and the results are inserted at the lowest selected index.
    /// Empty results delete the shape entirely (e.g. full boolean subtract).
    /// Results inherit the layer of the lowest-index selected shape (SPK-1137).
    func replaceSelectedShapes(with results: [VectorShape]) {
        let indices = selectedShapeIndices.sorted()
        guard !indices.isEmpty else { return }
        registerUndoPoint()
        let insertAt = indices.first ?? 0
        let resultLayerID = shapeLayerIDs.indices.contains(insertAt) ? shapeLayerIDs[insertAt] : (layers.first?.id ?? UUID())
        for index in indices.reversed() where shapes.indices.contains(index) {
            shapes.remove(at: index)
            shapeLayerIDs.remove(at: index)
        }
        shapes.insert(contentsOf: results, at: min(insertAt, shapes.count))
        shapeLayerIDs.insert(
            contentsOf: Array(repeating: resultLayerID, count: results.count),
            at: min(insertAt, shapeLayerIDs.count)
        )
        selectedShapeIndices = Set(results.indices.map { min(insertAt, shapes.count - results.count) + $0 })
        syncLayerVectors()
        markDirty()
    }

    /// In-place transform variant used by group-aware transforms (nudge /
    /// flip / rotate / scale): replaces the shape at each of `indices` with
    /// the parallel result WITHOUT removing/re-inserting, so group indices
    /// stay valid and member order is preserved (UI-polish cluster).
    func replaceSelectedShapes(with results: [VectorShape], at indices: [Int]) {
        guard results.count == indices.count else { return }
        registerUndoPoint()
        for (offset, index) in indices.enumerated()
        where shapes.indices.contains(index) && results.indices.contains(offset) {
            shapes[index] = results[offset]
        }
        selectedShapeIndices = Set(indices)
        syncLayerVectors()
        markDirty()
    }

    /// Join selected polylines/lines that share endpoints into chains.
    /// Uses `ShapeJoinEngine` (joinPolylines for freehand, joinLines for lines).
    /// Shapes that cannot join are kept unchanged.
    @discardableResult
    func applyJoin() -> Bool {
        let indices = selectedShapeIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard sel.count >= 2 else {
            statusMessage = "Join needs ≥2 selected shapes"
            return false
        }
        var output: [VectorShape] = []
        var remaining = sel

        // Freehand polylines: greedy pairwise join by shared endpoints.
        var polys = remaining.filter { if case .freehand = $0 { return true } else { return false } }
        let others = remaining.filter { if case .freehand = $0 { return false } else { return true } }
        var joined: [VectorShape] = []
        while polys.count >= 2 {
            let a = polys.removeFirst()
            var merged = false
            for (i, b) in polys.enumerated() {
                if let m = ShapeJoinEngine.joinPolylines(a, b) {
                    polys.remove(at: i)
                    polys.insert(m, at: 0)
                    merged = true
                    break
                }
            }
            if !merged {
                joined.append(a)
            }
        }
        joined.append(contentsOf: polys)

        // Lines: chain join.
        if !others.isEmpty {
            let (lineResults, lineRemaining) = ShapeJoinEngine.joinLines(others)
            output.append(contentsOf: joined)
            output.append(contentsOf: lineResults)
            output.append(contentsOf: lineRemaining)
        } else {
            output.append(contentsOf: joined)
        }

        let countBefore = sel.count
        replaceSelectedShapes(with: output)
        statusMessage = "Join: \(countBefore) → \(output.count) shape(s)"
        return true
    }

    /// Close every selected open polyline (appends first point to last).
    @discardableResult
    func applyClose() -> Bool {
        let indices = selectedShapeIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Close needs a selected shape"
            return false
        }
        let output = sel.flatMap { ShapeJoinEngine.closePolyline($0) }
        replaceSelectedShapes(with: output)
        statusMessage = "Closed \(sel.count) shape(s)"
        return true
    }

    /// Weld (union) selected shapes into merged regions.
    @discardableResult
    func applyWeld() -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard sel.count >= 2 else {
            statusMessage = "Weld needs ≥2 selected shapes"
            return false
        }
        let output = ShapeBooleanEngine.weld(shapes: sel)
        replaceSelectedShapes(with: output)
        statusMessage = "Welded \(sel.count) → \(output.count) shape(s)"
        return true
    }

    /// Subtract the 2nd..nth selected shapes from the first selected shape.
    @discardableResult
    func applySubtract() -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard sel.count >= 2 else {
            statusMessage = "Subtract needs a base + tool shapes selected"
            return false
        }
        var base = sel[0]
        var output: [VectorShape] = []
        for tool in sel.dropFirst() {
            let pieces = ShapeBooleanEngine.subtract(base: base, tool: tool)
            if pieces.isEmpty { output = []; break }
            if pieces.count == 1 {
                base = pieces[0]
            } else {
                output = pieces
                break
            }
        }
        if output.isEmpty { output = [base] }
        replaceSelectedShapes(with: output)
        statusMessage = "Subtracted \(sel.count - 1) tool(s) from base"
        return true
    }

    /// Intersect all selected shapes.
    @discardableResult
    func applyIntersect() -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard sel.count >= 2 else {
            statusMessage = "Intersect needs ≥2 selected shapes"
            return false
        }
        let output = ShapeBooleanEngine.intersect(shapes: sel)
        replaceSelectedShapes(with: output)
        statusMessage = "Intersected \(sel.count) shape(s) → \(output.count) shape(s)"
        return true
    }

    /// Offset every selected shape by a signed distance (positive = outward).
    @discardableResult
    func applyOffset(distance: Double) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Offset needs a selected shape"
            return false
        }
        var output: [VectorShape] = []
        var skipped = 0
        for shape in sel {
            let results = VectorOffsetCalculator.offsetShape(shape, by: distance)
            if results.isEmpty {
                skipped += 1
            } else {
                output.append(contentsOf: results)
            }
        }
        replaceSelectedShapes(with: output)
        let distanceText = String(format: "%.2f", distance)
        statusMessage = "Offset \(sel.count) shape(s) by \(distanceText)" +
            (skipped > 0 ? " (\(skipped) collapsed)" : "")
        return true
    }

    /// Fillet every selected shape's corners (SPK-0215). Freehand polylines
    /// get interior corners rounded; rectangles convert to rounded freehands.
    @discardableResult
    func applyFillet(radius: Double) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Fillet needs a selected shape"
            return false
        }
        let output = sel.map { ShapeFilletEngine.fillet($0, radius: radius) }
        replaceSelectedShapes(with: output)
        statusMessage = "Filleted \(sel.count) shape(s) (r \(String(format: "%.2f", radius))mm)"
        return true
    }

    /// SPK-D13 — fit smooth curves through the selected shapes (replaces each
    /// shape with its smoothed control-point polyline; corners sharper than
    /// the threshold survive). Undoable + dirty.
    @discardableResult
    func applyFitCurves(smoothing: Double = 0.5) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Fit Curves needs a selected shape"
            return false
        }
        let params = FitCurvesParams(smoothing: smoothing, cornerAngleDegrees: 60, maxSegmentLengthMm: 0)
        let output = sel.map { shape in
            let result = FitCurvesEngine.fit(shape: shape, params: params)
            return VectorShape.freehand(points: result.fitted.first ?? [])
        }
        replaceSelectedShapes(with: output)
        statusMessage = "Fitted \(sel.count) shape(s) with smoothing \(String(format: "%.1f", smoothing))"
        return true
    }

    /// Extend selected open shapes by a distance at both open ends (SPK-0215).
    @discardableResult
    func applyExtend(distance: Double) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Extend needs a selected shape"
            return false
        }
        let output = sel.map { ShapeExtendEngine.extend($0, distance: distance) }
        replaceSelectedShapes(with: output)
        statusMessage = "Extended \(sel.count) shape(s) by \(String(format: "%.2f", distance))mm"
        return true
    }

    // MARK: - Array / circular copy (SPK-0214)

    /// Grid-copy every selected shape (columns × rows at a spacing). The
    /// selection becomes the full grid (grid array-copy semantics).
    @discardableResult
    func applyArrayCopy(columns: Int, rows: Int, spacingX: Double, spacingY: Double) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty, columns > 0, rows > 0 else {
            statusMessage = "Array copy needs selected shapes and positive columns/rows"
            return false
        }
        var output: [VectorShape] = []
        for shape in sel {
            let result = ArrayCopyEngine.createGridArray(
                source: shape, columns: columns, rows: rows,
                spacingX: spacingX, spacingY: spacingY
            )
            output.append(contentsOf: result.copies)
        }
        replaceSelectedShapes(with: output)
        statusMessage = "Array copy: \(sel.count) shape(s) → \(output.count) copies (\(columns)×\(rows) grid)"
        return true
    }

    /// Copy every selected shape around a center (default: selection
    /// centroid). With `rotateCopies`, each copy also spins by its angular
    /// position (rectangles convert to freehand so the rotation is real).
    @discardableResult
    func applyCircularCopy(count: Int, center: VectorPoint? = nil, rotateCopies: Bool) -> Bool {
        let sel = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty, count >= 2 else {
            statusMessage = "Circular copy needs selected shapes and count ≥ 2"
            return false
        }
        let ctr = center ?? selectionCentroid(of: sel) ?? VectorPoint(x: 0, y: 0)
        var output: [VectorShape] = []
        for shape in sel {
            let result = ArrayCopyEngine.createCircularArrayAround(
                source: shape, center: ctr, count: count, rotateCopies: rotateCopies
            )
            output.append(contentsOf: result.copies)
        }
        replaceSelectedShapes(with: output)
        statusMessage = "Circular copy: \(sel.count) shape(s) → \(output.count) copies (\(count)×)"
        return true
    }

    // MARK: - Keyhole gadget (H02, SPK-0907)

    /// Add a keyhole-slot vector (circle + tangent shaft slot) for wall
    /// hanging, placed with the slot bottom at the design origin. Users move
    /// it with the transform tools. Undo + dirty via `addShapes`.
    @discardableResult
    func addKeyhole(screwHeadDiameterMm: Double, shaftDiameterMm: Double) -> Bool {
        guard let shape = KeyholeGadget.keyholeShape(
            screwHeadDiameterMm: screwHeadDiameterMm,
            shaftDiameterMm: shaftDiameterMm
        ) else {
            statusMessage = "Keyhole: shaft diameter must be smaller than the head"
            return false
        }
        registerUndoPoint()
        addShapes([shape])
        statusMessage = "Keyhole added (head Ø \(String(format: "%.1f", screwHeadDiameterMm))mm, shaft Ø \(String(format: "%.1f", shaftDiameterMm))mm) — profile-cut it from Cut"
        return true
    }

    /// Nudge every selected shape by (dx, dy) mm.
    @discardableResult
    func applyNudge(dx: Double, dy: Double) -> Bool {
        let indices = expandedSelectionIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Nudge needs a selected shape"
            return false
        }
        let output = sel.map { $0.translated(by: dx, dy) }
        replaceSelectedShapes(with: output, at: indices.sorted())
        statusMessage = String(format: "Nudged %d shape(s) by (%.2f, %.2f) mm", sel.count, dx, dy)
        return true
    }

    /// Nudge every selected shape +1 mm in X.
    @discardableResult
    func applyNudgeX() -> Bool { applyNudge(dx: 1, dy: 0) }

    /// Mirror selected shapes across the vertical centerline of the selection.
    @discardableResult
    func applyFlipHorizontal() -> Bool {
        let indices = expandedSelectionIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Flip needs a selected shape"
            return false
        }
        guard let centroid = selectionCentroid(of: sel) else {
            statusMessage = "Flip needs a selection with geometry"
            return false
        }
        let output = ShapeTransformer().flipHorizontal(shapes: sel, about: centroid)
        replaceSelectedShapes(with: output, at: indices.sorted())
        statusMessage = "Flipped \(sel.count) shape(s) horizontally across the selection centerline"
        return true
    }

    /// Rotate selected shapes by `degrees` CCW around the selection centroid.
    @discardableResult
    func applyRotate(degrees: Double) -> Bool {
        let indices = expandedSelectionIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Rotate needs a selected shape"
            return false
        }
        guard let centroid = selectionCentroid(of: sel) else {
            statusMessage = "Rotate needs a selection with geometry"
            return false
        }
        let output = ShapeTransformer().rotate(shapes: sel, angle: degrees, about: centroid)
        replaceSelectedShapes(with: output, at: indices.sorted())
        statusMessage = "Rotated \(sel.count) shape(s) \(Int(degrees))° around selection centroid"
        return true
    }

    @discardableResult
    func applyRotate90() -> Bool { applyRotate(degrees: 90) }

    /// Scale selected shapes uniformly about the selection centroid.
    @discardableResult
    func applyScale(factor: Double) -> Bool {
        let indices = expandedSelectionIndices.sorted()
        let sel = indices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        guard !sel.isEmpty else {
            statusMessage = "Scale needs a selected shape"
            return false
        }
        guard let centroid = selectionCentroid(of: sel) else {
            statusMessage = "Scale needs a selection with geometry"
            return false
        }
        let output = ShapeTransformer().scale(shapes: sel, factor: factor, about: centroid)
        replaceSelectedShapes(with: output, at: indices.sorted())
        statusMessage = String(
            format: "Scaled %d shape(s) by %.2f× around selection centroid",
            sel.count, factor
        )
        return true
    }

    @discardableResult
    func applyScale110() -> Bool { applyScale(factor: 1.1) }

    /// Trim: clip every selected OPEN vector to the union bounds of the
    /// selected CLOSED shapes (the boundary). The boundary shapes stay in
    /// place; each open vector is replaced by its clipped pieces (SPK-1101d).
    /// Selection is updated to the trimmed results plus the boundaries.
    @discardableResult
    func applyTrimToSelection() -> Bool {
        let indices = selectedShapeIndices.sorted()
        guard !indices.isEmpty, indices.allSatisfy({ shapes.indices.contains($0) }) else {
            statusMessage = "Trim needs a selected shape"
            return false
        }

        // Boundary = union bbox of selected closed shapes; targets = open vectors.
        var boundary: Rect?
        var targetIndices: [Int] = []
        for index in indices {
            let shape = shapes[index]
            if shape.isClosedShape {
                let r = shape.boundingRect
                if var box = boundary {
                    box = Rect(
                        minX: min(box.minX, r.minX), minY: min(box.minY, r.minY),
                        maxX: max(box.maxX, r.maxX), maxY: max(box.maxY, r.maxY)
                    )
                    boundary = box
                } else {
                    boundary = r
                }
            } else {
                targetIndices.append(index)
            }
        }

        guard let box = boundary, !targetIndices.isEmpty else {
            statusMessage = "Trim needs a closed shape (boundary) + open vectors to trim"
            return false
        }

        registerUndoPoint()

        // Clip each open target; keep pieces that differ from the input.
        let piecesByTarget: [[VectorShape]] = targetIndices.map { index in
            let pieces = ShapeJoinEngine.trimToBox(shapes[index], in: box)
            if pieces.count == 1, pieces[0] == shapes[index] {
                return []
            }
            return pieces
        }
        let trimmedCount = piecesByTarget.filter { !$0.isEmpty }.count
        let flat = piecesByTarget.flatMap { $0 }

        // Remove targets highest-first, rebasing the surviving (boundary)
        // selection indices as indices above each removed target shift down.
        var keptSelection = selectedShapeIndices.filter { !targetIndices.contains($0) }
        for removed in targetIndices {
            keptSelection = Set(keptSelection.map { $0 > removed ? $0 - 1 : $0 })
        }
        for index in targetIndices.reversed() {
            shapes.remove(at: index)
            shapeLayerIDs.remove(at: index)
        }
        // Insert pieces at the lowest target index (same layer as the first
        // target), rebasing boundary indices above the insertion point.
        let insertAt = targetIndices.first ?? 0
        let resultLayerID = shapeLayerIDs.indices.contains(insertAt)
            ? shapeLayerIDs[insertAt]
            : (layers.first?.id ?? UUID())
        shapes.insert(contentsOf: flat, at: min(insertAt, shapes.count))
        shapeLayerIDs.insert(
            contentsOf: Array(repeating: resultLayerID, count: flat.count),
            at: min(insertAt, shapeLayerIDs.count)
        )
        if !flat.isEmpty {
            keptSelection = Set(keptSelection.map { $0 >= insertAt ? $0 + flat.count : $0 })
            keptSelection.formUnion(Set(insertAt..<(insertAt + flat.count)))
        }
        selectedShapeIndices = keptSelection
        syncLayerVectors()
        markDirty()
        statusMessage = trimmedCount == 0
            ? "Trim: nothing to trim (selection needs open vectors crossing the boundary)"
            : "Trimmed \(trimmedCount) shape(s) to the boundary bounds"
        return true
    }

    func addDemoRectangle() {
        let shape = VectorShape.rectangle(
            origin: ShopPilotGeometry.VectorPoint(x: 10, y: 10),
            width: 80,
            height: 50
        )
        addShapes([shape])
    }

    // MARK: - SVG import

    /// Import an SVG file into the session document.
    ///
    /// Reads the file, parses it via `SVGImporter` (viewBox-aware, paths +
    /// primitives), and adds every resulting shape to the document through the
    /// normal `addShapes` path (undo point, layer vectors, dirty flag, status).
    /// Returns the number of shapes imported.
    @discardableResult
    func importSVG(from url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let result = SVGImporter.parse(content)
        guard result.success else {
            let message = result.errors.first ?? "SVG import failed"
            statusMessage = message
            throw ImportError.svgParseFailed(message)
        }
        guard !result.shapes.isEmpty else {
            statusMessage = "No drawable shapes found in \(url.lastPathComponent)"
            return 0
        }
        addShapes(result.shapes)
        statusMessage = "Imported \(result.shapes.count) shape(s) from \(url.lastPathComponent)"
        return result.shapes.count
    }

    // MARK: - STL relief import (SPK-3D-spine-a)

    /// The imported STL relief (heightfield), if any. Persisted on the job.
    var stlHeightfield: HeightfieldData? {
        job.stlHeightfield
    }

    /// Import an ASCII STL file as a heightfield relief: parse + rasterize,
    /// store on the document, mark dirty. Returns the importer result.
    @discardableResult
    func importSTLHeightfield(from url: URL) throws -> STLHeightfieldResult {
        let result = STLHeightfieldImporter.importSTL(
            at: url.path,
            cellSizeMm: 1.0,
            scale: 1.0
        )
        guard result.success, let hf = result.heightfield else {
            statusMessage = "STL import failed: \(result.errorMessage ?? "unknown error")"
            return result
        }
        registerUndoPoint()
        job.stlHeightfield = hf
        markDirty()
        statusMessage = "STL relief imported: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
        return result
    }

    // MARK: - Bitmap relief import (SPK-0706)

    /// Import an image file as a heightfield relief: decode → grayscale →
    /// heightfield, store on the document, mark dirty. Reuses the SAME
    /// document relief slot as STL, so the Model stage + 3D rough/finish
    /// engines consume bitmap reliefs unchanged.
    @discardableResult
    func importBitmapHeightfield(from url: URL, config: BitmapHeightfieldConfig) -> BitmapHeightfieldResult {
        let result = BitmapHeightfieldImporter.decodeImage(at: url, config: config)
        guard result.success, let hf = result.heightfield else {
            statusMessage = "Image relief import failed: \(result.errorMessage ?? "unknown error")"
            return result
        }
        registerUndoPoint()
        job.stlHeightfield = hf
        markDirty()
        statusMessage = "Image relief imported: \(result.widthPx)×\(result.heightPx)px → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
        return result
    }

    // MARK: - OBJ / 3MF relief import (Tier-2 import breadth)

    /// Import an OBJ mesh as a heightfield relief into the SAME document
    /// relief slot as STL (mirrors `importSTLHeightfield`).
    @discardableResult
    func importOBJHeightfield(from url: URL) -> OBJHeightfieldResult {
        let result = OBJHeightfieldImporter.importOBJ(at: url.path, cellSizeMm: 1.0, scale: 1.0)
        guard result.success, let hf = result.heightfield else {
            statusMessage = "OBJ import failed: \(result.errorMessage ?? "unknown error")"
            return result
        }
        registerUndoPoint()
        job.stlHeightfield = hf
        markDirty()
        statusMessage = "OBJ relief imported: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
        return result
    }

    /// Import a 3MF model as a heightfield relief into the same slot.
    @discardableResult
    func import3MFHeightfield(from url: URL) -> ThreeMFImportResult {
        let result = ThreeMFImporter.import3MF(at: url.path, cellSizeMm: 1.0, scale: 1.0)
        guard result.success, let hf = result.heightfield else {
            statusMessage = "3MF import failed: \(result.errorMessage ?? "unknown error")"
            return result
        }
        registerUndoPoint()
        job.stlHeightfield = hf
        markDirty()
        statusMessage = "3MF relief imported: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
        return result
    }

    /// Import an EPS drawing as design vectors (addShapes). Undoable + dirty.
    @discardableResult
    func importEPSVectors(from url: URL) -> EPSImportResult {
        let result = EPSImporter.importEPS(at: url.path, scale: 1.0)
        guard result.success, !result.shapes.isEmpty else {
            statusMessage = "EPS import failed: \(result.errorMessage ?? "no vector paths found")"
            return result
        }
        registerUndoPoint()
        addShapes(result.shapes)
        statusMessage = "EPS imported: \(result.pathCount) path(s) → \(result.shapes.count) vector(s)"
        return result
    }

    /// Import a PDF's vector content streams as design vectors. Undoable.
    @discardableResult
    func importPDFVectors(from url: URL) -> PDFImportResult {
        let result = PDFImporter.importPDF(at: url.path, scale: 1.0)
        guard result.success, !result.shapes.isEmpty else {
            statusMessage = "PDF import failed: \(result.errorMessage ?? "no vector paths found")"
            return result
        }
        registerUndoPoint()
        addShapes(result.shapes)
        statusMessage = "PDF imported: \(result.pathCount) path(s) → \(result.shapes.count) vector(s)"
        return result
    }

    /// Import an AI file (EPS- or PDF-flavored) as design vectors. Undoable.
    @discardableResult
    func importAIVectors(from url: URL) -> AIImportResult {
        let result = AIImporter.importAI(at: url.path, scale: 1.0)
        guard result.success, !result.shapes.isEmpty else {
            statusMessage = "AI import failed: \(result.errorMessage ?? "no vector paths found")"
            return result
        }
        registerUndoPoint()
        addShapes(result.shapes)
        statusMessage = "AI imported: \(result.pathCount) path(s) (\(result.flavor)) → \(result.shapes.count) vector(s)"
        return result
    }

    /// Import an R12 DWG's LINE/CIRCLE/ARC/POINT entities as design vectors.
    /// Undoable + dirty.
    @discardableResult
    func importDWGShapes(from url: URL) -> DWGImportResult {
        let result = DWGImporter.importDWG(at: url.path, scale: 1.0)
        guard result.success, !result.shapes.isEmpty else {
            statusMessage = "DWG import failed: \(result.errorMessage ?? "no drawable entities found")"
            return result
        }
        registerUndoPoint()
        addShapes(result.shapes)
        statusMessage = "DWG imported: \(result.entityCount) entit(y/ies) → \(result.shapes.count) vector(s)"
        return result
    }

    // MARK: - Relief components (SPK-0700/0701 lean slice)
    /// The document's relief component stack (nil = single-relief doc).
    var reliefComponents: [ReliefComponent] {
        job.reliefComponents ?? []
    }

    /// Fold the visible components into the ACTIVE relief (`stlHeightfield`)
    /// with the real element-wise engine. Mirrors the sculpt pattern: undo
    /// point, markDirty, and dirty every Rough3D/Finish3D node so the next
    /// recalc regenerates from the composited surface. Returns true when the
    /// composition is usable.
    @discardableResult
    func recompositeRelief() -> Bool {
        let components = reliefComponents
        guard !components.isEmpty else {
            statusMessage = "No components to composite — add the active relief as a component first"
            return false
        }
        guard let merged = ComponentCompositor.composite(components) else {
            statusMessage = "Composite failed: component grids must be aligned (same cells, size, origin) — resampling is not supported yet"
            return false
        }
        registerUndoPoint()
        job.stlHeightfield = merged
        markDirty()
        for node in toolpathTree.allNodes where node.strategyKind == .rough3D || node.strategyKind == .finish3D {
            node.markDirty()
        }
        statusMessage = "Composited \(components.filter(\.visible).count) component(s) → \(merged.width)×\(merged.height) relief, max \(String(format: "%.1f", merged.maxHeight))mm"
        return true
    }

    /// Capture the CURRENT active relief as a named component (Add mode) and
    /// recomposite. The first capture seeds the stack; later imports then
    /// combine with it — the component combine workflow in lean form.
    @discardableResult
    func addComponentFromActiveRelief(named name: String) -> Bool {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No active relief — import an image or STL first"
            return false
        }
        registerUndoPoint()
        var stack = job.reliefComponents ?? []
        stack.append(ReliefComponent(name: name.isEmpty ? "Relief \(stack.count + 1)" : name, heightfield: hf))
        job.reliefComponents = stack
        markDirty()
        let ok = recompositeRelief()
        return ok
    }

    /// Change a component's combine mode and recomposite.
    @discardableResult
    func updateComponentMode(_ id: UUID, mode: OperationMode) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        stack[index].combineMode = mode
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// Toggle component visibility and recomposite.
    @discardableResult
    func toggleComponentVisibility(_ id: UUID) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        stack[index].visible.toggle()
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// SPK-0702 — set a component's dynamic props (height scale / tilt /
    /// fade). Undoable + dirty + recomposites so the Model view and the 3D
    /// toolpaths pick up the modified surface. Pass nil to leave a prop
    /// untouched; pass the identity value to clear it.
    @discardableResult
    func updateComponentModifiers(
        _ id: UUID,
        heightScale: Double? = nil,
        tiltAngleDegrees: Double? = nil,
        fadeAmount: Double? = nil,
        fadeDirection: FadeDirection? = nil
    ) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        if let heightScale { stack[index].heightScale = heightScale }
        if let tiltAngleDegrees { stack[index].tiltAngleDegrees = tiltAngleDegrees }
        if let fadeAmount { stack[index].fadeAmount = fadeAmount }
        if let fadeDirection { stack[index].fadeDirection = fadeDirection }
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// SPK-0703 — generate a parametric shape relief (angled/round/smooth/
    /// flat) into the component stack, aligned to the sheet footprint. The
    /// shape becomes a component so it composites with imported reliefs.
    @discardableResult
    func addShapeComponent(shapeType: ShapeType, params: ShapeParameters) -> Bool {
        guard let sheet = activeSheet else {
            statusMessage = "Add Shape needs a sheet — set up the job first"
            return false
        }
        let hf = ShapeReliefGenerator.generate(
            shapeType: shapeType,
            params: params,
            width: sheet.width,
            height: sheet.depth,   // sheet.depth = Y footprint; sheet.height is THICKNESS (was passing thickness — relief came out a 6mm strip)
            cellSizeMm: 1.0,
            maxHeight: min(sheet.height, 10.0)
        )
        registerUndoPoint()
        var stack = job.reliefComponents ?? []
        stack.append(ReliefComponent(
            name: "Shape — \(shapeType.displayName)",
            heightfield: hf,
            combineMode: .combineAdd
        ))
        job.reliefComponents = stack
        markDirty()
        statusMessage = "Added \(shapeType.displayName.lowercased()) shape component (\(hf.width)×\(hf.height) grid)"
        return recompositeRelief()
    }

    /// SPK-0712 — smooth a component's relief (Laplacian). Undoable + dirty.
    @discardableResult
    func smoothComponent(_ id: UUID, params: SmoothParams) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        stack[index].heightfield = ComponentOperationEngine.smooth(stack[index].heightfield, params: params)
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// SPK-0712 — emboss a component's relief (raised/recessed stamp).
    @discardableResult
    func embossComponent(_ id: UUID, params: EmbossParams) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        stack[index].heightfield = ComponentOperationEngine.emboss(stack[index].heightfield, params: params)
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// SPK-E22 — offset a component's relief (dilate/erode the solid form).
    /// Positive offsetMm grows the shell outward, negative insets it.
    @discardableResult
    func offsetComponent(_ id: UUID, offsetMm: Double) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        guard let result = ModelOffsetEngine.offset(
            heightfield: stack[index].heightfield,
            params: .init(offsetMm: offsetMm)
        ) else {
            statusMessage = "Offset failed — invalid grid"
            return false
        }
        registerUndoPoint()
        stack[index].heightfield = result.heightfield
        job.reliefComponents = stack
        markDirty()
        return recompositeRelief()
    }

    /// SPK-0712 — bake the visible component stack into the ACTIVE relief and
    /// clear the stack (the reference "Bake visible"): the composited surface
    /// becomes the document relief that 3D toolpaths cut.
    @discardableResult
    func bakeComponents() -> Bool {
        let stack = reliefComponents
        guard !stack.isEmpty else {
            statusMessage = "Bake needs components — add reliefs or shapes first"
            return false
        }
        guard let baked = ComponentOperationEngine.bake(stack) else {
            statusMessage = "Bake failed — component grids are misaligned"
            return false
        }
        registerUndoPoint()
        job.stlHeightfield = baked
        job.reliefComponents = nil
        markDirty()
        statusMessage = "Baked \(stack.count) component(s) into the active relief"
        return true
    }

    /// SPK-0712 — split the active relief at a horizontal plane; the part
    /// above the plane becomes the new relief (re-based to 0).
    @discardableResult
    func splitRelief(planeHeight: Double) -> Bool {
        guard let hf = job.stlHeightfield else {
            statusMessage = "Split needs a relief — import STL/OBJ/3MF or an image first"
            return false
        }
        registerUndoPoint()
        job.stlHeightfield = ComponentOperationEngine.split(hf, planeHeight: planeHeight)
        markDirty()
        statusMessage = String(format: "Split relief at %.1fmm — upper part kept (re-based to 0)", planeHeight)
        return true
    }

    /// SPK-0714 — two-rail sweep: sweep a profile between the FIRST TWO
    /// selected vectors (as rails) into a component. The swept strip becomes
    /// a ReliefComponent aligned to its own bounding box.
    @discardableResult
    func addSweepComponent(profile: SweepProfile, height: Double) -> Bool {
        let railVectors = vectors.filter { !$0.points.isEmpty }
        guard railVectors.count >= 2 else {
            statusMessage = "Sweep needs ≥2 vectors as rails — draw two polylines and select them"
            return false
        }
        let rail1 = railVectors[0].points.map { VectorPoint(x: $0.x, y: $0.y) }
        let rail2 = railVectors[1].points.map { VectorPoint(x: $0.x, y: $0.y) }
        guard let hf = SweepReliefEngine.sweep(
            rail1: rail1,
            rail2: rail2,
            profile: profile,
            height: height,
            cellSizeMm: 1.0
        ) else {
            statusMessage = "Sweep failed — rails need 2+ points each"
            return false
        }
        registerUndoPoint()
        var stack = job.reliefComponents ?? []
        stack.append(ReliefComponent(
            name: "Sweep — \(profile.displayName.lowercased())",
            heightfield: hf,
            combineMode: .combineAdd
        ))
        job.reliefComponents = stack
        markDirty()
        statusMessage = "Added sweep component (\(hf.width)×\(hf.height) grid, peak \(String(format: "%.1f", hf.maxHeight))mm)"
        return recompositeRelief()
    }

    /// Remove a component and recomposite (or clear the stack when last).
    @discardableResult
    func removeComponent(_ id: UUID) -> Bool {
        guard var stack = job.reliefComponents,
              let index = stack.firstIndex(where: { $0.id == id }) else {
            statusMessage = "Component not found"
            return false
        }
        registerUndoPoint()
        stack.remove(at: index)
        job.reliefComponents = stack.isEmpty ? nil : stack
        markDirty()
        return recompositeRelief()
    }

    // MARK: - SPK-0705 Interactive Shape Handles

    /// Create handles for a component (called when component is selected).
    func createHandlesForComponent(_ id: UUID) {
        handleManager.createHandles(for: id)
        statusMessage = "Handles created for component"
    }

    /// Clear all handles.
    func clearHandles() {
        handleManager.clearAll()
    }

    /// Apply a handle drag to the selected component.
    /// `recordUndo` is true only for the FIRST event of a drag gesture —
    /// per-event undo snapshots flood the undo stack with MB-sized heightfield
    /// grids (same rule as sculpt strokes).
    @discardableResult
    func applyHandleDrag(handleID: UUID, deltaX: Double, deltaY: Double, deltaZ: Double, recordUndo: Bool = true) -> Bool {
        guard let handle = handleManager.handles.first(where: { $0.id == handleID }) else {
            statusMessage = "Handle not found"
            return false
        }
        guard let component = job.reliefComponents?.first(where: { $0.id == handle.componentID }) else {
            statusMessage = "Component not found"
            return false
        }
        let delta = HandlePosition(x: deltaX, y: deltaY, z: deltaZ)
        guard let newHF = handleManager.applyHandle(to: component, handle: handle, delta: delta) else {
            statusMessage = "Handle manipulation failed"
            return false
        }
        if recordUndo { registerUndoPoint() }
        var stack = job.reliefComponents ?? []
        if let idx = stack.firstIndex(where: { $0.id == handle.componentID }) {
            stack[idx].heightfield = newHF
            job.reliefComponents = stack
        }
        markDirty()
        return recompositeRelief()
    }

    /// ⌘K "Import Image Relief…" / Model-stage button: pick an image and
    /// convert it to a heightmap. A small config alert sets max height,
    /// mm-per-pixel scale and invert before import (SPK-0706).
    func importBitmapHeightfieldFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Image Relief"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Image → Heightmap"
        alert.informativeText = "Brightness becomes height: white = peak, black = floor."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let maxHeightField = NSTextField(string: "10.0")
        maxHeightField.placeholderString = "Max height (mm)"
        let mmPerPxField = NSTextField(string: "1.0")
        mmPerPxField.placeholderString = "mm per pixel"
        let invertBox = NSButton(checkboxWithTitle: "Invert (dark = peak)", target: nil, action: nil)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(NSTextField(labelWithString: "Max height (mm):"))
        stack.addArrangedSubview(maxHeightField)
        stack.addArrangedSubview(NSTextField(labelWithString: "mm per pixel:"))
        stack.addArrangedSubview(mmPerPxField)
        stack.addArrangedSubview(invertBox)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let config = BitmapHeightfieldConfig(
            mmPerPixel: Double(mmPerPxField.stringValue) ?? 1.0,
            maxHeightMm: Double(maxHeightField.stringValue) ?? 10.0,
            invert: invertBox.state == .on,
            smoothingPasses: 1,
            maxCells: 600
        )
        let result = importBitmapHeightfield(from: url, config: config)
        selectedStage = .model
        if !result.success {
            statusMessage = "Image relief import failed: \(result.errorMessage ?? "unknown error")"
        }
    }

    // MARK: - SPK-1900a / SPK-1900e (photo → heightfield engines)

    /// Decode an image file to a row-major luminance grid (0..1) using the
    /// same ImageIO path as the bitmap-relief importer. Rows = image Y.
    static func decodeLuminanceGrid(from url: URL) -> [[Double]]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let pixels = BitmapHeightfieldImporter.grayscalePixels(from: cg)
        guard pixels.count == cg.width * cg.height else { return nil }
        var rows: [[Double]] = []
        for r in 0..<cg.height {
            rows.append(Array(pixels[r * cg.width..<(r + 1) * cg.width]))
        }
        return rows
    }

    /// Shared tail for the two photo engines: store the generated grid as the
    /// document relief (same slot as STL/image import), hop to Model stage,
    /// and dirty every 3D node so recalc regenerates from it.
    private func adoptGeneratedRelief(_ hf: HeightfieldData, label: String) {
        registerUndoPoint()
        job.stlHeightfield = hf
        markDirty()
        selectedStage = .model
        for node in toolpathTree.allNodes where node.strategyKind == .rough3D || node.strategyKind == .finish3D {
            node.markDirty()
        }
        statusMessage = "\(label): \(hf.width)×\(hf.height) grid, \(String(format: "%.0f", Double(hf.width) * hf.cellSizeMm))×\(String(format: "%.0f", Double(hf.height) * hf.cellSizeMm))mm"
    }

    /// ⌘K "Photo Lithophane…" / Model-stage button: pick a photo, map its
    /// light transmission to thickness (bright = thin), and load it as the
    /// relief. Cut it with Rough/Finish 3D like any other relief.
    func generateLithophaneFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Photo Lithophane"
        guard panel.runModal() == .OK, let url = panel.url,
              let rows = Self.decodeLuminanceGrid(from: url) else {
            statusMessage = "Lithophane: could not read that image"
            return
        }
        var params = LithophaneParams()
        params.mode = .lithophaneThickness
        params.gridResolution = 600 // match the importer's ~600-cell budget
        adoptGeneratedRelief(LithophaneEngine.generateHeightfield(luminance: rows, params: params),
                             label: "Lithophane")
    }

    /// ⌘K "Image to Relief…" — Carveco-style auto-levels + smoothing +
    /// detail boost over a photo, landing in the standard relief slot.
    func generateImageToReliefFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Image to Relief"
        guard panel.runModal() == .OK, let url = panel.url,
              let rows = Self.decodeLuminanceGrid(from: url) else {
            statusMessage = "Image to Relief: could not read that image"
            return
        }
        var params = ImageToReliefParams()
        params.gridResolution = 600
        adoptGeneratedRelief(ImageToReliefEngine.generateHeightfield(luminance: rows, params: params),
                             label: "Image relief")
    }

    // MARK: - Sculpt (SPK-0713 lean slice)

    /// Apply one sculpt stroke to the document relief. Returns the result
    /// (new heightfield + affected-cell count) or nil when no relief is
    /// loaded. Registers an undo point, stores the new grid, marks the
    /// document dirty and dirties every 3D toolpath node so the next recalc
    /// regenerates from the sculpted surface.
    @discardableResult
    func applySculptStroke(_ stroke: SculptStrokeParams, recordUndo: Bool = true) -> SculptStrokeResult? {
        guard let hf = job.stlHeightfield else {
            statusMessage = "Sculpt: import an STL or image relief first"
            return nil
        }
        if recordUndo {
            registerUndoPoint()
        }
        let result = SculptEngine.applyStroke(stroke, to: hf)
        job.stlHeightfield = result.heightfield
        markDirty()
        for node in toolpathTree.allNodes where node.strategyKind == .rough3D || node.strategyKind == .finish3D {
            node.markDirty()
        }
        statusMessage = "Sculpt \(stroke.tool.rawValue): \(result.cellsAffected) cells, peak \(String(format: "%.1f", result.maxHeight))mm"
        return result
    }

    // MARK: - DXF import (SPK-1101g)

    /// Import an ASCII DXF file into the session document.
    ///
    /// Reads the file, parses it via `DXFParser` (LINE / LWPOLYLINE / CIRCLE /
    /// ARC entities; unsupported entities skipped tolerantly), and adds every
    /// resulting shape through the normal `addShapes` path (undo point, layer
    /// vectors, dirty flag, status). Returns the number of shapes imported.
    @discardableResult
    func importDXF(from url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let result = DXFParser.parse(content)
        guard !result.shapes.isEmpty else {
            statusMessage = "No drawable entities found in \(url.lastPathComponent) (LINE/Polyline/Circle/Arc only)"
            return 0
        }
        addShapes(result.shapes)
        let skipped = result.errors.isEmpty ? "" : " — \(result.errors.count) entity warning(s)"
        statusMessage = "Imported \(result.shapes.count) shape(s) from \(url.lastPathComponent)\(skipped)"
        return result.shapes.count
    }

    // MARK: - Selection

    func selectVector(_ id: UUID) {
        selectedVectorIDs.insert(id)
    }

    func deselectVector(_ id: UUID) {
        selectedVectorIDs.remove(id)
    }

    func toggleVectorSelection(_ id: UUID) {
        if selectedVectorIDs.contains(id) {
            selectedVectorIDs.remove(id)
        } else {
            selectedVectorIDs.insert(id)
        }
    }

    func clearSelection() {
        selectedVectorIDs.removeAll()
        selectedShapeIndices.removeAll()
        selection = .none
    }

    // MARK: - Vector Preflight Doctor (SPK-0211 + SPK-0212)

    /// Run the vector preflight doctor on the current design shapes. Returns
    /// the report; also stashes it on the session so the Design UI can render
    /// it without re-running.
    @discardableResult
    func runPreflight() -> PreflightReport {
        let report = VectorPreflight.check(shapes: shapes)
        lastPreflightReport = report
        if report.issues.isEmpty {
            statusMessage = "Preflight: \(shapes.count) shape(s) — no issues found"
        } else {
            let errors = report.issues.filter { $0.severity == .error }.count
            let warnings = report.issues.filter { $0.severity == .warning }.count
            statusMessage = "Preflight: \(report.issues.count) issue(s) — \(errors) error(s), \(warnings) warning(s)"
        }
        return report
    }

    /// Select the shapes affected by a preflight issue (fix CTA).
    func selectPreflightIssue(_ issue: PreflightResult) {
        guard !issue.affectedShapeIndices.isEmpty else { return }
        selectedShapeIndices = Set(issue.affectedShapeIndices.filter { shapes.indices.contains($0) })
        selection = .none
        statusMessage = issue.suggestedFix ?? issue.message
    }

    var hasSelection: Bool { !selectedVectorIDs.isEmpty || !selectedShapeIndices.isEmpty }

    // MARK: - Expanded vector validator (SPK-0806)

    /// Run the EXPANDED batch validator (topology/geometry/precision checks,
    /// fix actions) over every design path. Mirrors the preflight doctor but
    /// with the full `VectorValidator` rule set; stashes the result for UI.
    @discardableResult
    func runVectorValidation() -> BatchVectorValidationResult? {
        let paths = vectors
        guard !paths.isEmpty else {
            statusMessage = "Vector validation: no vectors to check"
            return nil
        }
        let shapeData = paths.map { path -> VectorShapeData in
            VectorShapeData(
                id: path.id,
                points: path.points,
                isClosed: path.isClosed,
                shapeType: path.isClosed ? .freehand : .line
            )
        }
        let result = VectorValidator.validateBatch(shapes: shapeData)
        lastVectorValidation = result
        statusMessage = result.summary
        return result
    }

    // MARK: - Toolpath preflight (SPK-FM-R013/R014/R019, export gate)

    /// Expert dismissals for toolpath preflight issues, session-scoped (same
    /// one-shot honesty contract as ExportBlocker's expert override — SPK-0603).
    @Published var toolpathPreflightDismissed: Set<UUID> = []

    /// Keep-out zones (SPK-0308): toolpaths must not enter active zones.
    @Published var keepOutZones: [KeepOutZone] = []

    /// Run the toolpath preflight rules over the tree with the document's
    /// design vectors and sheet material. Blocks export on `.error` issues.
    func exportPreflightIssues() -> [ToolpathPreflightIssue] {
        let materialThickness = activeSheet?.height ?? 25.0
        // R014: the active machine profile decides whether the table holds the
        // work down (no vacuum → through-cuts need tabs).
        let vacuum = machineProfiles.profiles.first?.vacuumHoldDown ?? false
        var issues = ToolpathPreflight.checkTree(
            toolpathTree,
            vectors: vectors,
            materialThicknessMm: materialThickness,
            dismissedNodeIDs: toolpathPreflightDismissed,
            vacuumHoldDown: vacuum
        )
        // R017 (FM-10): measured material thickness vs the job setup drifts
        // beyond tolerance → warn with a "Use Measured Value" CTA.
        let measured = machineProfiles.profiles.first?.measuredThicknessMm
        if let drift = MachineStartPreflight.thicknessDrift(
            jobThicknessMm: materialThickness,
            measuredThicknessMm: measured
        ) {
            issues.append(drift)
        }
        // R019 (FM-12): a multi-tool tree saved to ONE file with a post that
        // cannot change tools mid-file → error (blocks save), split CTA.
        let post = machineProfiles.profiles.first?.autoPostProcessorType ?? .grbl
        if let multiTool = ToolpathPreflight.multiToolSingleFile(
            tree: toolpathTree,
            postSupportsToolChange: post.supportsToolChange
        ) {
            issues.append(multiTool)
        }
        // SPK-0308: any cut segment entering an active keep-out zone.
        if !keepOutZones.isEmpty {
            for node in toolpathTree.allNodes where node.isOperation {
                let gcode = (node.toolpathResult ?? "").components(separatedBy: .newlines)
                if let violation = ToolpathPreflight.keepOutZoneViolation(
                    nodeName: node.name,
                    zones: keepOutZones,
                    gcodeLines: gcode,
                    nodeID: node.id
                ) {
                    issues.append(violation)
                }
            }
        }
        return issues
    }

    // MARK: - Keep-out zones (SPK-0308)

    /// Add a keep-out zone (persists with the job, marks the document dirty).
    func addKeepOutZone(_ zone: KeepOutZone) {
        keepOutZones.append(zone)
        job.keepOutZones = keepOutZones
        markDirty()
    }

    /// Remove a keep-out zone by id.
    @discardableResult
    func removeKeepOutZone(id: UUID) -> Bool {
        guard let index = keepOutZones.firstIndex(where: { $0.id == id }) else { return false }
        keepOutZones.remove(at: index)
        job.keepOutZones = keepOutZones
        markDirty()
        return true
    }

    /// Toggle a zone's active flag (inactive zones are ignored by the check).
    func toggleKeepOutZone(id: UUID) {
        guard let index = keepOutZones.firstIndex(where: { $0.id == id }) else { return }
        keepOutZones[index].isActive.toggle()
        job.keepOutZones = keepOutZones
        markDirty()
    }

    /// Ordered per-tool G-code groups for the R019 split CTA: every operation
    /// node's computed G-code bucketed by its assigned tool, in first-appearance
    /// order (nil toolID → "Unassigned" bucket).
    func toolpathGroupsByTool() -> [(toolName: String, gcode: [String])] {
        var order: [String] = []
        var buckets: [String: [String]] = [:]
        for node in toolpathTree.allNodes where node.isOperation {
            let name: String
            if let toolID = node.toolID, let tool = toolDatabase.tool(withID: toolID) {
                name = tool.name
            } else {
                name = "Unassigned"
            }
            if buckets[name] == nil { order.append(name) }
            let gcode = (node.toolpathResult ?? "").split(whereSeparator: \.isNewline).map(String.init)
            buckets[name, default: []].append(contentsOf: gcode)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// SPK-1135 — build the printable job-sheet data from the live document:
    /// job name, first sheet's material + dimensions, and one row per
    /// operation node (name, strategy label, assigned tool, feed/depth from
    /// the node's stored params, estimated time).
    func buildJobSheetData() -> JobSheetData {
        let sheet = activeSheet
        let info: [ToolpathInfo] = toolpathTree.allNodes.filter(\.isOperation).map { node in
            let toolName: String
            if let toolID = node.toolID, let tool = toolDatabase.tool(withID: toolID) {
                toolName = tool.name
            } else {
                toolName = "—"
            }
            return ToolpathInfo(
                name: node.name,
                type: .fromStrategyLabel(node.typeLabel),
                tool: toolName,
                feedRate: node.paramFeedRate ?? 0,
                depth: node.paramCutDepth ?? 0,
                estimatedTime: node.estimatedTimeSeconds
            )
        }
        return JobSheetData(
            jobName: job.name,
            material: sheet?.material?.name ?? "—",
            sheetWidth: sheet?.width ?? 0,
            sheetHeight: sheet?.depth ?? 0,
            toolpaths: info,
            createdAt: .now,
            notes: ""
        )
    }

    /// SPK-1135 — fill the bundled HTML template from the live document.
    /// The app renders the returned HTML to PDF (WebKit createPDF) and
    /// writes it where the user chose.
    func jobSheetHTML() -> String {
        JobSheetHTMLTemplateEngine.fill(data: buildJobSheetData())
    }

    /// R017 fix CTA: adopt the machine profile's measured material thickness
    /// into the job sheet (the honest "update job thickness" action).
    func applyMeasuredThickness() {
        guard let measured = machineProfiles.profiles.first?.measuredThicknessMm,
              var sheet = activeSheet else {
            statusMessage = "No measured thickness to apply"
            return
        }
        sheet.height = measured
        job.sheets[activeSheetIndex] = sheet
        markDirty()
        statusMessage = String(format: "Job thickness updated to the measured %.2fmm — recalculate toolpaths", measured)
    }

    /// R013 fix CTA: enable the V-Carve flat-bottom floor on the node,
    /// prefilled to keep the carve off the material's back side. The node is
    /// marked dirty — the export gate blocks until the user recalculates
    /// (the fix persists through `paramsJSON` on recalc/save).
    func applyFlatDepthFix(nodeID: UUID) {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.isVCarveOperation,
              let paramsJSON = node.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              var params = try? JSONDecoder().decode(VCarveParams.self, from: paramsData) else {
            statusMessage = "No V-Carve params to fix"
            return
        }
        let materialThickness = activeSheet?.height ?? 25.0
        let recommended = max(0.1, materialThickness - ToolpathPreflight.flatDepthSafetyMarginMm)
        params.flatBottomMode = true
        params.maxDepthOfCutMm = min(params.maxDepthOfCutMm, recommended)
        node.paramsJSON = encodeParams(params)
        node.markDirty()
        statusMessage = "Flat depth set on \(node.name) — recalculate to regenerate the toolpath"
        markDirty()
    }

    /// R013 secondary CTA: accept the risk for this node this session (the
    /// override does not survive reopen — same as the expert override).
    func dismissPunchThrough(nodeID: UUID) {
        toolpathPreflightDismissed.insert(nodeID)
        statusMessage = "Punch-through warning dismissed for this session"
    }

    /// R014 fix CTA: enable tabs on the through-cut profile node (default
    /// geometry: length 6mm / thickness 3mm / spacing 25mm). The node is
    /// marked dirty — recalc regenerates with the tabs (the fix persists
    /// through `paramsJSON`).
    func applyAddTabsFix(nodeID: UUID) {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.isProfileOperation,
              let paramsJSON = node.paramsJSON,
              let paramsData = paramsJSON.data(using: .utf8),
              var params = try? JSONDecoder().decode(ProfileToolpathParams.self, from: paramsData) else {
            statusMessage = "No Profile params to fix"
            return
        }
        params.addTabs = true
        node.paramsJSON = encodeParams(params)
        node.markDirty()
        statusMessage = "Tabs added to \(node.name) — recalculate to regenerate the toolpath"
        markDirty()
    }

    // MARK: - Shape selection (design canvas)

    /// Select a single shape by index (replaces the selection).
    func selectShape(_ index: Int) {
        selectedShapeIndices = [index]
        selection = .none
    }

    /// Toggle a shape in/out of the canvas selection.
    func toggleShapeSelection(_ index: Int) {
        if selectedShapeIndices.contains(index) {
            selectedShapeIndices.remove(index)
        } else {
            selectedShapeIndices.insert(index)
        }
    }

    /// Clear the shape selection only (keeps layer/vector selection intact).
    func clearShapeSelection() {
        selectedShapeIndices.removeAll()
    }

    // MARK: - Toolpaths

    /// Select a toolpath tree node (nil clears the selection).
    func selectToolpath(_ id: UUID?) {
        selectedToolpathID = id
        selection = id.map { .toolpath($0) } ?? .none
    }

    // MARK: - Smart part selection (SPK-1203)

    /// Select the whole PART a shape belongs to: closed shapes that touch or
    /// overlap (within 0.5 mm) are one part. Single click → whole assembly,
    /// no manual grouping — the Aspire 12.5 smart-selection pattern.
    @discardableResult
    func smartSelectPart(containing shapeIndex: Int) -> Bool {
        guard shapes.indices.contains(shapeIndex) else { return false }
        let parts = PartDetector.detectParts(of: shapes, tolerance: 0.5) { shape in
            // Only closed shapes join parts (open paths are separate).
            switch shape {
            case .freehand(let pts): return pts.count >= 3
            default: return true
            }
        }
        guard let part = PartDetector.part(containing: shapeIndex, in: parts) else {
            selectedShapeIndices = [shapeIndex]
            return true
        }
        selectedShapeIndices = Set(part.shapeIndices)
        statusMessage = "Selected part — \(part.shapeIndices.count) shape(s)"
        return true
    }

    /// Delete a toolpath node from the tree (any depth, undoable, marks dirty).
    @discardableResult
    func deleteToolpath(id: UUID) -> Bool {
        guard id != toolpathTree.root.id,
              toolpathTree.findNode(id: id) != nil else {
            statusMessage = "Nothing to delete"
            return false
        }
        registerUndoPoint()
        guard toolpathTree.removeNode(id: id) else { return false }
        if selectedToolpathID == id {
            selectedToolpathID = nil
            selection = .none
        }
        statusMessage = "Deleted toolpath"
        lastToolpathSummary = "\(toolpaths.count) toolpath(s) remaining"
        markDirty()
        return true
    }

    // MARK: - Context-menu actions (SPK-1204)

    /// Recalculate ONE toolpath node: marks it dirty, then runs the shared
    /// dirty-recalc — only this node regenerates (its siblings are clean).
    @discardableResult
    func recalculateToolpath(id: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: id),
              case .operation = node.type else {
            statusMessage = "No toolpath operation to recalculate"
            return false
        }
        node.markDirty()
        let count = recalculateDirtyToolpaths()
        statusMessage = count > 0
            ? "Recalculated “\(node.name)”"
            : "“\(node.name)” has nothing to recalculate"
        return count > 0
    }

    /// Select the source vectors a toolpath was cut from (the tree rows
    /// highlight them in Design). Falls back to selecting all vectors when
    /// no link is recorded.
    func selectToolpathSources(id: UUID) {
        let sourceIDs = linkManager.sourceVectorIds(forToolpathId: id.uuidString) ?? []
        if !sourceIDs.isEmpty {
            selectedVectorIDs = Set(sourceIDs)
            selection = .toolpath(id)
            statusMessage = "Selected \(sourceIDs.count) source vector(s) for this toolpath"
        } else {
            selectedVectorIDs = Set(vectors.map(\.id))
            statusMessage = "No link recorded — selected all vectors"
        }
    }

    /// Duplicate a toolpath node (same params + result, new node under the
    /// same parent). Undoable + marks dirty.
    @discardableResult
    func duplicateToolpath(id: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: id),
              case .operation = node.type,
              let parent = toolpathTree.parent(of: id) else {
            statusMessage = "No toolpath operation to duplicate"
            return false
        }
        registerUndoPoint()
        let copy = parent.addOperation(node.name + " copy")
        copy.toolID = node.toolID
        copy.paramsJSON = node.paramsJSON
        copy.toolpathResult = node.toolpathResult
        copy.estimatedTimeSeconds = node.estimatedTimeSeconds
        copy.markDirty() // the copy still needs a fresh compute against sources
        selectToolpath(copy.id)
        statusMessage = "Duplicated “\(node.name)”"
        markDirty()
        return true
    }

    // MARK: - Cut-layers table support (SPK-1201)

    /// The cut-layers table rows — a flat projection of the toolpath tree in
    /// tree order with tool names resolved.
    var cutLayerRows: [CutLayerRow] {
        CutLayerTableBuilder.build(tree: toolpathTree) { [weak self] toolID in
            self?.toolDatabase.tool(withID: toolID)?.name
        }
    }

    /// Inline feed-rate edit from the table: dispatches on the node's
    /// strategy, updates the right params struct, and regenerates the op.
    @discardableResult
    func setToolpathFeedRate(_ feed: Double, nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              case .operation = node.type else { return false }
        switch node.strategyKind {
        case .profile:
            var p = node.profileParams()
            p.feedRateMmPerMin = feed
            return applyProfileParams(p, to: nodeID)
        case .pocket:
            var p = node.pocketParams()
            p.feedRateMmPerMin = feed
            return applyPocketParams(p, to: nodeID)
        case .drill:
            var p = node.drillParams()
            p.feedRateMmPerMin = feed
            return applyDrillParams(p, to: nodeID)
        case .vcarve:
            var p = node.vcarveParams()
            p.feedRateMmPerMin = feed
            return applyVCarveParams(p, to: nodeID)
        default:
            return false // specialty ops keep their form-defined feeds
        }
    }

    /// Assign a tool (from `toolDatabase`) to a toolpath operation node.
    /// Marks the node dirty and records an undo point.
    @discardableResult
    func assignTool(_ toolID: UUID?, toToolpath nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              case .operation = node.type else {
            statusMessage = "No toolpath operation selected"
            return false
        }
        let tool = toolID.flatMap { toolDatabase.tool(withID: $0) }
        registerUndoPoint()
        node.assignTool(tool?.id)
        if let tool {
            statusMessage = "Assigned “\(tool.name)” to \(node.name)"
        } else {
            statusMessage = "Removed tool from \(node.name)"
        }
        markDirty()
        return true
    }

    // MARK: - Profile generation (SPK-1403c)

    /// Generate a Cut-out (Profile) toolpath. SPK-1403c: the orchestration is
    /// owned by `ProfileToolpathGenerator` (Core) — this facade just supplies
    /// the session hooks. SPK-UI-BUG-03: routed through the async witness so
    /// the ~35s engine compute runs off the main thread; the result still
    /// lands on the toolpath tree + G-code buffer, and the UI (stage rail,
    /// Cancel, AX) stays responsive during generate.
    func generateProfileToolpath() {
        isGeneratingToolpath = true
        ProfileToolpathGenerator.generateProfileAsync(on: self) { [weak self] _ in
            self?.isGeneratingToolpath = false
        }
    }

    // ProfileGeneratingSession (SPK-1403c).
    var activeSheetHeightMm: Double { activeSheet?.height ?? 6.0 }
    var toolpathNodeCount: Int { toolpathTree.allNodes.count }
    func setLastToolpathSummary(_ text: String) {
        lastToolpathSummary = text
        statusMessage = text
    }

    /// Apply Profile params to an operation: store them on the node and
    /// immediately regenerate its G-code with the REAL engine (SPK-1136a).
    /// The dirty badge clears because the result is fresh; the session buffer
    /// refreshes from the tree.
    @discardableResult
    func applyProfileParams(_ params: ProfileToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.isProfileOperation else {
            statusMessage = "Apply params: select a Profile operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = ProfileToolpathEngine.compute(
            vectors: vectors,
            params: params,
            material: nil,
            stockHeightMm: activeSheet?.height ?? 6.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "Profile: \(result.gcodeLines.count) lines, \(params.cutMode.displayName), " +
            "\(Int(result.estimatedTimeSeconds))s"
        statusMessage = lastToolpathSummary
        markDirty()
        return true
    }

    /// SPK-1403c — internal for the generator protocol witness.
    func encodeParams<T: Encodable>(_ params: T) -> String? {
        guard let data = try? JSONEncoder().encode(params) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - SPK-UI-BUG-03 — off-main single-op generate

    /// A single-op generate produced by a background engine compute and
    /// applied on the main actor (mirrors the SPK-1314 recalc compute/apply
    /// split). `paramsJSON` is encoded on the background queue from the value
    /// (pure JSONEncoder work — no session state).
    private struct AsyncGenerateResult {
        var nodeName: String
        var gcode: [String]
        var estimatedTime: Double
        var summary: String
        var paramsJSON: String?
        /// When false the node is NOT added (e.g. rest-machining found
        /// nothing to clear) — only the summary is published.
        var addNode: Bool = true
    }

    /// Run a single-op engine compute OFF the main thread, then wire the
    /// node + publish the summary on the main actor. `compute` must only
    /// touch VALUE snapshots taken on the main thread (never session state);
    /// `apply` runs on the main actor and may touch the session. Cut-stage
    /// generation no longer blocks the main thread (SPK-UI-BUG-03: Profile
    /// was ~35s on the Sign sample, freezing the whole app + AX server).
    private func generateToolpathAsync(
        compute: @escaping () -> AsyncGenerateResult,
        apply: @escaping (AsyncGenerateResult) -> Void = { _ in }
    ) {
        isGeneratingToolpath = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = compute()
            DispatchQueue.main.async {
                self.finishGenerateToolpath(result, apply: apply)
            }
        }
    }

    /// Apply an async-generate result on the main actor and refresh UI state.
    private func finishGenerateToolpath(_ result: AsyncGenerateResult, apply: (AsyncGenerateResult) -> Void) {
        if result.addNode {
            apply(result)
        }
        lastToolpathSummary = result.summary
        statusMessage = result.summary
        isGeneratingToolpath = false
    }

    /// JSON-encode an op's params to a string for the node — pure, so the
    /// background generate queue can call it without touching session state.
    private static func encodeParamsValue<T: Encodable>(_ params: T) -> String? {
        guard let data = try? JSONEncoder().encode(params) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Recalculate every dirty toolpath operation with the real engine
    /// (SPK-1102c + SPK-1102h-recalc). Profile/Pocket/Drill/V-Carve
    /// regenerate from the current session vectors + their stored params;
    /// unknown ops stay dirty. SPK-1133b: recalc resolves each op's assigned
    /// tool cut-data (feed/plunge/rpm/depth) against the sheet material and
    /// the active machine name, so per-machine cutting data flows into the
    /// G-code. The session G-code buffer is rebuilt from the clean tree.
    /// Returns the number of regenerated ops.
    @discardableResult
    /// SPK-1314 — async recalc: the heavy engine compute runs on a
    /// background queue (pure pass, no @Published mutation), then the
    /// results are applied on the main actor. Big jobs no longer freeze
    /// the UI. Falls back to the sync path when the compute returns nothing.
    func recalculateDirtyToolpathsAsync() {
        let dirtyBefore = toolpathTree.dirtyNodeCount
        guard dirtyBefore > 0 else {
            statusMessage = "No dirty toolpaths to recalculate"
            return
        }
        let vectorsSnapshot = vectors
        let material = activeSheet?.material
        let stockHeight = activeSheet?.height ?? 6.0
        let toolsSnapshot = toolDatabase.tools
        let heightfield = job.stlHeightfield
        let machine = activeMachineName
        isRecalculating = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let computed = self.toolpathTree.computeDirtyToolpathResults(
                vectors: vectorsSnapshot,
                material: material,
                stockHeightMm: stockHeight,
                tools: toolsSnapshot,
                heightfield: heightfield,
                machineName: machine
            )
            DispatchQueue.main.async {
                self.finishAsyncRecalc(computed)
            }
        }
    }

    /// Apply async-recalc results on the main actor and refresh UI state.
    private func finishAsyncRecalc(_ computed: [ToolpathNodeResult]) {
        let regenerated = toolpathTree.applyToolpathResults(computed)
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        let remaining = toolpathTree.dirtyNodeCount
        lastToolpathSummary = "\(gcodeLines.count) G-code lines · \(remaining) dirty"
        statusMessage = regenerated.isEmpty
            ? "Recalculated: no supported ops were dirty"
            : remaining == 0
                ? "Recalculated \(regenerated.count) dirty toolpath(s)"
                : "Recalculated \(regenerated.count) dirty toolpath(s); \(remaining) still dirty"
        isRecalculating = false
        markDirty()
    }

    func recalculateDirtyToolpaths() -> Int {
        let dirtyBefore = toolpathTree.dirtyNodeCount
        guard dirtyBefore > 0 else {
            statusMessage = "No dirty toolpaths to recalculate"
            return 0
        }
        let regenerated = toolpathTree.recalculateDirtyToolpaths(
            vectors: vectors,
            material: activeSheet?.material,
            stockHeightMm: activeSheet?.height ?? 6.0,
            tools: toolDatabase.tools,
            heightfield: job.stlHeightfield,
            machineName: activeMachineName
        )
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        let remaining = toolpathTree.dirtyNodeCount
        lastToolpathSummary = "\(gcodeLines.count) G-code lines · \(remaining) dirty"
        statusMessage = regenerated.isEmpty
            ? "Recalculated: no supported ops were dirty"
            : remaining == 0
                ? "Recalculated \(regenerated.count) dirty toolpath(s)"
                : "Recalculated \(regenerated.count) dirty toolpath(s); \(remaining) still dirty"
        markDirty()
        return regenerated.count
    }

    // MARK: - Add-op strategies (SPK-1102d)

    /// Add a computed toolpath node to the tree, refresh the session G-code
    /// buffer from the tree, select the node, jump to Cut, mark dirty.
    @discardableResult
    /// SPK-1403c — internal (not private) so `ProfileGeneratingSession`
    /// conformance can witness the node-creation hook for the extracted
    /// generator. Behavior unchanged.
    func addToolpathNode(
        named name: String,
        gcode: [String],
        estimatedTime: Double
    ) -> ToolpathTreeNode {
        let node = toolpathTree.addOperation(name)
        // SPK-1133: new ops start with the strategy's default tool (installer
        // catalog), so Cut uses real tools — recalc derives feeds from them.
        if node.toolID == nil {
            let strategy: String
            if name.hasPrefix("Rough 3D") {
                strategy = "Rough"
            } else if name.hasPrefix("Finish 3D") {
                strategy = "Finish"
            } else {
                // SPK-0900/0802 slices: specialty strategies use V-bit tools.
                let map: [String: String] = [
                    "Profile": "Profile", "Pocket": "Pocket", "Drill": "Drill", "V-Carve": "V-Carve",
                    "Prism": "V-Carve", "Fluting": "V-Carve", "Chamfer": "V-Carve", "Inlay": "V-Carve",
                    "Quick Engrave": "V-Carve", "Photo V-Carve": "V-Carve", "Texture": "V-Carve",
                    "Drag Knife": "V-Carve", "Sketch Carve": "V-Carve", "Rotary Wrap": "V-Carve",
                ]
                strategy = map.keys.first(where: { name.hasPrefix($0) }).flatMap { map[$0] } ?? name
            }
            node.toolID = toolDatabase.defaultTool(forStrategy: strategy)?.id
        }
        node.toolpathResult = gcode.joined(separator: "\n")
        node.estimatedTimeSeconds = estimatedTime
        // SPK-0319 lite: remember which source vectors this op was cut from.
        linkToolpathToSources(node)
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        selectToolpath(node.id)
        selectedStage = .cut
        markDirty()
        return node
    }

    /// SPK-1920g (H-402) — wasteboard surfacing: generate the facing program
    /// as an EXPLICIT tree node. Nothing streams automatically; the user must
    /// review, confirm preflight, and press Run Job like any other op.
    @discardableResult
    func generateWasteboardSurfacingToolpath(
        widthMm: Double? = nil,
        depthMm: Double? = nil
    ) -> ToolpathTreeNode? {
        let sheetW = widthMm ?? activeSheet?.width ?? 300
        let sheetD = depthMm ?? activeSheet?.depth ?? 200
        var params = WasteboardSurfacingParams()
        params.widthMm = sheetW
        params.depthMm = sheetD

        registerUndoPoint()
        let result = WasteboardSurfacingEngine.generate(params)
        let nodeCount = toolpathTree.allNodes.count
        // Time estimate: total cut length / feed + plunge/rapid overhead.
        let rows = WasteboardSurfacingEngine.rowCount(params)
        let passes = WasteboardSurfacingEngine.zPassCount(params)
        let cutLength = Double(rows) * max(0, params.widthMm - params.cutterDiameterMm) * Double(passes)
        let estimated = cutLength / max(1, params.feedRateMmPerMin) * 60 + Double(passes * rows) * 2

        let node = addToolpathNode(
            named: "Wasteboard Surface \(nodeCount)",
            gcode: result,
            estimatedTime: estimated
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Wasteboard surfacing ready — \(passes) Z pass(es), \(rows) rows. Review, then Run Job when the bed is clear."
        lastToolpathSummary = statusMessage
        markDirty()
        return node
    }

    // MARK: - Plugin strategies (SPK-1006 loadable ABI)

    /// Run a discovered plugin as a toolpath strategy: builds the job
    /// document from the live session, runs the plugin child process, and —
    /// on a valid output — injects its G-code as a new toolpath node.
    @discardableResult
    func runPluginStrategy(_ plugin: PluginStore.LoadedPlugin,
                           params: [String: String] = [:]) -> Bool {
        registerUndoPoint()
        var merged = params
        for decl in plugin.manifest.params where merged[decl.key] == nil {
            merged[decl.key] = decl.defaultValue
        }
        let sheet = activeSheet
        let doc = PluginJobDocument(
            jobName: job.name,
            stockWidthMm: sheet?.width ?? 304.8,
            stockDepthMm: sheet?.depth ?? 304.8,
            stockHeightMm: sheet?.height ?? 19.05,
            vectors: vectors.map { path in
                PluginVectorPath(
                    points: path.points.map { PluginVectorPoint(x: $0.x, y: $0.y) },
                    isClosed: path.isClosed
                )
            },
            params: merged
        )
        guard let output = PluginRunner.run(
            manifest: plugin.manifest,
            pluginDirectory: plugin.directory,
            document: doc
        ) else {
            statusMessage = "Plugin “\(plugin.manifest.name)” failed or timed out"
            return false
        }
        guard !output.gcodeLines.isEmpty else {
            statusMessage = "Plugin “\(plugin.manifest.name)” returned no G-code"
            return false
        }
        let node = addToolpathNode(
            named: "Plugin: \(plugin.manifest.name)",
            gcode: output.gcodeLines,
            estimatedTime: output.estimatedTimeSeconds
        )
        node.toolID = toolDatabase.defaultTool(forStrategy: "V-Carve")?.id
        statusMessage = "Plugin “\(plugin.manifest.name)” → \(output.gcodeLines.count) G-code lines"
        return true
    }

    /// Generate a Pocket toolpath from the closed session vectors (zigzag
    /// default) and add it to the tree. SPK-UI-BUG-03: engine compute runs
    /// off the main thread; node wiring applies on the main actor.
    func generatePocketToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = PocketToolpathParams()
            let result = PocketToolpathEngine.compute(
                vectors: vectorsSnapshot,
                params: params,
                material: nil,
                stockHeightMm: stockHeight
            )
            let summary = result.isTooSmall
                ? "Pocket: region too small for the tool — no cut generated"
                : "Pocket: \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Pocket \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params),
                addNode: !result.isTooSmall
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Pocket params to an operation: store them on the node and
    /// immediately regenerate its G-code with the REAL engine (SPK-1136b).
    /// The dirty badge clears because the result is fresh.
    @discardableResult
    func applyPocketParams(_ params: PocketToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.isPocketOperation else {
            statusMessage = "Apply params: select a Pocket operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = PocketToolpathEngine.compute(
            vectors: vectors,
            params: params,
            material: nil,
            stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "Pocket: \(result.gcodeLines.count) lines, \(params.clearanceMode.displayName), " +
            "\(Int(result.estimatedTimeSeconds))s"
        statusMessage = result.isTooSmall
            ? "Pocket: region too small for the tool — no cut generated"
            : lastToolpathSummary
        markDirty()
        return true
    }

    // MARK: - SPK-1910b — Trochoid Slot (generate / apply)

    /// Generate a trochoidal slotting toolpath from the closed session
    /// vectors and add it to the tree. Pro strategy — hidden in Beginner
    /// mode at the UI layer. SPK-UI-BUG-03: engine compute runs off the
    /// main thread.
    func generateTrochoidSlotToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import a closed slot corridor first"
            return
        }
        // SPK-DOGFOOD-03 — corridor selection: with a selection, only the
        // SELECTED closed shapes become the slot boundary (matches Profile/
        // Pocket selection semantics); with no selection, all closed shapes
        // are eligible (small designs, single-slot jobs).
        let selectedIdx = expandedSelectionIndices
        let sourceShapes: [VectorShape] = selectedIdx.isEmpty
            ? shapes
            : selectedIdx.sorted().compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        let vectorsSnapshot = GeometryBridge.toCorePaths(sourceShapes, layerIDs: shapeLayerIDs)
            .filter { $0.isClosed && !$0.points.isEmpty }
        guard !vectorsSnapshot.isEmpty else {
            statusMessage = "Trochoid Slot needs a CLOSED vector — the corridor boundary"
            return
        }
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = TrochoidSlotParams()
            let result = TrochoidSlotToolpathEngine.compute(
                vectors: vectorsSnapshot,
                params: params,
                material: nil,
                stockHeightMm: stockHeight
            )
            let summary = result.isTooNarrow
                ? "Trochoid Slot: corridor too narrow for the tool — no cut generated"
                : "Trochoid Slot: \(result.loopCount) loops × \(result.passCount) pass(es), \(result.gcodeLines.count) lines"
            return AsyncGenerateResult(
                nodeName: "Trochoid Slot \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params),
                addNode: !result.isTooNarrow
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
            // Trochoid slots use an end mill, not the default V-bit mapping.
            if let endMill = self.toolDatabase.tools.first(where: { $0.type == .endMill }) {
                node.toolID = endMill.id
            }
        }
    }

    /// Apply Trochoid Slot params to an operation: store them on the node and
    /// immediately regenerate its G-code with the real engine (SPK-1910b).
    @discardableResult
    func applyTrochoidSlotParams(_ params: TrochoidSlotParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.strategyKind == .trochoidSlot else {
            statusMessage = "Apply params: select a Trochoid Slot operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = TrochoidSlotToolpathEngine.compute(
            vectors: vectors.filter { $0.isClosed && !$0.points.isEmpty },
            params: params,
            material: nil,
            stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "Trochoid Slot: \(result.loopCount) loops × \(result.passCount) pass(es), " +
            "\(Int(result.estimatedTimeSeconds))s"
        statusMessage = result.isTooNarrow
            ? "Trochoid Slot: corridor too narrow for the tool — no cut generated"
            : lastToolpathSummary
        markDirty()
        return true
    }

    /// SPK-1920d (H-304) — apply Rough 3D params (including inverse mill) to an
    /// operation: store + regenerate with the REAL engine, clearing the dirty
    /// badge (mirrors the apply* family).
    @discardableResult
    func applyRough3DParams(_ params: HeightfieldRoughParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.strategyKind == .rough3D else {
            statusMessage = "Apply params: select a Rough 3D operation"
            return false
        }
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an STL or image first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = HeightfieldRoughEngine.compute(heightfield: hf, params: params)
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Rough 3D\(params.inverseMill ? " (inverse)" : ""): \(result.passCount) z-levels, ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Drill toolpath at the center of every closed vector
    /// (bounding-box centroid, default peck cycle) and add it to the tree.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateDrillToolpath() {
        let depth = -min(activeSheet?.height ?? 25.0, 10.0)
        let points: [DrillPoint] = vectors.compactMap { path in
            guard path.isClosed, !path.points.isEmpty else { return nil }
            let xs = path.points.map(\.x)
            let ys = path.points.map(\.y)
            return DrillPoint(
                x: (xs.min()! + xs.max()!) / 2,
                y: (ys.min()! + ys.max()!) / 2,
                zDepthMm: depth
            )
        }
        guard !points.isEmpty else {
            statusMessage = "Drill needs a closed vector — holes are placed at shape centers"
            return
        }
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = DrillToolpathParams()
            let result = DrillToolpathEngine.compute(
                points: points,
                params: params,
                material: nil,
                stockHeightMm: stockHeight
            )
            let summary = "Drill: \(result.pointCount) hole(s), \(result.gcodeLines.count) lines"
            return AsyncGenerateResult(
                nodeName: "Drill \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Drill params to an operation: store them on the node and
    /// immediately regenerate its G-code with the REAL engine (SPK-1136c).
    /// Point mapping honors the stored params (cut depth, dwell).
    @discardableResult
    func applyDrillParams(_ params: DrillToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.isDrillOperation else {
            statusMessage = "Apply params: select a Drill operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let points: [DrillPoint] = vectors.compactMap { path in
            guard path.isClosed, !path.points.isEmpty else { return nil }
            let xs = path.points.map(\.x)
            let ys = path.points.map(\.y)
            return DrillPoint(
                x: (xs.min()! + xs.max()!) / 2,
                y: (ys.min()! + ys.max()!) / 2,
                zDepthMm: -(params.startDepthMm + params.cutDepthMm),
                dwellSeconds: params.dwellAtBottom ? params.dwellTimeSeconds : 0
            )
        }
        guard !points.isEmpty else {
            statusMessage = "Drill needs at least one closed vector (holes at shape centers)"
            return false
        }
        let result = DrillToolpathEngine.compute(
            points: points,
            params: params,
            material: nil,
            stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "Drill: \(result.pointCount) hole(s), \(result.gcodeLines.count) lines, " +
            "\(params.cycleType.displayName)"
        statusMessage = lastToolpathSummary
        markDirty()
        return true
    }

    // MARK: - Drill Bank (parity F34)

    /// Generate a Drill Bank toolpath: a W×H grid of uniquely-numbered holes
    /// from default params, added to the tree. When closed vectors are
    /// selected the grid's origin is pinned to the selection centroid so the
    /// bank lands on the part.
    func generateDrillBankToolpath() {
        let params = DrillBankToolpathParams()
        let points = drillBankPoints(centeredOn: params)
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let result = DrillBankToolpathEngine.compute(
                points: points,
                params: params,
                stockHeightMm: stockHeight
            )
            let summary =
                "Drill Bank: \(result.pointCount) hole(s) (\(params.gridCols)×\(params.gridRows) grid), \(result.gcodeLines.count) lines"
            return AsyncGenerateResult(
                nodeName: "Drill Bank \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// SPK-H04 — wrapped fluting: flute straight lines around the rotary axis
    /// (flat X stays axial, flat Y wraps to A degrees). Uses the selected
    /// open vectors' endpoints as flute lines; falls back to a single
    /// center-line flute when no vectors are selected.
    func generateWrappedFluting() {
        var params = WrappedFlutingParams()
        // SPK-0903: job-level rotary setup supplies the stock Ø default.
        if let cfg = job.rotaryConfig {
            params.wrapDiameterMm = cfg.diameter
        }
        // Flute lines: use selected open polylines' segments; else a single
        // default flute along the job width. (Both read only session state
        // on the main thread — the engine gets value snapshots.)
        let selected = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        var flutePoints: [VectorPoint] = []
        if let first = selected.first, case .freehand(let pts) = first, pts.count >= 2 {
            flutePoints = pts
        } else {
            let w = activeSheet?.width ?? 100.0
            flutePoints = [VectorPoint(x: 0, y: 0), VectorPoint(x: w, y: 0)]
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let result = WrappedFlutingToolpathEngine.compute(points: flutePoints, params: params)
            let summary =
                "Wrapped Fluting: \(result.moveCount) move(s) around Ø\(String(format: "%.1f", params.wrapDiameterMm))mm, \(result.gcode.count) lines"
            return AsyncGenerateResult(
                nodeName: "Wrapped Fluting \(nodeCount)",
                gcode: result.gcode,
                estimatedTime: TimeInterval(result.moveCount) * 0.02,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Drill Bank params to an operation: store them on the node and
    /// immediately regenerate its G-code with the real engine.
    @discardableResult
    func applyDrillBankParams(_ params: DrillBankToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.strategyKind == .drillBank else {
            statusMessage = "Apply params: select a Drill Bank operation"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let points = drillBankPoints(centeredOn: params)
        let result = DrillBankToolpathEngine.compute(
            points: points,
            params: params,
            stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "Drill Bank: \(result.pointCount) hole(s) (\(params.gridCols)×\(params.gridRows) grid), " +
            "\(params.style.displayName)"
        statusMessage = lastToolpathSummary
        markDirty()
        return true
    }

    /// Grid points for a drill bank, pinned to the selection centroid when
    /// closed vectors are selected (nil otherwise = grid at its params origin).
    private func drillBankPoints(centeredOn params: DrillBankToolpathParams) -> [DrillPoint]? {
        let closed = vectors.filter { $0.isClosed && !$0.points.isEmpty }
        guard !closed.isEmpty else { return nil }
        let xs = closed.flatMap { $0.points.map(\.x) }
        let ys = closed.flatMap { $0.points.map(\.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        var centered = params
        centered.originX += (minX + maxX) / 2
        centered.originY += (minY + maxY) / 2
        return centered.gridPoints()
    }

    /// Generate a V-Carve toolpath from the session vectors (V-bit, default
    /// params) and add it to the tree. SPK-UI-BUG-03: the (heavy) engine
    /// compute runs off the main thread; the open-vector preflight gate stays
    /// synchronous on the main actor (it only inspects shapes).
    func generateVCarveToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        // SPK-0604 — preflight gate: V-Carve on open vectors is blocked with a
        // plain-English fix CTA (reuses the 0211/0212 preflight doctor).
        if let gateReport = VectorPreflight.vCarveGate(shapes: shapes) {
            lastPreflightReport = gateReport
            preflightPanelVisible = true
            let openCount = gateReport.issues.filter { $0.issue == .openPath }.count
            statusMessage = "V-Carve blocked: \(openCount) open vector(s) — close them in Design first"
            selectedStage = .design
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = VCarveParams()
            let result = VCarveEngine.compute(
                vectors: vectorsSnapshot,
                params: params,
                stockHeightMm: stockHeight
            )
            let summary = "V-Carve: \(result.gcodeLines.count) lines, \(result.passCount) pass(es)"
            return AsyncGenerateResult(
                nodeName: "V-Carve \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Generate a 3D ROUGH toolpath (z-level clearing) from the imported STL
    /// relief and add it to the tree (SPK-3D-spine-b). SPK-UI-BUG-03: the
    /// heightfield engine runs off the main thread.
    func generateRough3DToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No STL relief — import one via Design → STL Relief… first"
            return
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = HeightfieldRoughParams()
            let result = HeightfieldRoughEngine.compute(heightfield: hf, params: params)
            let summary = "Rough 3D: \(result.gcodeLines.count) lines, \(result.passCount) z-levels"
            return AsyncGenerateResult(
                nodeName: "Rough 3D \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Generate a 3D FINISH toolpath (surface-following) from the imported STL
    /// relief and add it to the tree (SPK-3D-spine-b). SPK-UI-BUG-03: the
    /// heightfield engine runs off the main thread.
    func generateFinish3DToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No STL relief — import one via Design → STL Relief… first"
            return
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = HeightfieldFinishParams()
            let result = HeightfieldFinishEngine.compute(heightfield: hf, params: params)
            let summary = "Finish 3D: \(result.gcodeLines.count) lines, \(result.passCount) rows"
            return AsyncGenerateResult(
                nodeName: "Finish 3D \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    // MARK: - SPK-0711 Zero plane + boundary

    /// Compute the work area (zero plane + boundary) from the component stack
    /// (or the active relief when no components exist). Reports the result in
    /// the status bar; returns the WorkArea for programmatic use.
    @discardableResult
    func computeWorkAreaFromComponents() -> WorkArea? {
        var boxes: [BoundingBox3D] = []
        let components = job.reliefComponents ?? []
        if !components.isEmpty {
            for component in components where component.visible {
                let b = component.heightfield.bounds
                boxes.append(BoundingBox3D(
                    minX: b.minX, minY: b.minY, minZ: 0,
                    maxX: b.maxX, maxY: b.maxY, maxZ: component.heightfield.maxHeight
                ))
            }
        } else if let hf = job.stlHeightfield {
            let b = hf.bounds
            boxes.append(BoundingBox3D(
                minX: b.minX, minY: b.minY, minZ: 0,
                maxX: b.maxX, maxY: b.maxY, maxZ: hf.maxHeight
            ))
        } else {
            statusMessage = "Work area: no relief or components — import an STL or add a component first"
            return nil
        }

        let area = ZeroPlaneAndBoundaryEngine.computeWorkArea(
            componentBoundingBoxes: boxes,
            zeroPlaneOffset: 0,
            boundarySafetyMargin: 5.0
        )
        let (valid, errors) = ZeroPlaneAndBoundaryEngine.validate(area)
        if valid {
            statusMessage = String(
                format: "Work area: %.1f×%.1f mm at origin (%.1f, %.1f), zero plane Z=%.2f",
                area.areaWidth, area.areaHeight, area.originX, area.originY, area.originZ
            )
        } else {
            statusMessage = "Work area invalid: \(errors.joined(separator: "; "))"
        }
        return area
    }

    // MARK: - Laser strategy (SPK-0906)

    /// Generate a LASER toolpath (cut/engrave G-code) from the first
    /// available design vector and add it to the tree. Falls back to a 10mm
    /// diamond path when no vectors exist yet.
    func generateLaserToolpath(mode: LaserMode, powerPercent: Double, speedMmPerMin: Double) -> Bool {
        let config = LaserEngine.createConfig(mode: mode, powerPercent: powerPercent, speedMmPerMin: speedMmPerMin)

        // Pull a closed path from the first available design vector.
        var path: [(Double, Double)] = []
        if let firstPath = vectors.first(where: { $0.points.count >= 2 }) {
            path = firstPath.points.map { ($0.x, $0.y) }
            if firstPath.isClosed, let firstPt = path.first,
               path.last!.0 != firstPt.0 || path.last!.1 != firstPt.1 {
                path.append(firstPt) // close the loop back to the start
            }
        }
        if path.count < 2 {
            // Fallback: 10mm square diamond (closed).
            path = [(0, 0), (5, 5), (0, 10), (-5, 5), (0, 0)]
        }

        var pathLength = 0.0
        for i in 1..<path.count {
            let dx = path[i].0 - path[i - 1].0
            let dy = path[i].1 - path[i - 1].1
            pathLength += (dx * dx + dy * dy).squareRoot()
        }

        registerUndoPoint()
        let result = LaserEngine.generateToolpath(config: config, pathLengthMm: pathLength)
        let gcode = LaserEngine.gcodeForMode(config: config, path: path)
        let node = addToolpathNode(
            named: "Laser \(mode.rawValue.capitalized) \(toolpathTree.allNodes.count)",
            gcode: gcode,
            estimatedTime: result.estimatedTimeMinutes * 60.0
        )
        node.paramsJSON = encodeParams(config)
        lastToolpathSummary = result.success
            ? "Laser \(mode.rawValue): \(gcode.count) lines, \(String(format: "%.1f", result.estimatedTimeMinutes)) min est, \(String(format: "%.0f", config.powerPercent))% power"
            : "Laser failed: \(result.errorMessage ?? "unknown error")"
        statusMessage = lastToolpathSummary
        return result.success
    }

    // MARK: - Laser fill & picture (SPK-2000c — cross-platform parity)

    /// Laser Fill: raster scanline fill over the closed vectors' bounds.
    /// Pure-data engine + tree node; streams through the normal Run Job
    /// discipline like every other op (no auto-run).
    func generateLaserFillToolpath(
        angleDegrees: Double = 0,
        lineSpacingMm: Double = 0.3,
        overscanMm: Double = 1.0,
        powerPercent: Double = 80,
        speedMmPerMin: Double = 3000
    ) {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import shapes to laser-fill first"
            return
        }
        let pathsSnapshot = vectors.map { $0.points }
        registerUndoPoint()
        let params = LaserFillParams(angleDegrees: angleDegrees, lineSpacingMm: lineSpacingMm,
                                     overscanMm: overscanMm, powerPercent: powerPercent,
                                     speedMmPerMin: speedMmPerMin)
        let result = LaserFillEngine.compute(paths: pathsSnapshot, params: params)
        guard result.success, let bounds = result.bounds else {
            statusMessage = "Laser Fill failed: \(result.errorMessage ?? "unknown error")"
            return
        }
        let widthMm = bounds.maxX - bounds.minY
        let timeMinutes = Double(result.scanlineCount) * widthMm / speedMmPerMin
        let node = addToolpathNode(
            named: "Laser Fill \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: timeMinutes * 60.0
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary = "Laser Fill: \(result.scanlineCount) scanlines, \(result.gcodeLines.count) lines"
        statusMessage = lastToolpathSummary
    }

    /// Laser Picture: power-modulated raster over the loaded relief heightfield
    /// (dark = more burn). Uses the STL/image relief already on the document —
    /// the same data Photo V-Carve consumes.
    func generateLaserPictureToolpath(
        targetWidthMm: Double? = nil,
        lineSpacingMm: Double = 0.25,
        maxPowerPercent: Double = 100,
        speedMmPerMin: Double = 2000
    ) {
        guard let hf = stlHeightfield else {
            statusMessage = "No image/relief loaded — import an image or STL in Model first"
            return
        }
        registerUndoPoint()
        let widthMm = Double(hf.width) * hf.cellSizeMm
        let target = targetWidthMm ?? min(widthMm, activeSheet?.width ?? widthMm)
        let params = LaserPictureParams(targetWidthMm: target,
                                        lineSpacingMm: lineSpacingMm,
                                        maxPowerPercent: maxPowerPercent,
                                        speedMmPerMin: speedMmPerMin)
        // Sample the relief into a grayscale grid (heights normalized to luminance).
        var lum: [UInt8] = []
        lum.reserveCapacity(hf.width * hf.height)
        let maxH = hf.heights.max() ?? 1
        let minH = hf.heights.min() ?? 0
        let span = max(1e-6, maxH - minH)
        for h in hf.heights {
            // Higher relief = darker pixel = more burn.
            let darkness = UInt8(max(0, min(255, Int((h - minH) / span * 255))))
            lum.append(darkness)
        }
        let grid = GrayscaleGrid(width: hf.width, height: hf.height, luminance: lum)
        let result = LaserPictureEngine.compute(grid: grid, params: params)
        guard result.success else {
            statusMessage = "Laser Picture failed: \(result.errorMessage ?? "unknown error")"
            return
        }
        let node = addToolpathNode(
            named: "Laser Picture \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: 0
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary = "Laser Picture: \(result.rasterRows) rows, \(result.burnedPixels) burned cells"
        statusMessage = lastToolpathSummary
    }

    // MARK: - Specialty strategies (SPK-0900 + SPK-0802 lean slices)

    /// Generate a Prism toolpath: parallel V-grooves across every closed
    /// vector (the prismatic sign effect) and add it to the tree.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generatePrismToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = PrismToolpathParams()
            let result = PrismToolpathEngine.compute(
                paths: vectorsSnapshot,
                params: params,
                stockHeightMm: stockHeight
            )
            let summary = result.featureCount > 0
                ? "Prism: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
                : "Prism: no closed vectors — the grooves raster needs closed shapes"
            return AsyncGenerateResult(
                nodeName: "Prism \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Generate a Fluting toolpath: the selected vectors ARE the flutes
    /// (draw parallel lines for a ribbed board), cut in step-down passes.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateFlutingToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw flute lines first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = FlutingToolpathParams()
            let result = FlutingToolpathEngine.compute(
                paths: vectorsSnapshot,
                params: params,
                stockHeightMm: stockHeight
            )
            let summary = result.featureCount > 0
                ? "Fluting: \(result.featureCount) flute(s), ~\(Int(result.estimatedTimeSeconds))s"
                : "Fluting: no usable vectors (need ≥ 2 points)"
            return AsyncGenerateResult(
                nodeName: "Fluting \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Generate a Chamfer toolpath: V-bevel on the selected edges.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateChamferToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select edges to chamfer"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = ChamferToolpathParams()
            let result = ChamferToolpathEngine.compute(
                paths: vectorsSnapshot,
                params: params,
                stockHeightMm: stockHeight
            )
            let summary = result.featureCount > 0
                ? "Chamfer: \(result.featureCount) edge(s), ~\(Int(result.estimatedTimeSeconds))s"
                : "Chamfer: no usable vectors"
            return AsyncGenerateResult(
                nodeName: "Chamfer \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Generate the female (pocket) or male (plug) half of a V-inlay.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateInlayToolpath(variant: InlayToolpathParams.Variant) {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select the inlay shape"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            var params = InlayToolpathParams()
            params.variant = variant
            let result: SpecialtyResult = variant == .pocket
                ? InlayToolpathEngine.computePocket(paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight)
                : InlayToolpathEngine.computePlug(paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight)
            let summary = "Inlay \(variant == .pocket ? "pocket" : "plug"): \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Inlay \(variant == .pocket ? "Pocket" : "Plug") \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Prism params to an operation: store + regenerate with the REAL
    /// engine, clearing the dirty badge (mirrors the SPK-1136 apply* family).
    @discardableResult
    func applyPrismParams(_ params: PrismToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .prism else {
            statusMessage = "Apply params: select a Prism operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = PrismToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Prism: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    @discardableResult
    func applyFlutingParams(_ params: FlutingToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .fluting else {
            statusMessage = "Apply params: select a Fluting operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = FlutingToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Fluting: \(result.featureCount) flute(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    @discardableResult
    func applyChamferParams(_ params: ChamferToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .chamfer else {
            statusMessage = "Apply params: select a Chamfer operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = ChamferToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Chamfer: \(result.featureCount) edge(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    @discardableResult
    func applyInlayParams(_ params: InlayToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .inlay else {
            statusMessage = "Apply params: select an Inlay operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result: SpecialtyResult = params.variant == .pocket
            ? InlayToolpathEngine.computePocket(paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0)
            : InlayToolpathEngine.computePlug(paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0)
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Inlay \(params.variant == .pocket ? "pocket" : "plug"): ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Quick Engrave toolpath: single-pass V-bit engraving along
    /// the selected vectors (the sign-shop "just engrave it" op).
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateQuickEngraveToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import text/shapes first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = QuickEngraveToolpathParams()
            let result = QuickEngraveToolpathEngine.compute(
                paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight
            )
            let summary = result.featureCount > 0
                ? "Quick Engrave: \(result.featureCount) vector(s), ~\(Int(result.estimatedTimeSeconds))s"
                : "Quick Engrave: no usable vectors"
            return AsyncGenerateResult(
                nodeName: "Quick Engrave \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    @discardableResult
    func applyQuickEngraveParams(_ params: QuickEngraveToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .quickEngrave else {
            statusMessage = "Apply params: select a Quick Engrave operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = QuickEngraveToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Quick Engrave: \(result.featureCount) vector(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Photo V-Carve op: a fine V-bit raster over the imported
    /// relief (image or STL), brightness → depth. Dark pixels carve deep,
    /// bright pixels stay high — the classic sign-shop photo carve.
    /// SPK-UI-BUG-03: the raster engine runs off the main thread.
    func generatePhotoVCarveToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image (Model → Image Relief…) or STL first"
            return
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = PhotoVCarveToolpathParams()
            let result = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: params)
            let summary = "Photo V-Carve: \(result.gcodeLines.count) lines, \(result.featureCount) passes, ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Photo V-Carve \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Photo V-Carve params to an operation: store + regenerate with the
    /// REAL engine, clearing the dirty badge (mirrors the apply* family).
    @discardableResult
    func applyPhotoVCarveParams(_ params: PhotoVCarveToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .photoVCarve else {
            statusMessage = "Apply params: select a Photo V-Carve operation"
            return false
        }
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image or STL first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: params)
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Photo V-Carve: \(result.featureCount) passes, ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Drag Knife op: spindle-center path offset by the blade
    /// offset with corner pivots — the classic drag-knife toolpath.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateDragKnifeToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import shapes first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = DragKnifeToolpathParams()
            let result = DragKnifeToolpathEngine.compute(
                paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight
            )
            let summary = "Drag Knife: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Drag Knife \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    @discardableResult
    func applyDragKnifeParams(_ params: DragKnifeToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .dragKnife else {
            statusMessage = "Apply params: select a Drag Knife operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = DragKnifeToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Drag Knife: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Texture op: parallel or crosshatch grooves clipped inside
    /// the selected closed vectors (SPK-0900 texture slice).
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateTextureToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select a closed boundary first"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = TextureToolpathParams()
            let result = TextureToolpathEngine.compute(
                paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight
            )
            let summary = "Texture: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Texture \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    @discardableResult
    func applyTextureParams(_ params: TextureToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .texture else {
            statusMessage = "Apply params: select a Texture operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = TextureToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Texture: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Sketch Carve op: a V-bit raster gated by the image's EDGES
    /// (Sobel gradient), so only strong brightness transitions carve — the
    /// hand-sketched line-art look (SPK-0901 remainder).
    /// SPK-UI-BUG-03: the raster engine runs off the main thread.
    func generateSketchCarveToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image (Model → Image Relief…) or STL first"
            return
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = SketchCarveToolpathParams()
            let result = SketchCarveToolpathEngine.compute(heightfield: hf, params: params)
            let summary = "Sketch Carve: \(result.featureCount) edge cells, \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Sketch Carve \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Apply Sketch Carve params to an operation: store + regenerate with the
    /// REAL engine, clearing the dirty badge (mirrors the apply* family).
    @discardableResult
    func applySketchCarveParams(_ params: SketchCarveToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .sketchCarve else {
            statusMessage = "Apply params: select a Sketch Carve operation"
            return false
        }
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image or STL first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = SketchCarveToolpathEngine.compute(heightfield: hf, params: params)
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Sketch Carve: \(result.featureCount) edge cells, ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    /// Generate a Rotary Wrap op: wrap the selected vectors around a rotary
    /// axis (X → A degrees, Y stays the axis dimension) — SPK-0904 slice.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateRotaryWrapToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import shapes first"
            return
        }
        var params = RotaryWrapToolpathParams()
        // SPK-0903: job-level rotary setup supplies the stock Ø default.
        if let cfg = job.rotaryConfig {
            params.diameterMm = cfg.diameter
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let result = RotaryWrapToolpathEngine.compute(
                paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight
            )
            let summary = "Rotary Wrap: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Rotary Wrap \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// True when the selection contains a rectangle (dogbone target).
    var hasSelectedRectangle: Bool {
        selectedShapeIndices.contains { idx in
            shapes.indices.contains(idx) && {
                if case .rectangle = shapes[idx] { return true }
                return false
            }()
        }
    }

    // MARK: - Dogbone corner relief (SPK-1301)

    /// Add dogbone corner-relief circles to a selected rectangle pocket so a
    /// round bit can cut square corners (joinery). Returns the count added.
    @discardableResult
    func addDogboneReliefs(bitDiameter: Double) -> Int {
        // Find the selected rectangle (first selected shape that is one).
        guard let index = selectedShapeIndices.first,
              shapes.indices.contains(index) else {
            statusMessage = "Select a rectangle pocket first"
            return 0
        }
        let shape = shapes[index]
        guard case .rectangle(let origin, let width, let height) = shape else {
            statusMessage = "Dogbone works on a rectangle pocket — select one"
            return 0
        }
        let bounds = Rect(
            minX: origin.x, minY: origin.y,
            maxX: origin.x + width, maxY: origin.y + height
        )
        let reliefs = Dogbone.cornerReliefs(for: bounds, bitDiameter: bitDiameter)
        guard !reliefs.isEmpty else {
            statusMessage = "Dogbone: invalid bit diameter"
            return 0
        }
        registerUndoPoint()
        var added = 0
        for relief in reliefs {
            shapes.append(.circle(center: relief.center, radius: relief.radius))
            added += 1
        }
        statusMessage = "Dogbone: \(added) corner relief(s) added (\(bitDiameter)mm bit)"
        markDirty()
        return added
    }

    // MARK: - Rest machining (SPK-1305)

    /// Generate a Rest Machining op: after a rough pass, clear leftover
    /// material (pockets the big tool couldn't reach) with z-level passes.
    /// The remaining-depth grid comes from the heightfield (cells where the
    /// relief is higher than the target floor), the planner computes the
    /// layers, and each pass becomes a zigzag clearing raster at that Z.
    /// SPK-UI-BUG-03: the planner runs off the main thread; the
    /// nothing-to-clear case publishes the summary without adding a node.
    func generateRestMachiningToolpath(stepDown: Double = 2.0, minRemaining: Double = 0.3) {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image (Model → Image Relief…) or STL first"
            return
        }
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            // Remaining depth per cell: height above the relief's floor.
            // (A flat stock yields all-zero remaining → no rest passes needed.)
            let floor = hf.heights.min() ?? 0
            let remaining = hf.heights.map { max(0, $0 - floor) }
            let passes = RestRoughing.planRestPasses(
                remainingDepthGrid: remaining,
                gridWidth: hf.width,
                stepDown: stepDown,
                minRemaining: minRemaining
            )
            guard !passes.isEmpty else {
                return AsyncGenerateResult(
                    nodeName: "Rest Machine \(nodeCount)",
                    gcode: [],
                    estimatedTime: 0,
                    summary: "Rest Machining: nothing left to clear (rough pass already cleaned the relief)",
                    paramsJSON: Self.encodeParamsValue(RestMachiningParams(stepDown: stepDown, minRemaining: minRemaining)),
                    addNode: false
                )
            }
            let gcode = self.restMachiningGCode(passes: passes, heightfield: hf)
            let summary = "Rest Machining: \(passes.count) pass(es), \(gcode.count) lines"
            return AsyncGenerateResult(
                nodeName: "Rest Machine \(nodeCount)",
                gcode: gcode,
                estimatedTime: TimeEstimator.estimate(gcodeLines: gcode).cuttingTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(RestMachiningParams(stepDown: stepDown, minRemaining: minRemaining))
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Zigzag clearing rasters per rest pass, over the cells that still hold
    /// material at that layer. Cells → world coords via the heightfield grid.
    private func restMachiningGCode(passes: [RestPass], heightfield hf: HeightfieldData) -> [String] {
        var lines: [String] = ["G21", "G90", "G17"]
        let safeZ = 5.0
        lines.append("G0 Z\(safeZ)")
        let cellW = hf.cellSizeMm
        let worldX = { (gx: Int) -> Double in hf.minX + (Double(gx) + 0.5) * cellW }
        let worldY = { (gy: Int) -> Double in hf.minY + (Double(gy) + 0.5) * cellW }
        for pass in passes {
            // The raster band: min/max world extents of this pass's cells.
            var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
            for idx in pass.cellIndices {
                let gx = idx % hf.width, gy = idx / hf.width
                let x = worldX(gx), y = worldY(gy)
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            guard minX <= maxX, minY <= maxY else { continue }
            lines.append("G0 X\(fmt(minX)) Y\(fmt(minY))")
            lines.append("G1 Z\(fmt(pass.depth)) F300")
            // Zigzag across the band at cell resolution.
            var y = minY
            var dir = 1.0
            while y <= maxY + 1e-9 {
                if dir > 0 {
                    lines.append("G1 X\(fmt(maxX)) Y\(fmt(y)) F600")
                } else {
                    lines.append("G1 X\(fmt(minX)) Y\(fmt(y)) F600")
                }
                y += cellW
                dir *= -1
            }
            lines.append("G0 Z\(safeZ)")
        }
        lines.append("M5")
        lines.append("M30")
        return lines
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    /// Params snapshot stored on the node so the form can restore + recalc.
    struct RestMachiningParams: Codable {
        var stepDown: Double
        var minRemaining: Double
    }

    @discardableResult
    func applyRotaryWrapParams(_ params: RotaryWrapToolpathParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.strategyKind == .rotaryWrap else {
            statusMessage = "Apply params: select a Rotary Wrap operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = RotaryWrapToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Rotary Wrap: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
        markDirty()
        return true
    }

    // MARK: - Array copy toolpath + merged toolpath (SPK-0803)

    /// The toolpath node currently selected in the Cut tree (nil = none).
    var selectedOperationNode: ToolpathTreeNode? {
        guard let id = selectedToolpathID else { return nil }
        return toolpathTree.findNode(id: id)
    }

    /// The selected operation's G-code lines (nil when no selection or the
    /// selected node has no computed result).
    private var selectedOperationGCode: [String]? {
        guard let node = selectedOperationNode, let result = node.toolpathResult else { return nil }
        return result.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// SPK-0803 — array-copy the SELECTED operation's G-code (linear or
    /// circular) into a new tree node via the real transform engine.
    @discardableResult
    func generateArrayCopyToolpath(count: Int, spacing: Double = 20.0, angle: Double = 0.0) -> Bool {
        guard let base = selectedOperationGCode else {
            statusMessage = "Array Copy: select a toolpath operation with computed G-code first"
            return false
        }
        let params = LinearArrayCopyParams(count: count, spacing: spacing, angle: angle)
        let result = ToolpathGCodeTransformer.linearArray(base: base, params: params)
        guard !result.isEmpty, result.copyCount > 0 else {
            statusMessage = "Array Copy: nothing to copy"
            return false
        }
        registerUndoPoint()
        let node = addToolpathNode(
            named: "Array Copy \(toolpathTree.allNodes.count) (×\(result.copyCount))",
            gcode: result.lines,
            estimatedTime: Double(result.moveCount) * 0.01
        )
        let encoded = encodeParams(ArrayCopyParamsJSON(kind: "linear", count: result.copyCount,
                                                       spacing: spacing, angle: angle))
        node.paramsJSON = encoded
        statusMessage = "Array Copy: \(result.copyCount) copies (\(result.moveCount) move lines)"
        markDirty()
        return true
    }

    /// SPK-0803 — circular array copy of the selected operation around a
    /// center point. `radius` places copies on the circle; `sweepDegrees`
    /// distributes them over an arc (360 = full ring).
    @discardableResult
    func generateCircularArrayCopyToolpath(count: Int, radius: Double, centerX: Double, centerY: Double,
                                           sweepDegrees: Double = 360.0) -> Bool {
        guard let base = selectedOperationGCode else {
            statusMessage = "Circular Array Copy: select a toolpath operation first"
            return false
        }
        let params = CircularArrayCopyParams(count: count, centerX: centerX, centerY: centerY,
                                             startAngle: 0, endAngle: sweepDegrees, radius: radius)
        let result = ToolpathGCodeTransformer.circularArray(base: base, params: params)
        guard !result.isEmpty else {
            statusMessage = "Circular Array Copy: nothing to copy"
            return false
        }
        registerUndoPoint()
        let node = addToolpathNode(
            named: "Circular Array \(toolpathTree.allNodes.count) (×\(result.copyCount))",
            gcode: result.lines,
            estimatedTime: Double(result.moveCount) * 0.01
        )
        node.paramsJSON = encodeParams(ArrayCopyParamsJSON(kind: "circular", count: result.copyCount,
                                                           radius: radius, centerX: centerX, centerY: centerY))
        statusMessage = "Circular Array: \(result.copyCount) copies around Ø\(String(format: "%.1f", radius * 2))mm"
        markDirty()
        return true
    }

    /// SPK-0803 — merge ALL computed operation nodes' G-code into one new
    /// node (tree order; markers preserved). Selection-independent: the
    /// merged op is the union of the whole cut plan, which is what a merge
    /// node is for (one program to stream).
    @discardableResult
    func generateMergedToolpath() -> Bool {
        let programs = toolpathTree.allNodes
            .filter { $0.toolpathResult != nil }
            .compactMap { node -> [String]? in
                node.toolpathResult?
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        guard programs.count >= 2 else {
            statusMessage = "Merge Toolpaths: need at least 2 computed operations"
            return false
        }
        registerUndoPoint()
        let merged = ToolpathGCodeTransformer.merge(programs: programs)
        let node = addToolpathNode(
            named: "Merged \(toolpathTree.allNodes.count) (\(programs.count) ops)",
            gcode: merged,
            estimatedTime: Double(merged.count) * 0.01
        )
        node.paramsJSON = encodeParams(ArrayCopyParamsJSON(kind: "merge", count: programs.count))
        statusMessage = "Merged: \(programs.count) operations → \(merged.count) lines"
        markDirty()
        return true
    }

    // MARK: - Nest advanced (SPK-0804)

    /// Nest the SELECTED shapes (or all shapes when nothing is selected) onto
    /// the active sheet using the Geometry guillotine engine. Adds translated
    /// copies at the engine's placed positions — the nested layout materializes
    /// as new design vectors on the active layer (undo + dirty).
    @discardableResult
    func nestSelectedShapes(margin: Double = 5.0) -> NestResult? {
        let sourceIndices: [Int]
        if !selectedShapeIndices.isEmpty {
            sourceIndices = Array(selectedShapeIndices).sorted()
        } else {
            sourceIndices = Array(shapes.indices)
        }
        guard !sourceIndices.isEmpty else {
            statusMessage = "Nest: nothing to nest — draw or select shapes first"
            return nil
        }
        guard let sheet = activeSheet else {
            statusMessage = "Nest: no sheet — set up the job first"
            return nil
        }
        let parts = sourceIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        let result = ShopPilotGeometry.NestingEngine.nest(
            parts: parts,
            sheetWidth: sheet.width,
            sheetHeight: sheet.depth,
            margin: margin
        )
        guard !result.parts.isEmpty else {
            statusMessage = "Nest: nothing placed — parts may exceed the sheet"
            return result
        }
        registerUndoPoint()
        // Materialize placed copies: translate each source shape so its
        // bounding box top-left lands on the engine's placed position
        // (applying the 90° rotation the engine used when it fit rotated).
        var copies: [VectorShape] = []
        var usedLayerID = activeSheet?.layers.first?.id ?? UUID()
        if let layer = activeSheet?.layers.first { usedLayerID = layer.id }
        for placed in result.parts {
            let original = placed.shape
            let localBB = original.boundingRect
            var placedShape = original
            if abs(placed.rotation - .pi / 2.0) < 1e-9 {
                // Rotate about the bbox center, then translate so the rotated
                // bbox's top-left lands at the placed position.
                let center = VectorPoint(x: localBB.minX + localBB.width / 2,
                                         y: localBB.minY + localBB.height / 2)
                placedShape = ShapeTransformer().rotate(
                    shapes: [original], angle: 90, about: center
                )[0]
            }
            let newBB = placedShape.boundingRect
            let dx = placed.position.x - newBB.minX
            let dy = placed.position.y - newBB.minY
            copies.append(placedShape.translated(by: dx, dy))
        }
        let newLayerIDs = Array(repeating: usedLayerID, count: copies.count)
        shapes.append(contentsOf: copies)
        shapeLayerIDs.append(contentsOf: newLayerIDs)
        syncLayerVectors()
        selectedShapeIndices = Set((shapes.count - copies.count)..<shapes.count)
        statusMessage = String(
            format: "Nest: %d placed, %d unplaced, utilization %.1f%%",
            result.parts.count, result.unplacedCount, result.utilization
        )
        markDirty()
        return result
    }

    // MARK: - Tiling (SPK-0805)

    /// Tile the SELECTED shapes (or all shapes) across the active sheet using
    /// the real `TilingManager` layout engine. Each tile's content is the
    /// source selection, copied to the tile cell origin (mirror flags
    /// applied). Materializes as new design vectors — undo + dirty.
    @discardableResult
    func generateTiling(tilesPerRow: Int, tilesPerColumn: Int,
                        tileGap: Double = 2.0, margin: Double = 5.0) -> TilingResult? {
        let sourceIndices: [Int]
        if !selectedShapeIndices.isEmpty {
            sourceIndices = Array(selectedShapeIndices).sorted()
        } else {
            sourceIndices = Array(shapes.indices)
        }
        guard !sourceIndices.isEmpty else {
            statusMessage = "Tiling: nothing to tile — draw or select shapes first"
            return nil
        }
        guard let sheet = activeSheet else {
            statusMessage = "Tiling: no sheet — set up the job first"
            return nil
        }
        // Tile cell = sheet footprint minus margins, split into the grid.
        let cellW = (sheet.width - 2 * margin) / Double(tilesPerRow)
        let cellH = (sheet.depth - 2 * margin) / Double(tilesPerColumn)
        let config = TilingConfig(
            tilesPerRow: tilesPerRow,
            tilesPerColumn: tilesPerColumn,
            tileWidth: cellW,
            tileHeight: cellH,
            tileGap: tileGap,
            gapType: .fixed,
            direction: .horizontal,
            alignment: .topLeft,
            originX: margin,
            originY: margin,
            rotation: 0,
            mirrorHorizontal: false,
            mirrorVertical: false,
            stagger: false,
            staggerAmount: 0
        )
        let result = TilingManager().generateLayout(config: config, sheetWidth: sheet.width, sheetHeight: sheet.depth)
        guard result.success, !result.tiles.isEmpty else {
            statusMessage = "Tiling: layout failed — \(result.errorMessage ?? "unknown")"
            return result
        }
        // Source shapes' content bbox (so copies center in each tile cell).
        let contentBB = sourceIndices.reduce(into: Rect()) { acc, idx in
            guard shapes.indices.contains(idx) else { return }
            let bb = shapes[idx].boundingRect
            acc = acc.width == 0 && acc.height == 0 ? bb : Rect(
                minX: min(acc.minX, bb.minX), minY: min(acc.minY, bb.minY),
                maxX: max(acc.maxX, bb.maxX), maxY: max(acc.maxY, bb.maxY)
            )
        }
        let contentW = contentBB.width == 0 ? cellW : contentBB.width
        let contentH = contentBB.height == 0 ? cellH : contentBB.height

        registerUndoPoint()
        let layerID = activeSheet?.layers.first?.id ?? UUID()
        var copies: [VectorShape] = []
        for tile in result.tiles where tile.placed {
            // Center the content in the tile cell.
            let cellCenterX = tile.x + tile.width / 2
            let cellCenterY = tile.y + tile.height / 2
            let dx = cellCenterX - contentW / 2 - contentBB.minX
            let dy = cellCenterY - contentH / 2 - contentBB.minY
            var copy = contentBB.width == 0 && contentBB.height == 0
                ? VectorShape.rectangle(origin: VectorPoint(x: tile.x, y: tile.y),
                                        width: tile.width, height: tile.height)
                : shapes[sourceIndices[0]].translated(by: dx, dy)
            copies.append(copy)
        }
        let newLayerIDs = Array(repeating: layerID, count: copies.count)
        shapes.append(contentsOf: copies)
        shapeLayerIDs.append(contentsOf: newLayerIDs)
        syncLayerVectors()
        selectedShapeIndices = Set((shapes.count - copies.count)..<shapes.count)
        statusMessage = "Tiling: \(result.placedTiles) tiles placed (\(tilesPerRow)×\(tilesPerColumn) grid)"
        markDirty()
        return result
    }

    // MARK: - Thread milling (SPK-0902)

    /// Generate a thread-mill op on the FIRST selected closed vector (its
    /// bounding-box center is the hole center; the hole Ø is derived from the
    /// vector size). Uses the real helical engine. SPK-UI-BUG-03: engine
    /// compute runs off the main thread.
    func generateThreadMillingToolpath() {
        guard let target = selectedClosedShapeBBoxCenter() else {
            statusMessage = "Thread Mill: select a closed vector (the hole) first"
            return
        }
        let centerX = target.center.x
        let centerY = target.center.y
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            let params = ThreadMillParams()
            let result = ThreadMillingToolpathEngine.compute(
                centerX: centerX,
                centerY: centerY,
                params: params
            )
            let summary = "Thread Mill: M\(String(format: "%.2f", result.threadPitchMm)) pitch, \(result.helixCount) helical pass(es), \(result.gcodeLines.count) lines"
            return AsyncGenerateResult(
                nodeName: "Thread Mill \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    /// Recompute a thread-mill op with new params (form Apply).
    @discardableResult
    func applyThreadMillParams(_ params: ThreadMillParams, to nodeID: UUID,
                               centerX: Double = 0, centerY: Double = 0) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID),
              node.strategyKind == .threadMill else {
            statusMessage = "Apply params: select a Thread Mill operation"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = ThreadMillingToolpathEngine.compute(centerX: centerX, centerY: centerY, params: params)
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty { gcodeLines = all }
        statusMessage = "Thread Mill: \(result.helixCount) helical pass(es)"
        markDirty()
        return true
    }

    /// Center of the selected closed shape's bounding box (nil when none).
    private func selectedClosedShapeBBoxCenter() -> (center: (x: Double, y: Double), size: (w: Double, h: Double))? {
        guard let idx = selectedShapeIndices.sorted().first, shapes.indices.contains(idx) else { return nil }
        let bb = shapes[idx].boundingRect
        return ((bb.minX + bb.width / 2, bb.minY + bb.height / 2), (bb.width, bb.height))
    }

    /// Generate an Inlay op from a named V-Carve recipe preset (SPK-0802
    /// remainder): the recipe sets angle/depth/feeds on the real engine.
    /// SPK-UI-BUG-03: engine compute runs off the main thread.
    func generateInlayToolpath(variant: InlayToolpathParams.Variant, recipeName: String? = nil) {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select the inlay shape"
            return
        }
        let vectorsSnapshot = vectors
        let stockHeight = activeSheet?.height ?? 25.0
        let nodeCount = toolpathTree.allNodes.count
        registerUndoPoint()
        generateToolpathAsync(compute: {
            var params: InlayToolpathParams
            var summaryPrefix: String
            if let name = recipeName, let recipe = VCarveInlayRecipe.preset(named: name) {
                params = recipe.params(variant: variant)
                summaryPrefix = "Inlay \(variant == .pocket ? "pocket" : "plug") [\(recipe.name)]:"
            } else {
                params = InlayToolpathParams()
                params.variant = variant
                summaryPrefix = "Inlay \(variant == .pocket ? "pocket" : "plug"):"
            }
            let result: SpecialtyResult = variant == .pocket
                ? InlayToolpathEngine.computePocket(paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight)
                : InlayToolpathEngine.computePlug(paths: vectorsSnapshot, params: params, stockHeightMm: stockHeight)
            let summary = "\(summaryPrefix) \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
            return AsyncGenerateResult(
                nodeName: "Inlay \(variant == .pocket ? "Pocket" : "Plug") \(nodeCount)",
                gcode: result.gcodeLines,
                estimatedTime: result.estimatedTimeSeconds,
                summary: summary,
                paramsJSON: Self.encodeParamsValue(params)
            )
        }) { result in
            let node = self.addToolpathNode(named: result.nodeName, gcode: result.gcode, estimatedTime: result.estimatedTime)
            node.paramsJSON = result.paramsJSON
        }
    }

    // MARK: - Level mirror modes (SPK-0908)

    /// The session's level manager (level metadata + mirror modes).
    let levelManager = LevelManager()

    /// Mirror a level's content: flips every component heightfield in that
    /// level along the requested axis (real grid transform, world footprint
    /// kept) and recomposites the active relief. Undoable + dirty.
    @discardableResult
    func mirrorLevel(_ id: UUID, axis: LevelManager.MirrorAxis) -> Bool {
        guard let level = levelManager.levels.first(where: { $0.id == id }) else {
            statusMessage = "Mirror: level not found"
            return false
        }
        guard var stack = job.reliefComponents, !stack.isEmpty else {
            statusMessage = "Mirror: no relief components to mirror"
            return false
        }
        registerUndoPoint()
        let levelComponentIDs = Set(level.components)
        var mirrored = false
        for i in stack.indices where levelComponentIDs.contains(stack[i].id) {
            stack[i].heightfield = LevelMirrorEngine.mirror(stack[i].heightfield, axis: axis)
            mirrored = true
        }
        guard mirrored else {
            statusMessage = "Mirror: level holds no relief components"
            return false
        }
        job.reliefComponents = stack
        levelManager.mirrorLevel(id, axis: axis)
        markDirty()
        let ok = recompositeRelief()
        statusMessage = "Level “\(level.name)” mirrored \(axis.rawValue)\(ok ? " — relief recomposited" : "")"
        return ok
    }

    /// Mirror the document's ACTIVE relief in place (no component stack
    /// needed) — the single-relief workflow equivalent of a level mirror.
    @discardableResult
    func mirrorActiveRelief(axis: LevelManager.MirrorAxis) -> Bool {
        guard let hf = job.stlHeightfield else {
            statusMessage = "Mirror: no active relief — import an image or STL first"
            return false
        }
        registerUndoPoint()
        job.stlHeightfield = LevelMirrorEngine.mirror(hf, axis: axis)
        for node in toolpathTree.allNodes where node.strategyKind == .rough3D || node.strategyKind == .finish3D {
            node.markDirty()
        }
        markDirty()
        statusMessage = "Relief mirrored \(axis.rawValue) — 3D ops marked dirty"
        return true
    }

    // MARK: - Text + bitmap trace + export (studio surface)

    /// Add rendered text as vector glyph curves (CoreText → freehand shapes),
    /// ready for V-Carve / Quick Engrave. Undo + dirty via `addShapes`.
    @discardableResult
    func addText(text: String, fontSizePoints: Double, scaleMmPerPoint: Double) -> Bool {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "Text: enter some text"
            return false
        }
        let result = TextTool.createText(
            text: text,
            font: "Helvetica Neue",
            fontSize: max(6, fontSizePoints),
            scale: max(0.01, scaleMmPerPoint)
        )
        guard !result.shapes.isEmpty else {
            statusMessage = "Text: no glyphs rendered"
            return false
        }
        registerUndoPoint()
        addShapes(result.shapes)
        statusMessage = "Text added: \(result.shapes.count) glyph(s), \(result.metrics.glyphCount) chars"
        return true
    }

    /// Trace a bitmap image into vector paths (D22) and add them to the
    /// document. The image is mapped onto the job sheet's dimensions.
    @discardableResult
    func traceBitmap(from url: URL, threshold: Double) -> Bool {
        let sheet = activeSheet
        let result = BitmapTracer.trace(
            from: url,
            quality: BitmapTraceQuality(threshold: threshold),
            imageWidth: sheet?.width ?? 300.0,
            imageHeight: sheet?.height ?? 300.0
        )
        guard !result.paths.isEmpty else {
            statusMessage = "Trace: no paths found — adjust the threshold"
            return false
        }
        let shapes = result.paths.map { path -> VectorShape in
            .freehand(points: path.points)
        }
        registerUndoPoint()
        addShapes(shapes)
        statusMessage = "Trace: \(shapes.count) path(s) from \(result.pixelCount) px"
        return true
    }

    /// Trace-bitmap panel flow: pick an image, ask for a threshold, trace.
    func traceBitmapFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Trace Bitmap"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Trace Bitmap"
        alert.informativeText = "Brightness → vector outline (dark shapes on a light background work best)."
        alert.addButton(withTitle: "Trace")
        alert.addButton(withTitle: "Cancel")
        let thresholdField = NSTextField(string: "0.5")
        thresholdField.placeholderString = "Threshold (0–1)"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(NSTextField(labelWithString: "Threshold (0–1):"))
        stack.addArrangedSubview(thresholdField)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let threshold = min(1.0, max(0.0, Double(thresholdField.stringValue) ?? 0.5))
        _ = traceBitmap(from: url, threshold: threshold)
    }

    /// Export the imported relief as an ASCII STL mesh (E38). Returns the
    /// exported triangle count, or nil on failure.
    @discardableResult
    func exportSTL(to url: URL) -> Int? {
        guard let hf = job.stlHeightfield,
              let stl = HeightfieldSTLExporter.stlString(from: hf) else {
            statusMessage = "Export STL: no relief to export"
            return nil
        }
        do {
            try stl.write(to: url, atomically: true, encoding: .utf8)
            let triangles = stl.components(separatedBy: "facet normal").count - 1
            statusMessage = "STL exported: \(triangles) triangles"
            return triangles
        } catch {
            statusMessage = "STL export failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - SPK-0707 Component STL export

    /// Export a component's heightfield as an ASCII STL mesh.
    /// Returns the exported triangle count, or nil on failure.
    @discardableResult
    func exportComponentSTL(_ componentID: UUID, to url: URL) -> Int? {
        guard let component = job.reliefComponents?.first(where: { $0.id == componentID }) else {
            statusMessage = "Component not found"
            return nil
        }
        guard let stl = HeightfieldSTLExporter.stlString(from: component.heightfield) else {
            statusMessage = "Export STL: no heightfield to export"
            return nil
        }
        do {
            try stl.write(to: url, atomically: true, encoding: .utf8)
            let triangles = stl.components(separatedBy: "facet normal").count - 1
            statusMessage = "Component STL exported: \(component.name) (\(triangles) triangles)"
            return triangles
        } catch {
            statusMessage = "STL export failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - SPK-0708 Composite render

    /// Render the active relief (or the first component) with a material config.
    /// Returns the render output on success.
    @discardableResult
    func renderCompositeComponent(_ config: MetalCompositeConfig) -> RenderOutput {
        let output = MetalCompositeRenderEngine.render(config)
        if output.success {
            statusMessage = "Composite render: \(config.material.rawValue) / \(config.finish.rawValue) → \(URL(fileURLWithPath: output.imageUrl).lastPathComponent)"
        } else {
            statusMessage = "Composite render failed: \(output.errorMessage ?? "unknown error")"
        }
        return output
    }

    /// Export the design vectors as ASCII DXF R12 (mm).
    @discardableResult
    func exportDXF(to url: URL) -> Bool {
        let dxf = VectorDXFExporter.dxfString(from: shapes)
        do {
            try dxf.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "DXF exported: \(shapes.count) shape(s)"
            return true
        } catch {
            statusMessage = "DXF export failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Apply V-Carve params to an operation: store them on the node and
    /// immediately regenerate its G-code with the REAL engine (SPK-1136d).
    @discardableResult
    func applyVCarveParams(_ params: VCarveParams, to nodeID: UUID) -> Bool {
        guard let node = toolpathTree.findNode(id: nodeID), node.isVCarveOperation else {
            statusMessage = "Apply params: select a V-Carve operation"
            return false
        }
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — add shapes first"
            return false
        }
        registerUndoPoint()
        node.paramsJSON = encodeParams(params)
        let result = VCarveEngine.compute(
            vectors: vectors,
            params: params,
            stockHeightMm: activeSheet?.height ?? 25.0
        )
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        node.clearDirty()
        let all = allToolpathGCode
        if !all.isEmpty {
            gcodeLines = all
        }
        lastToolpathSummary =
            "V-Carve: \(result.gcodeLines.count) lines, \(Int(params.vBitAngleDegrees))° bit, " +
            "\(result.passCount) pass(es)"
        statusMessage = lastToolpathSummary
        markDirty()
        return true
    }

    // MARK: - Machine G-code (SPK-1403d)

    /// Load fixture G-code into the buffer when it is empty (so Machine
    /// Continue / fixture load always has something to hand off). SPK-1403d:
    /// the orchestration is owned by `FixtureGCodeLoader` (Core) — this
    /// facade just supplies the session hooks.
    func loadFixtureGCodeIfNeeded() {
        FixtureGCodeLoader.loadIfNeeded(into: self)
    }

    /// Send G-code to the Machine stage via the Cut-to-Machine bridge.
    func sendToMachineStage() {
        guard !gcodeLines.isEmpty else {
            statusMessage = "No G-code to send — generate a toolpath first"
            return
        }
        statusMessage = "Sending \(gcodeLines.count) lines to Machine stage..."
        selectedStage = .machine
    }

    func handleCommand(_ id: CommandID) {
        switch id {
        case .newJob:
            // SPK-1601 — File New replaces the session (not stage-only).
            newJob()
        case .saveJob:
            // SPK-1600 — the command palette Save routes to the same File
            // Save path (prompt on first save, packageURL re-save after).
            savePackageFromPanel()
        case .openJob:
            openPackageFromPanel()
        case .undo:
            if undo() {
                statusMessage = "Undo"
            }
        case .redo:
            if redo() {
                statusMessage = "Redo"
            }
        case .group:
            if applyGroup() { selectedStage = .design }
        case .ungroup:
            if applyUngroup() { selectedStage = .design }
        case .setSize:
            statusMessage = "Set Size: use the Design ops bar (Set Size…)"
            selectedStage = .design
        case .profileTP:
            generateProfileToolpath()
        case .vcCarveTP:
            generateProfileToolpath()
        case .connectMachine, .airCut:
            loadFixtureGCodeIfNeeded()
            selectedStage = .machine
        case .exportGcode:
            // SPK-1610 — the palette Export routes to the same save-panel
            // path as File Export and Cut Save Toolpaths.
            exportGcodeFromPanel()
        case .importSVG:
            importSVGFromPanel()
        case .importSTLRelief:
            importSTLHeightfieldFromPanel()
        case .importImageRelief:
            importBitmapHeightfieldFromPanel()
        case .importLithophane:
            generateLithophaneFromPanel()
        case .importImageToRelief:
            generateImageToReliefFromPanel()
        case .importOBJRelief:
            importOBJHeightfieldFromPanel()
        case .import3MFRelief:
            import3MFHeightfieldFromPanel()
        case .importEPS:
            importEPSFromPanel()
        case .importPDF:
            importPDFFromPanel()
        case .importAI:
            importAIFromPanel()
        case .importDWG:
            importDWGFromPanel()
        default:
            statusMessage = "Command: \(id.name)"
        }
        showCommandPalette = false
    }

    /// ⌘K "Import PDF Vectors…": open panel → PDF content streams → vectors.
    func importPDFFromPanel() {
        let panel = NSOpenPanel()
        if let pdfType = UTType(filenameExtension: "pdf") {
            panel.allowedContentTypes = [pdfType]
        } else {
            panel.allowedFileTypes = ["pdf"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import PDF Vectors"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importPDFVectors(from: url)
        selectedStage = .design
    }

    /// ⌘K "Import AI…": open panel → AI (EPS or PDF flavor) → vectors.
    func importAIFromPanel() {
        let panel = NSOpenPanel()
        if let aiType = UTType(filenameExtension: "ai") {
            panel.allowedContentTypes = [aiType]
        } else {
            panel.allowedFileTypes = ["ai"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import AI"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importAIVectors(from: url)
        selectedStage = .design
    }

    /// ⌘K "Import DWG…": open panel → R12 DWG → vectors.
    func importDWGFromPanel() {
        let panel = NSOpenPanel()
        if let dwgType = UTType(filenameExtension: "dwg") {
            panel.allowedContentTypes = [dwgType]
        } else {
            panel.allowedFileTypes = ["dwg"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import DWG"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importDWGShapes(from: url)
        selectedStage = .design
    }

    /// ⌘K "Import OBJ Relief…": open panel → OBJ → heightfield (Tier-2).
    func importOBJHeightfieldFromPanel() {
        let panel = NSOpenPanel()
        if let objType = UTType(filenameExtension: "obj") {
            panel.allowedContentTypes = [objType]
        } else {
            panel.allowedFileTypes = ["obj"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import OBJ Relief"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importOBJHeightfield(from: url)
        selectedStage = .model
    }

    /// ⌘K "Import 3MF Relief…": open panel → 3MF → heightfield (Tier-2).
    func import3MFHeightfieldFromPanel() {
        let panel = NSOpenPanel()
        if let threeMFType = UTType(filenameExtension: "3mf") {
            panel.allowedContentTypes = [threeMFType]
        } else {
            panel.allowedFileTypes = ["3mf"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import 3MF Relief"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = import3MFHeightfield(from: url)
        selectedStage = .model
    }

    /// ⌘K "Import EPS…": open panel → EPS → design vectors (Tier-2).
    func importEPSFromPanel() {
        let panel = NSOpenPanel()
        if let epsType = UTType(filenameExtension: "eps") {
            panel.allowedContentTypes = [epsType]
        } else {
            panel.allowedFileTypes = ["eps"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import EPS"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = importEPSVectors(from: url)
        selectedStage = .design
    }

    /// ⌘K "Import STL Relief…": present an open panel and import the chosen
    /// STL as a heightfield (SPK-3D-spine-a). Also the Design-stage button.
    func importSTLHeightfieldFromPanel() {
        let panel = NSOpenPanel()
        if let stlType = UTType(filenameExtension: "stl") {
            panel.allowedContentTypes = [stlType]
        } else {
            panel.allowedFileTypes = ["stl"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import STL Relief"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // SPK-0707: show orientation wizard before import
        stlImportURL = url
        showSTLOrientationWizard = true
    }

    /// ⌘K "Import SVG…": present an open panel and import the chosen file
    /// through `importSVG(from:)` (SPK-1101e). The Design-stage Import hub
    /// remains the in-pane path; this makes the session method reachable
    /// from the palette too.
    private func importSVGFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import SVG"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try importSVG(from: url)
            selectedStage = .design
            if count == 0 {
                statusMessage = "No drawable shapes found in \(url.lastPathComponent)"
            }
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func defaultPackageURL() -> URL {
        if let packageURL {
            return packageURL
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let safeName = job.name.replacingOccurrences(of: "/", with: "-")
        return docs.appendingPathComponent("\(safeName).shoppilot")
    }

    /// SPK-1610 — post template selected for export (shared by the File
    /// Export and Cut Save Toolpaths panels). Defaults to the shipped GRBL mm.
    var exportPostTemplateID: String = "grbl-mm"

    /// SPK-1600 — File Save / Save As. `isSaveAs` forces the panel; plain
    /// Save writes to `packageURL` when one exists (re-save), else prompts.
    /// The panel filters to `.shoppilot` and the URL becomes the new
    /// `packageURL` via `savePackage(to:)` (markClean + clearUndo included).
    func savePackageFromPanel(isSaveAs: Bool = false) {
        if !isSaveAs, let packageURL {
            do {
                try savePackage(to: packageURL)
            } catch {
                statusMessage = "Save failed: \(error.localizedDescription)"
            }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "shoppilot")].compactMap { $0 }
        panel.nameFieldStringValue = "\(job.name.replacingOccurrences(of: "/", with: "-")).shoppilot"
        panel.canCreateDirectories = true
        panel.title = isSaveAs ? "Save As…" : "Save"
        guard panel.runModal() == .OK, let url = panel.url else {
            return // cancelled
        }
        do {
            try savePackage(to: url)
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// SPK-1610 — File Export G-code: the SAME save-panel path the Cut
    /// stage's "Save Toolpaths" uses (post-template picker accessory + unit
    /// preference override). Shared so File menu, ⌘K palette and Cut all
    /// export identically.
    func exportGcodeFromPanel() {
        let gcode = allToolpathGCode
        guard !gcode.isEmpty else {
            statusMessage = "No G-code to save — generate a toolpath first"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "job.gcode"
        panel.canCreateDirectories = true
        panel.title = "Export G-code"

        // SPK-1134 + SPK-1000: post picker accessory (shipped GRBL set +
        // user Post Studio templates).
        let postPicker = PostTemplatePickerView(
            templates: postTemplateStore.allTemplates,
            selectedID: exportPostTemplateID
        ) { id in
            self.exportPostTemplateID = id
        }
        let accessory = NSHostingView(rootView: postPicker)
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
        panel.accessoryView = accessory

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return // User cancelled
        }

        let profile = machineProfiles.profiles.first ?? MachineProfile.simulatorProfile
        do {
            let postTemplate = postTemplateStore.template(byID: exportPostTemplateID)
            let result = try CutToMachineBridge.export(
                gcodeLines: gcode,
                toolInfo: nil,
                machineProfile: profile,
                fileName: destinationURL.deletingPathExtension().lastPathComponent,
                postTemplate: postTemplate,
                postVariables: postTemplateVariables,
                // SPK-1609 — the Preferences unit choice overrides the
                // profile for export (inch → G20 + scaled coordinates).
                unitsOverride: AppSettings().isInches ? .inch : .millimeter
            )

            if let errorMessage = result.errorMessage {
                statusMessage = "Export failed: \(errorMessage)"
                return
            }
            guard let exportedURL = result.outputFileURL else {
                statusMessage = "Export failed: bridge produced no output file"
                return
            }

            // The bridge writes post-processed G-code to its temp export
            // directory; copy it to the user-chosen destination and report
            // the line count actually on disk.
            let data = try Data(contentsOf: exportedURL)
            try data.write(to: destinationURL, options: .atomic)
            let writtenText = String(data: data, encoding: .utf8) ?? ""
            let writtenLineCount = writtenText.split(whereSeparator: \.isNewline).count
            statusMessage = "Exported \(destinationURL.lastPathComponent) (\(writtenLineCount) lines)"
            lastToolpathSummary = "\(result.postProcessorType.displayName) — \(writtenLineCount) lines"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func openPackageFromDefaultLocation() {
        let url = defaultPackageURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "No package at \(url.lastPathComponent)"
            return
        }
        do {
            try openPackage(from: url)
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    /// ⌘O / ⌘K "Open Job…" / Welcome "Open a Job…": present a REAL package
    /// picker (Bugbot Medium fix — the previous routing opened a default
    /// location without ever showing an NSOpenPanel). Filters to `.shoppilot`
    /// packages; the panel path then runs the same `openPackage(from:)`
    /// loader the File menu uses.
    func openPackageFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "shoppilot")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open ShopPilot Job"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try openPackage(from: url)
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sample projects (SPK-1400a / 1403a)

    /// Load a bundled sample project (from `SampleProjectsStore`) into this
    /// session. SPK-1403a: the lifecycle is owned by `SampleProjectLoader`
    /// (Core) — this facade just supplies the session hooks.
    func loadSampleProject(id: UUID) -> Bool {
        SampleProjectLoader.load(id: id, into: self)
    }
}
