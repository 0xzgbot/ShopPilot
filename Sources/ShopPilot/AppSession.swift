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
final class AppSession: ObservableObject {
    @Published var selectedStage: Stage = .setup
    @Published var job: Job
    @Published var shapes: [VectorShape] = []

    /// Per-shape layer membership, index-aligned with `shapes` (SPK-1137).
    /// Kept in lockstep by every shape mutation so the canvas can honor each
    /// layer's hide/lock and save/open can keep each layer's own vectors.
    @Published private(set) var shapeLayerIDs: [UUID] = []
    @Published var gcodeLines: [String] = []
    @Published var lastToolpathSummary: String = "No toolpath generated"
    @Published var statusMessage: String = "Ready"
    @Published var showCommandPalette = false
    @Published var showPreferences = false
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

    /// Inspector/browser selection type (job, sheet, layer, toolpath).
    @Published var selection: SelectionType = .none

    /// Currently selected toolpath tree node id (nil = none).
    /// The toolpath tree UI mirrors this; the inspector reads it too.
    @Published var selectedToolpathID: UUID?

    /// Whether the document has unsaved changes.
    @Published private(set) var isDirty = false

    /// Undo/redo stack hooks for document mutations.
    let undoManager = UndoManager()

    let docVars = DocumentVariablesModel()

    /// Last saved/opened package URL (if any).
    private(set) var packageURL: URL?

    private let documentSaver = DocumentSaver()
    private let documentLoader = DocumentLoader()

    enum SelectionType: Equatable {
        case none
        case job
        case sheet(UUID)
        case layer(UUID)
        case toolpath(UUID)
    }

    init() {
        var job = Job(name: "Untitled Job")
        _ = job.ensureSingleSheet()
        self.job = job
        self.safetyAccepted = UserDefaults.standard.bool(forKey: "shop_pilot_safety_accepted")
        self.showSafetyDisclaimer = !self.safetyAccepted
        self.canvasOverlays = CanvasOverlayStore.load()
    }

    // MARK: - Derived document access

    /// The job's layers, read from the first sheet. Owned by the job, exposed here.
    var layers: [Layer] {
        job.sheets.first?.layers ?? []
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
        job.sheets.first?.layers.count ?? 0
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

    @discardableResult
    func redo() -> Bool {
        guard undoManager.canRedo else { return false }
        undoManager.redo()
        return true
    }

    func clearUndoStack() {
        undoManager.removeAllActions()
    }

    // MARK: - Snapshot undo support

    private struct SessionSnapshot {
        let job: Job
        let shapes: [VectorShape]
        let shapeLayerIDs: [UUID]
        let shapeGroups: [[Int]]
        let gcodeLines: [String]
        let selectedVectorIDs: Set<UUID>
    }

    private func captureSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            job: job,
            shapes: shapes,
            shapeLayerIDs: shapeLayerIDs,
            shapeGroups: shapeGroups,
            gcodeLines: gcodeLines,
            selectedVectorIDs: selectedVectorIDs
        )
    }

    private func registerUndoPoint() {
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
        job = snapshot.job
        shapes = snapshot.shapes
        shapeLayerIDs = snapshot.shapeLayerIDs
        shapeGroups = snapshot.shapeGroups
        gcodeLines = snapshot.gcodeLines
        selectedVectorIDs = snapshot.selectedVectorIDs
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
        statusMessage = "Saved “\(job.name)”"
    }

    /// Open a `.shoppilot` package from the given URL into this session.
    func openPackage(from url: URL) throws {
        let payload = try documentLoader.loadPayload(from: url)
        applyPackagePayload(payload)
        packageURL = url
        markClean()
        clearUndoStack()
        statusMessage = "Opened “\(payload.job.name)”"
    }

    /// Apply a loaded payload to session state (used by open and tests).
    func applyPackagePayload(_ payload: ShopPilotPackagePayload) {
        job = payload.job
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
    }

    // MARK: - Layer mutations

    @discardableResult
    func addLayer(_ layer: Layer = Layer()) -> Layer? {
        guard var sheet = job.sheets.first else { return nil }
        registerUndoPoint()
        sheet.addLayer(layer)
        job.sheets[0] = sheet
        markDirty()
        return layer
    }

    func renameLayer(id: UUID, to newName: String) {
        guard var sheet = job.sheets.first,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        registerUndoPoint()
        sheet.layers[index].name = newName
        job.sheets[0] = sheet
        markDirty()
    }

    @discardableResult
    func removeLayer(id: UUID) -> Bool {
        guard var sheet = job.sheets.first else { return false }
        guard sheet.layers.contains(where: { $0.id == id }) else { return false }
        registerUndoPoint()
        sheet.removeLayer(id: id)
        job.sheets[0] = sheet
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
        guard var sheet = job.sheets.first,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        guard sheet.layers[index].isVisible != isVisible else { return }
        registerUndoPoint()
        sheet.layers[index].isVisible = isVisible
        job.sheets[0] = sheet
        markDirty()
    }

    /// Toggle layer lock (lock icon) through the session sheet. Locking also
    /// drops selection of that layer's shapes (locked shapes are not editable).
    func setLayerLocked(id: UUID, isLocked: Bool) {
        guard var sheet = job.sheets.first,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        guard sheet.layers[index].isLocked != isLocked else { return }
        registerUndoPoint()
        sheet.layers[index].isLocked = isLocked
        job.sheets[0] = sheet
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
        guard var sheet = job.sheets.first,
              let from = sheet.layers.firstIndex(where: { $0.id == id }) else { return false }
        let clamped = min(max(toIndex, 0), sheet.layers.count - 1)
        guard from != clamped else { return false }
        registerUndoPoint()
        sheet.moveLayer(from: from, to: clamped)
        job.sheets[0] = sheet
        markDirty()
        return true
    }

    /// Move a layer one position up in the sheet's layer list.
    @discardableResult
    func moveLayerUp(id: UUID) -> Bool {
        guard let from = job.sheets.first?.layers.firstIndex(where: { $0.id == id }) else { return false }
        return moveLayer(id: id, toIndex: from - 1)
    }

    /// Move a layer one position down in the sheet's layer list.
    @discardableResult
    func moveLayerDown(id: UUID) -> Bool {
        guard let from = job.sheets.first?.layers.firstIndex(where: { $0.id == id }) else { return false }
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
        guard var sheet = job.sheets.first else { return }
        registerUndoPoint()
        sheet.width = width
        sheet.depth = depth
        sheet.height = height
        job.sheets[0] = sheet
        markDirty()
    }

    /// Set the material of the session's first sheet (nil = no material).
    func setSheetMaterial(_ material: ShopPilotCore.Material?) {
        guard var sheet = job.sheets.first else { return }
        registerUndoPoint()
        sheet.material = material
        job.sheets[0] = sheet
        markDirty()
    }

    /// Apply a stock sheet preset to the session's first sheet (SPK-1132):
    /// sets the sheet name + W/D/H and records the preset name so it
    /// survives save/open. Undoable + dirty.
    func applyStockPreset(_ preset: StockSheetPreset) {
        guard var sheet = job.sheets.first else { return }
        registerUndoPoint()
        StockSheetPresets.apply(preset, to: &sheet)
        job.sheets[0] = sheet
        statusMessage = "Stock: \(preset.name)"
        markDirty()
    }

    // MARK: - Shape / vector mutations

    func addShapes(_ newShapes: [VectorShape]) {
        registerUndoPoint()
        shapes.append(contentsOf: newShapes)
        let layerID: UUID
        if var sheet = job.sheets.first {
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
            job.sheets[0] = sheet
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
        guard let sheet = job.sheets.first else {
            statusMessage = "Add Shape needs a sheet — set up the job first"
            return false
        }
        let hf = ShapeReliefGenerator.generate(
            shapeType: shapeType,
            params: params,
            width: sheet.width,
            height: sheet.height,
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

    // MARK: - Toolpath preflight (SPK-FM-R013/R014/R019, export gate)

    /// Expert dismissals for toolpath preflight issues, session-scoped (same
    /// one-shot honesty contract as ExportBlocker's expert override — SPK-0603).
    @Published var toolpathPreflightDismissed: Set<UUID> = []

    /// Keep-out zones (SPK-0308): toolpaths must not enter active zones.
    @Published var keepOutZones: [KeepOutZone] = []

    /// Run the toolpath preflight rules over the tree with the document's
    /// design vectors and sheet material. Blocks export on `.error` issues.
    func exportPreflightIssues() -> [ToolpathPreflightIssue] {
        let materialThickness = job.sheets.first?.height ?? 25.0
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

    /// R017 fix CTA: adopt the machine profile's measured material thickness
    /// into the job sheet (the honest "update job thickness" action).
    func applyMeasuredThickness() {
        guard let measured = machineProfiles.profiles.first?.measuredThicknessMm,
              var sheet = job.sheets.first else {
            statusMessage = "No measured thickness to apply"
            return
        }
        sheet.height = measured
        job.sheets[0] = sheet
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
        let materialThickness = job.sheets.first?.height ?? 25.0
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

    func generateProfileToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        // Snapshot layer membership before the op — Profile must not reshuffle
        // shapes across layers (SPK-UI603a).
        let layerIDsBefore = shapeLayerIDs
        registerUndoPoint()
        // SPK-UI603: route through addToolpathNode so the strategy default tool
        // is assigned (was "No tool" when this path called addOperation bare).
        // Stock height comes from the sheet — matches Pocket/Drill/V-Carve.
        let params = ProfileToolpathParams()
        let stockHeight = job.sheets.first?.height ?? 6.0
        let result = ProfileToolpathEngine.compute(
            vectors: vectors,
            params: params,
            material: nil,
            stockHeightMm: stockHeight
        )
        let node = addToolpathNode(
            named: "Profile \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        // SPK-UI603c: form "Finish passes" ≠ engine depth/Z passes — label clearly.
        lastToolpathSummary =
            "Profile: \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s, " +
            "\(result.passCount) depth pass(es), \(params.finishPasses) finish pass(es)"
        statusMessage = lastToolpathSummary
        // SPK-UI603a: Profile must not reshuffle shape→layer membership.
        if shapeLayerIDs != layerIDsBefore {
            shapeLayerIDs = layerIDsBefore
            statusMessage = "Profile created — restored layer membership after unexpected reshuffle"
        }
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
            stockHeightMm: job.sheets.first?.height ?? 6.0
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

    private func encodeParams<T: Encodable>(_ params: T) -> String? {
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
    func recalculateDirtyToolpaths() -> Int {
        let dirtyBefore = toolpathTree.dirtyNodeCount
        guard dirtyBefore > 0 else {
            statusMessage = "No dirty toolpaths to recalculate"
            return 0
        }
        let regenerated = toolpathTree.recalculateDirtyToolpaths(
            vectors: vectors,
            material: job.sheets.first?.material,
            stockHeightMm: job.sheets.first?.height ?? 6.0,
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
    private func addToolpathNode(
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

    /// Generate a Pocket toolpath from the closed session vectors (zigzag
    /// default) and add it to the tree.
    func generatePocketToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        registerUndoPoint()
        let result = PocketToolpathEngine.compute(
            vectors: vectors,
            params: PocketToolpathParams(),
            material: nil,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Pocket \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(PocketToolpathParams())
        lastToolpathSummary =
            "Pocket: \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
        statusMessage = result.isTooSmall
            ? "Pocket: region too small for the tool — no cut generated"
            : lastToolpathSummary
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
            stockHeightMm: job.sheets.first?.height ?? 25.0
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

    /// Generate a Drill toolpath at the center of every closed vector
    /// (bounding-box centroid, default peck cycle) and add it to the tree.
    func generateDrillToolpath() {
        let depth = -min(job.sheets.first?.height ?? 25.0, 10.0)
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
        registerUndoPoint()
        let result = DrillToolpathEngine.compute(
            points: points,
            params: DrillToolpathParams(),
            material: nil,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Drill \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(DrillToolpathParams())
        lastToolpathSummary =
            "Drill: \(result.pointCount) hole(s), \(result.gcodeLines.count) lines"
        statusMessage = lastToolpathSummary
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
            stockHeightMm: job.sheets.first?.height ?? 25.0
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
        registerUndoPoint()
        let points = drillBankPoints(centeredOn: params)
        let result = DrillBankToolpathEngine.compute(
            points: points,
            params: params,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Drill Bank \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary =
            "Drill Bank: \(result.pointCount) hole(s) (\(params.gridCols)×\(params.gridRows) grid), \(result.gcodeLines.count) lines"
        statusMessage = lastToolpathSummary
    }

    /// SPK-H04 — wrapped fluting: flute straight lines around the rotary axis
    /// (flat X stays axial, flat Y wraps to A degrees). Uses the selected
    /// open vectors' endpoints as flute lines; falls back to a single
    /// center-line flute when no vectors are selected.
    func generateWrappedFluting() {
        let params = WrappedFlutingParams()
        registerUndoPoint()
        // Flute lines: use selected open polylines' segments; else a single
        // default flute along the job width.
        let selected = selectedShapeIndices.compactMap { shapes.indices.contains($0) ? shapes[$0] : nil }
        var flutePoints: [VectorPoint] = []
        if let first = selected.first, case .freehand(let pts) = first, pts.count >= 2 {
            flutePoints = pts
        } else {
            let w = job.sheets.first?.width ?? 100.0
            flutePoints = [VectorPoint(x: 0, y: 0), VectorPoint(x: w, y: 0)]
        }
        let result = WrappedFlutingToolpathEngine.compute(points: flutePoints, params: params)
        let node = addToolpathNode(
            named: "Wrapped Fluting \(toolpathTree.allNodes.count)",
            gcode: result.gcode,
            estimatedTime: TimeInterval(result.moveCount) * 0.02
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary =
            "Wrapped Fluting: \(result.moveCount) move(s) around Ø\(String(format: "%.1f", params.wrapDiameterMm))mm, \(result.gcode.count) lines"
        statusMessage = lastToolpathSummary
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
            stockHeightMm: job.sheets.first?.height ?? 25.0
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
    /// params) and add it to the tree.
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
        registerUndoPoint()
        let result = VCarveEngine.compute(
            vectors: vectors,
            params: VCarveParams(),
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "V-Carve \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(VCarveParams())
        lastToolpathSummary =
            "V-Carve: \(result.gcodeLines.count) lines, \(result.passCount) pass(es)"
        statusMessage = lastToolpathSummary
    }

    /// Generate a 3D ROUGH toolpath (z-level clearing) from the imported STL
    /// relief and add it to the tree (SPK-3D-spine-b).
    func generateRough3DToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No STL relief — import one via Design → STL Relief… first"
            return
        }
        registerUndoPoint()
        let params = HeightfieldRoughParams()
        let result = HeightfieldRoughEngine.compute(heightfield: hf, params: params)
        let node = addToolpathNode(
            named: "Rough 3D \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary =
            "Rough 3D: \(result.gcodeLines.count) lines, \(result.passCount) z-levels"
        statusMessage = lastToolpathSummary
    }

    /// Generate a 3D FINISH toolpath (surface-following) from the imported STL
    /// relief and add it to the tree (SPK-3D-spine-b).
    func generateFinish3DToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No STL relief — import one via Design → STL Relief… first"
            return
        }
        registerUndoPoint()
        let params = HeightfieldFinishParams()
        let result = HeightfieldFinishEngine.compute(heightfield: hf, params: params)
        let node = addToolpathNode(
            named: "Finish 3D \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        lastToolpathSummary =
            "Finish 3D: \(result.gcodeLines.count) lines, \(result.passCount) rows"
        statusMessage = lastToolpathSummary
    }

    // MARK: - Specialty strategies (SPK-0900 + SPK-0802 lean slices)

    /// Generate a Prism toolpath: parallel V-grooves across every closed
    /// vector (the prismatic sign effect) and add it to the tree.
    func generatePrismToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
        registerUndoPoint()
        let params = PrismToolpathParams()
        let result = PrismToolpathEngine.compute(
            paths: vectors,
            params: params,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Prism \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = result.featureCount > 0
            ? "Prism: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
            : "Prism: no closed vectors — the grooves raster needs closed shapes"
    }

    /// Generate a Fluting toolpath: the selected vectors ARE the flutes
    /// (draw parallel lines for a ribbed board), cut in step-down passes.
    func generateFlutingToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw flute lines first"
            return
        }
        registerUndoPoint()
        let params = FlutingToolpathParams()
        let result = FlutingToolpathEngine.compute(
            paths: vectors,
            params: params,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Fluting \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = result.featureCount > 0
            ? "Fluting: \(result.featureCount) flute(s), ~\(Int(result.estimatedTimeSeconds))s"
            : "Fluting: no usable vectors (need ≥ 2 points)"
    }

    /// Generate a Chamfer toolpath: V-bevel on the selected edges.
    func generateChamferToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select edges to chamfer"
            return
        }
        registerUndoPoint()
        let params = ChamferToolpathParams()
        let result = ChamferToolpathEngine.compute(
            paths: vectors,
            params: params,
            stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Chamfer \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = result.featureCount > 0
            ? "Chamfer: \(result.featureCount) edge(s), ~\(Int(result.estimatedTimeSeconds))s"
            : "Chamfer: no usable vectors"
    }

    /// Generate the female (pocket) or male (plug) half of a V-inlay.
    func generateInlayToolpath(variant: InlayToolpathParams.Variant) {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select the inlay shape"
            return
        }
        registerUndoPoint()
        var params = InlayToolpathParams()
        params.variant = variant
        let result: SpecialtyResult = variant == .pocket
            ? InlayToolpathEngine.computePocket(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
            : InlayToolpathEngine.computePlug(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
        let node = addToolpathNode(
            named: "Inlay \(variant == .pocket ? "Pocket" : "Plug") \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Inlay \(variant == .pocket ? "pocket" : "plug"): \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
            ? InlayToolpathEngine.computePocket(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
            : InlayToolpathEngine.computePlug(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
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
    func generateQuickEngraveToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import text/shapes first"
            return
        }
        registerUndoPoint()
        let params = QuickEngraveToolpathParams()
        let result = QuickEngraveToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Quick Engrave \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = result.featureCount > 0
            ? "Quick Engrave: \(result.featureCount) vector(s), ~\(Int(result.estimatedTimeSeconds))s"
            : "Quick Engrave: no usable vectors"
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
    func generatePhotoVCarveToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image (Model → Image Relief…) or STL first"
            return
        }
        registerUndoPoint()
        let params = PhotoVCarveToolpathParams()
        let result = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: params)
        let node = addToolpathNode(
            named: "Photo V-Carve \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Photo V-Carve: \(result.gcodeLines.count) lines, \(result.featureCount) passes, ~\(Int(result.estimatedTimeSeconds))s"
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
    func generateDragKnifeToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import shapes first"
            return
        }
        registerUndoPoint()
        let params = DragKnifeToolpathParams()
        let result = DragKnifeToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Drag Knife \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Drag Knife: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
    func generateTextureToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select a closed boundary first"
            return
        }
        registerUndoPoint()
        let params = TextureToolpathParams()
        let result = TextureToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Texture \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Texture: \(result.featureCount) groove(s), ~\(Int(result.estimatedTimeSeconds))s"
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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
    func generateSketchCarveToolpath() {
        guard let hf = job.stlHeightfield else {
            statusMessage = "No relief — import an image (Model → Image Relief…) or STL first"
            return
        }
        registerUndoPoint()
        let params = SketchCarveToolpathParams()
        let result = SketchCarveToolpathEngine.compute(heightfield: hf, params: params)
        let node = addToolpathNode(
            named: "Sketch Carve \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Sketch Carve: \(result.featureCount) edge cells, \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
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
    func generateRotaryWrapToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — draw or import shapes first"
            return
        }
        registerUndoPoint()
        let params = RotaryWrapToolpathParams()
        let result = RotaryWrapToolpathEngine.compute(
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
        )
        let node = addToolpathNode(
            named: "Rotary Wrap \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage = "Rotary Wrap: \(result.featureCount) path(s), ~\(Int(result.estimatedTimeSeconds))s"
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
            paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0
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

    /// Generate an Inlay op from a named V-Carve recipe preset (SPK-0802
    /// remainder): the recipe sets angle/depth/feeds on the real engine.
    func generateInlayToolpath(variant: InlayToolpathParams.Variant, recipeName: String? = nil) {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — select the inlay shape"
            return
        }
        registerUndoPoint()
        var params: InlayToolpathParams
        if let name = recipeName, let recipe = VCarveInlayRecipe.preset(named: name) {
            params = recipe.params(variant: variant)
            statusMessage = "Inlay \(variant == .pocket ? "pocket" : "plug") [\(recipe.name)]:"
        } else {
            params = InlayToolpathParams()
            params.variant = variant
            statusMessage = "Inlay \(variant == .pocket ? "pocket" : "plug"):"
        }
        let result: SpecialtyResult = variant == .pocket
            ? InlayToolpathEngine.computePocket(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
            : InlayToolpathEngine.computePlug(paths: vectors, params: params, stockHeightMm: job.sheets.first?.height ?? 25.0)
        let node = addToolpathNode(
            named: "Inlay \(variant == .pocket ? "Pocket" : "Plug") \(toolpathTree.allNodes.count)",
            gcode: result.gcodeLines,
            estimatedTime: result.estimatedTimeSeconds
        )
        node.paramsJSON = encodeParams(params)
        statusMessage += " \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s"
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
        let sheet = job.sheets.first
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
            stockHeightMm: job.sheets.first?.height ?? 25.0
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

    func loadFixtureGCodeIfNeeded() {
        guard gcodeLines.isEmpty else { return }
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("fixtures/gcode/calibration_square.nc"),
            Bundle.main.bundleURL
                .appendingPathComponent("fixtures/gcode/calibration_square.nc"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                gcodeLines = text
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                lastToolpathSummary = "Loaded fixture \(url.lastPathComponent) (\(gcodeLines.count) lines)"
                statusMessage = lastToolpathSummary
                return
            }
        }
        gcodeLines = [
            "G21",
            "G90",
            "G0 Z5",
            "G0 X0 Y0",
            "G1 Z-1 F200",
            "G1 X20 F800",
            "G1 Y20",
            "G1 X0",
            "G1 Y0",
            "G0 Z5",
            "M2",
        ]
        lastToolpathSummary = "Built-in air-cut square (\(gcodeLines.count) lines)"
        statusMessage = lastToolpathSummary
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
            selectedStage = .setup
        case .saveJob:
            savePackageToDefaultLocation()
        case .openJob:
            openPackageFromDefaultLocation()
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
            loadFixtureGCodeIfNeeded()
            statusMessage = "G-code ready (\(gcodeLines.count) lines) — use Machine stage to stream"
        case .importSVG:
            importSVGFromPanel()
        case .importSTLRelief:
            importSTLHeightfieldFromPanel()
        case .importImageRelief:
            importBitmapHeightfieldFromPanel()
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
        do {
            let result = try importSTLHeightfield(from: url)
            selectedStage = .design
            if result.success, let hf = result.heightfield {
                statusMessage = "STL relief: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
            } else {
                statusMessage = "STL import failed: \(result.errorMessage ?? "unknown error")"
            }
        } catch {
            statusMessage = "STL import failed: \(error.localizedDescription)"
        }
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

    private func savePackageToDefaultLocation() {
        do {
            try savePackage(to: defaultPackageURL())
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
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
}
