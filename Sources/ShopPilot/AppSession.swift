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

    /// Current selection (vector path IDs) — session-owned, not view-local.
    @Published var selectedVectorIDs: Set<UUID> = []

    /// Inspector/browser selection type (job, sheet, layer, toolpath).
    @Published var selection: SelectionType = .none

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
        job.sheets[0].layers[0].vectors = paths
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
        markDirty()
        return true
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
        if var sheet = job.sheets.first, !sheet.layers.isEmpty {
            sheet.layers[0].vectors = vectors
            job.sheets[0] = sheet
        }
        markDirty()
    }

    func addDemoRectangle() {
        let shape = VectorShape.rectangle(
            origin: ShopPilotGeometry.VectorPoint(x: 10, y: 10),
            width: 80,
            height: 50
        )
        addShapes([shape])
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
        selection = .none
    }

    var hasSelection: Bool { !selectedVectorIDs.isEmpty }

    // MARK: - Toolpaths

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
