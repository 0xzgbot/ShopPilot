import SwiftUI
import ShopPilotCore

// MARK: - SPK-0906 Laser Toolpath Sheet

/// SPK-0906 — sheet that lets the user pick a laser mode, power and feed
/// speed, then generate laser G-code into the Cut tree.
struct LaserToolpathSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Callback invoked with the chosen settings when the user hits Generate.
    var onGenerate: (LaserMode, Double, Double) -> Void

    @State private var mode: LaserMode = .cut
    @State private var powerPercent: Double = 80.0
    @State private var speedText = "1200"

    private var speedValue: Double {
        Double(speedText) ?? 1000.0
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Laser Mode") {
                    Picker("Mode", selection: $mode) {
                        Text("Engrave").tag(LaserMode.engrave)
                        Text("Cut").tag(LaserMode.cut)
                        Text("Score").tag(LaserMode.score)
                        Text("Fill").tag(LaserMode.fill)
                        Text("Raster").tag(LaserMode.raster)
                        Text("Vector").tag(LaserMode.vector)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Settings") {
                    Slider(value: $powerPercent, in: 0...100, step: 1) {
                        Text("Power")
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("100%")
                    }
                    Text("Power: \(Int(powerPercent))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Speed (mm/min)", text: $speedText)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    Text("Speed: \(Int(speedValue)) mm/min — cut G-code feeds at this rate; engrave runs at half speed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Laser Toolpath")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        onGenerate(mode, powerPercent, speedValue)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 380)
    }
}
