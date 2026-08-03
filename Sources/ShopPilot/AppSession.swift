import Foundation
import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

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
    @Published var gcodeLines: [String] = []
    @Published var lastToolpathSummary: String = "No toolpath generated"
    @Published var statusMessage: String = "Ready"
    @Published var showCommandPalette = false
    @Published var showPreferences = false
    @Published var showSafetyDisclaimer = true
    @Published var safetyAccepted = false

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

    /// Current selection (vector path IDs) — session-owned, not view-local.
    @Published var selectedVectorIDs: Set<UUID> = []

    /// Design-canvas selection: indices into `shapes` (session-owned so the
    /// canvas and the ops toolbar share one selection state).
    @Published var selectedShapeIndices: Set<Int> = []

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
    }

    // MARK: - Derived document access

    /// The job's layers, read from the first sheet. Owned by the job, exposed here.
    var layers: [Layer] {
        job.sheets.first?.layers ?? []
    }

    /// Flat list of all vector paths in the document (derived from design shapes).
    var vectors: [VectorPath] {
        GeometryBridge.toCorePaths(shapes)
    }

    /// Toolpaths list: operation nodes owned by the session's toolpath tree.
    var toolpaths: [ToolpathTreeNode] {
        toolpathTree.root.children
    }

    var sheetCount: Int { job.sheets.count }
    var layerCount: Int {
        job.sheets.first?.layers.count ?? 0
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
        let gcodeLines: [String]
        let selectedVectorIDs: Set<UUID>
    }

    private func captureSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            job: job,
            shapes: shapes,
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
        gcodeLines = snapshot.gcodeLines
        selectedVectorIDs = snapshot.selectedVectorIDs
        markDirty()
    }

    // MARK: - Package persist

    /// Build the current session state as a package payload.
    func makePackagePayload() -> ShopPilotPackagePayload {
        var payloadJob = job
        payloadJob.documentVariables = docVars.variables
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
        shapes = Self.shapesFromLayerVectors(payload.job)
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
        let paths = vectors
        if job.sheets[0].layers.isEmpty {
            job.sheets[0].layers.append(Layer(name: "Layer 1"))
        }
        // Sync into the active layer (falls back to layer 0) so multi-layer
        // documents keep each layer's own vectors.
        let index = activeLayerIndex(in: job.sheets[0].layers)
        job.sheets[0].layers[index].vectors = paths
    }

    /// Push the current design shapes into the session's active sheet/layer so
    /// the persisted document and Cut stage always see the live vectors.
    ///
    /// Shapes are synced into the *active* layer (the one selected in the layer
    /// panel, falling back to the first layer) rather than always layer 0, so
    /// multi-layer documents don't get their vectors clobbered into one layer.
    private func syncLayerVectors() {
        guard var sheet = job.sheets.first, !sheet.layers.isEmpty else { return }
        let targetIndex = activeLayerIndex(in: sheet.layers)
        sheet.layers[targetIndex].vectors = vectors
        job.sheets[0] = sheet
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

    /// Reconstruct design shapes from persisted layer vectors (freehand polylines).
    static func shapesFromLayerVectors(_ job: Job) -> [VectorShape] {
        job.sheets.flatMap(\.layers).flatMap(\.vectors).map { path in
            let pts = path.points.map { ShopPilotGeometry.VectorPoint(x: $0.x, y: $0.y) }
            return VectorShape.freehand(points: pts)
        }
    }

    // MARK: - Job lifecycle

    func acceptSafety() {
        safetyAccepted = true
        showSafetyDisclaimer = false
        UserDefaults.standard.set(true, forKey: "shop_pilot_safety_accepted")
    }

    func replaceJob(_ newJob: Job) {
        job = newJob
        docVars.variables = newJob.documentVariables
        shapes = []
        gcodeLines = []
        selectedVectorIDs = []
        selection = .job
        selectedToolpathID = nil
        toolpathTree = ToolpathTreeManager()
        lastToolpathSummary = "No toolpath generated"
        statusMessage = "Job “\(newJob.name)” ready"
        selectedStage = .design
        packageURL = nil
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

    /// Toggle layer lock (lock icon) through the session sheet.
    func setLayerLocked(id: UUID, isLocked: Bool) {
        guard var sheet = job.sheets.first,
              let index = sheet.layers.firstIndex(where: { $0.id == id }) else { return }
        guard sheet.layers[index].isLocked != isLocked else { return }
        registerUndoPoint()
        sheet.layers[index].isLocked = isLocked
        job.sheets[0] = sheet
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
        let converted = GeometryBridge.toCorePaths(newShapes)
        if var sheet = job.sheets.first {
            if sheet.layers.isEmpty {
                sheet.layers.append(Layer(name: "Layer 1"))
            }
            for path in converted {
                sheet.layers[0].addVector(path)
            }
            job.sheets[0] = sheet
        }
        statusMessage = "Added \(newShapes.count) shape(s) — \(vectors.count) path(s) total"
        selectedStage = .design
        markDirty()
    }

    func moveShape(at index: Int, by dx: Double, dy: Double) {
        guard shapes.indices.contains(index) else { return }
        registerUndoPoint()
        shapes[index] = shapes[index].translated(by: dx, dy)
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
        }
        selectedShapeIndices = []
        syncLayerVectors()
        markDirty()
    }

    /// Replace the selected shapes with the op results. The originals are
    /// removed and the results are inserted at the lowest selected index.
    /// Empty results delete the shape entirely (e.g. full boolean subtract).
    func replaceSelectedShapes(with results: [VectorShape]) {
        let indices = selectedShapeIndices.sorted()
        guard !indices.isEmpty else { return }
        registerUndoPoint()
        let insertAt = indices.first ?? 0
        for index in indices.reversed() where shapes.indices.contains(index) {
            shapes.remove(at: index)
        }
        shapes.insert(contentsOf: results, at: min(insertAt, shapes.count))
        selectedShapeIndices = Set(results.indices.map { min(insertAt, shapes.count - results.count) + $0 })
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

    var hasSelection: Bool { !selectedVectorIDs.isEmpty || !selectedShapeIndices.isEmpty }

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
        registerUndoPoint()
        let result = ProfileToolpathEngine.compute(
            vectors: vectors,
            params: ProfileToolpathParams(),
            material: nil,
            stockHeightMm: 6.0
        )
        gcodeLines = result.gcodeLines
        lastToolpathSummary =
            "Profile: \(result.gcodeLines.count) lines, ~\(Int(result.estimatedTimeSeconds))s, \(result.passCount) pass(es)"
        statusMessage = lastToolpathSummary
        let node = toolpathTree.addOperation("Profile \(toolpathTree.allNodes.count)")
        node.toolpathResult = result.gcodeLines.joined(separator: "\n")
        node.estimatedTimeSeconds = result.estimatedTimeSeconds
        selectToolpath(node.id)
        selectedStage = .cut
        markDirty()
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
        default:
            statusMessage = "Command: \(id.name)"
        }
        showCommandPalette = false
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
