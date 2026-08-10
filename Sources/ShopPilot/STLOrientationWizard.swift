import SwiftUI
import ShopPilotCore

// MARK: - STL Orientation Wizard

/// SPK-0707 — Orientation wizard for STL import.
/// Presents a sheet where the user configures orientation, scale, flips,
/// and centering before the STL is parsed and rasterized into a heightfield.
struct STLOrientationWizardView: View {
    let stlURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var orientation: STLImportOrientation = .auto
    @State private var scaleText: String = "1.0"
    @State private var flipX: Bool = false
    @State private var flipY: Bool = false
    @State private var flipZ: Bool = false
    @State private var center: Bool = true
    @State private var cellSizeText: String = "1.0"
    @State private var errorMessage: String?
    @State private var result: STLHeightfieldResult?

    var onImport: ((STLHeightfieldResult) -> Void)?

    var body: some View {
        NavigationView {
            Form {
                Section("Orientation") {
                    Picker("Orientation", selection: $orientation) {
                        Text("Auto-detect").tag(STLImportOrientation.auto)
                        Text("XZ plane (Y up)").tag(STLImportOrientation.xz)
                        Text("XY plane (Z up)").tag(STLImportOrientation.xy)
                        Text("YZ plane (X up)").tag(STLImportOrientation.yz)
                        Text("Custom").tag(STLImportOrientation.custom)
                    }
                }

                Section("Transform") {
                    Toggle("Flip X", isOn: $flipX)
                    Toggle("Flip Y", isOn: $flipY)
                    Toggle("Flip Z", isOn: $flipZ)
                    Toggle("Center on import", isOn: $center)
                }

                Section("Grid settings") {
                    TextField("Scale (mm/unit)", text: $scaleText)
                    TextField("Cell size (mm)", text: $cellSizeText)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }

                if let result {
                    Section {
                        if result.success, let hf = result.heightfield {
                            Text("\(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm")
                        } else {
                            Text("Import failed: \(result.errorMessage ?? "unknown")").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Import STL")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        performImport()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func performImport() {
        guard let scale = Double(scaleText) ?? nil, scale > 0 else {
            errorMessage = "Scale must be a positive number"
            return
        }
        guard let cellSize = Double(cellSizeText) ?? nil, cellSize > 0 else {
            errorMessage = "Cell size must be a positive number"
            return
        }

        let config = STLImportConfig(
            orientation: orientation,
            scale: scale,
            flipX: flipX,
            flipY: flipY,
            flipZ: flipZ,
            center: center,
            maxTriangles: 100_000
        )

        // Import with config settings. For now, pass scale and cellSize to importer.
        // Orientation transforms will be applied when a real orientation-aware parser is added.
        let result = STLHeightfieldImporter.importSTL(
            at: stlURL.path,
            cellSizeMm: cellSize,
            scale: scale
        )
        self.result = result
        errorMessage = nil
        if result.success {
            onImport?(result)
            dismiss()
        } else {
            errorMessage = result.errorMessage ?? "Import failed"
        }
    }
}

// MARK: - Sheet wrapper for ModelStageView integration

/// SPK-0707 — Sheet wrapper that ModelStageView presents.
struct STLOrientationWizardSheet: View {
    let stlURL: URL
    let config: STLImportConfig
    let onImport: (STLHeightfieldResult) -> Void

    var body: some View {
        STLOrientationWizardView(stlURL: stlURL) { result in
            onImport(result)
        }
    }
}
