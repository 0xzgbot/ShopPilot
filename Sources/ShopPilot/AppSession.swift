import Foundation
import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

/// Shared document + toolpath session for the main window.
@MainActor
final class AppSession: ObservableObject {
    @Published var selectedStage: Stage = .setup
    @Published var job: Job
    @Published var shapes: [VectorShape] = []
    @Published var vectors: [VectorPath] = []
    @Published var gcodeLines: [String] = []
    @Published var lastToolpathSummary: String = "No toolpath generated"
    @Published var statusMessage: String = "Ready"
    @Published var showCommandPalette = false
    @Published var showPreferences = false
    @Published var showSafetyDisclaimer = true
    @Published var safetyAccepted = false

    let docVars = DocumentVariablesModel()

    init() {
        var job = Job(name: "Untitled Job")
        _ = job.ensureSingleSheet()
        self.job = job
        self.safetyAccepted = UserDefaults.standard.bool(forKey: "shop_pilot_safety_accepted")
        self.showSafetyDisclaimer = !self.safetyAccepted
    }

    var sheetCount: Int { job.sheets.count }
    var layerCount: Int {
        job.sheets.first?.layers.count ?? 0
    }

    func acceptSafety() {
        safetyAccepted = true
        showSafetyDisclaimer = false
        UserDefaults.standard.set(true, forKey: "shop_pilot_safety_accepted")
    }

    func replaceJob(_ newJob: Job) {
        job = newJob
        statusMessage = "Job “\(newJob.name)” ready"
        selectedStage = .design
    }

    func addShapes(_ newShapes: [VectorShape]) {
        shapes.append(contentsOf: newShapes)
        let converted = GeometryBridge.toCorePaths(newShapes)
        vectors.append(contentsOf: converted)
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
    }

    func addDemoRectangle() {
        let shape = VectorShape.rectangle(
            origin: ShopPilotGeometry.VectorPoint(x: 10, y: 10),
            width: 80,
            height: 50
        )
        addShapes([shape])
    }

    func generateProfileToolpath() {
        guard !vectors.isEmpty else {
            statusMessage = "No vectors — import SVG or add a demo shape first"
            return
        }
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
        selectedStage = .cut
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
        // Built-in mini fixture when file missing
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
}
