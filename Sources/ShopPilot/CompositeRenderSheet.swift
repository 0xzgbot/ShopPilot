import SwiftUI
import ShopPilotCore

// MARK: - SPK-0708 Composite Render Sheet

/// SPK-0708 — sheet that lets the user pick a material preset (or custom
/// material/finish/lighting) and run a composite render of the active relief.
struct CompositeRenderSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Callback invoked with the chosen config when the user hits Render.
    var onRender: (MetalCompositeConfig) -> Void

    @State private var selectedPresetName = MetalCompositeRenderEngine.presets.first?.name ?? ""
    @State private var material: RenderMaterial = .aluminum
    @State private var finish: SurfaceFinish = .brushed
    @State private var reflectivity = 0.5
    @State private var roughness = 0.3
    @State private var metalness = 0.8
    @State private var ambientIntensity = 0.3
    @State private var directionalIntensity = 1.0
    @State private var directionalAngle = 45.0
    @State private var renderResult: RenderOutput?

    private var currentConfig: MetalCompositeConfig {
        MetalCompositeConfig(
            material: material,
            finish: finish,
            lighting: RenderLighting(
                ambientIntensity: ambientIntensity,
                directionalIntensity: directionalIntensity,
                directionalAngle: directionalAngle
            ),
            reflectivity: reflectivity,
            roughness: roughness,
            metalness: metalness
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Preset") {
                    Picker("Material Preset", selection: $selectedPresetName) {
                        ForEach(MetalCompositeRenderEngine.presets, id: \.name) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                    }
                    .onChange(of: selectedPresetName) { _, newName in
                        if let preset = MetalCompositeRenderEngine.getPreset(named: newName) {
                            material = preset.material
                            finish = preset.finish
                            reflectivity = preset.reflectivity
                            roughness = preset.roughness
                            metalness = preset.metalness
                        }
                    }
                }

                Section("Material") {
                    Picker("Material", selection: $material) {
                        Text("Aluminum").tag(RenderMaterial.aluminum)
                        Text("Steel").tag(RenderMaterial.steel)
                        Text("Copper").tag(RenderMaterial.copper)
                        Text("Brass").tag(RenderMaterial.brass)
                        Text("Titanium").tag(RenderMaterial.titanium)
                        Text("Wood").tag(RenderMaterial.wood)
                        Text("Plastic").tag(RenderMaterial.plastic)
                        Text("Glass").tag(RenderMaterial.glass)
                        Text("Custom").tag(RenderMaterial.custom)
                    }
                    Picker("Finish", selection: $finish) {
                        Text("Matte").tag(SurfaceFinish.matte)
                        Text("Brushed").tag(SurfaceFinish.brushed)
                        Text("Polished").tag(SurfaceFinish.polished)
                        Text("Mirrored").tag(SurfaceFinish.mirrored)
                        Text("Sandblasted").tag(SurfaceFinish.sandblasted)
                        Text("Anodized").tag(SurfaceFinish.anodized)
                        Text("Custom").tag(SurfaceFinish.custom)
                    }
                    Slider(value: $reflectivity, in: 0...1) {
                        Text("Reflectivity")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("1")
                    }
                    Slider(value: $roughness, in: 0...1) {
                        Text("Roughness")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("1")
                    }
                    Slider(value: $metalness, in: 0...1) {
                        Text("Metalness")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("1")
                    }
                }

                Section("Lighting") {
                    Slider(value: $ambientIntensity, in: 0...1) {
                        Text("Ambient")
                    }
                    Slider(value: $directionalIntensity, in: 0...3) {
                        Text("Directional")
                    }
                    Slider(value: $directionalAngle, in: 0...180) {
                        Text("Light Angle")
                    }
                }

                if let result = renderResult {
                    Section {
                        if result.success {
                            Label("Rendered \(result.width)×\(result.height) PNG (\(result.fileSize) bytes)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved to: \(result.imageUrl)")
                                .font(.caption2)
                                .textSelection(.enabled)
                        } else {
                            Label("Render failed: \(result.errorMessage ?? "unknown")", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Composite Render")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Render") {
                        renderResult = MetalCompositeRenderEngine.render(currentConfig)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 560)
    }
}
