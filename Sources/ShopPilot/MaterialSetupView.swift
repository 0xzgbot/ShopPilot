import SwiftUI
import ShopPilotCore

// MARK: - Material Setup View

/// SPK-1130 — Material setup UI bound to the session sheet.
///
/// Edits the stock W/D/H (mm) and the material of the session's first sheet
/// through `AppSession` (undo + dirty tracking). Material selection also
/// persists via `MaterialStore` so the last-used material survives relaunches
/// and becomes the default for newly created jobs.
public struct MaterialSetupView: View {

    @ObservedObject var session: AppSession

    @State private var widthText = ""
    @State private var depthText = ""
    @State private var heightText = ""

    init(session: AppSession) {
        self.session = session
    }

    private var sheet: Sheet? { session.job.sheets.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if sheet != nil {
                materialSection
                presetSection
                stockSection
                summary
            } else {
                Text("No sheet in this job yet — create a job first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .onAppear(perform: syncFromSheet)
        .onChange(of: session.job.sheets.first?.id) { _ in
            syncFromSheet()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube.transparent")
                .foregroundStyle(Color.accentColor)
            Text("Material Setup")
                .font(.headline)
            Spacer()
            if let name = sheet?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MATERIAL")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("Material", selection: materialBinding) {
                Text("None").tag("")
                ForEach(categories, id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(MaterialDatabase.shared.lookup(byCategory: category)) { material in
                            Text(material.displayName).tag(material.name)
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            // SPK-visual — material swatch chips: the four brand surface
            // palettes rendered as visible wood/acrylic chips (the same
            // palettes the Preview heightfield tints with). Click to apply.
            HStack(spacing: 6) {
                ForEach(MaterialSurfacePalette.presets, id: \.name) { palette in
                    MaterialSwatchChip(palette: palette, isSelected: materialBinding.wrappedValue == palette.name) {
                        materialBinding.wrappedValue = palette.name
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A tappable material chip: top-skin color band over the base color,
    /// with the name — reads like the real stock at a glance.
    private struct MaterialSwatchChip: View {
        let palette: MaterialSurfacePalette
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 0) {
                    // Skin band (top color).
                    Rectangle()
                        .fill(Color(red: palette.topColor.r, green: palette.topColor.g, blue: palette.topColor.b))
                        .frame(height: 14)
                    // Base band (what the cut reveals).
                    Rectangle()
                        .fill(Color(red: palette.baseColor.r, green: palette.baseColor.g, blue: palette.baseColor.b))
                        .frame(height: 10)
                    Text(palette.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                }
                .frame(width: 64)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isSelected ? SP.Tint.brand : Color.secondary.opacity(0.3),
                                      lineWidth: isSelected ? 1.5 : 0.5)
                )
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? SP.Tint.brand.opacity(0.08) : .clear)
                )
            }
            .buttonStyle(.plain)
            .help("\(palette.name) — \(palette.surfaceLayers) surface layer(s)")
            .accessibilityLabel(palette.name)
        }
    }

    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STOCK DIMENSIONS (mm)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                dimensionField(label: "Width", text: $widthText)
                dimensionField(label: "Depth", text: $depthText)
                dimensionField(label: "Height", text: $heightText)
            }
        }
    }

    /// SPK-1132 — one-click stock sheet preset picker. Selecting a preset
    /// applies its W/D/H + name to the session sheet (undoable, dirty) and
    /// records the preset name for persistence. "Custom…" = manual dims.
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STOCK SHEET PRESET")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("Stock Sheet Preset", selection: presetBinding) {
                Text("Custom…").tag("")
                Section("Imperial") {
                    ForEach(StockSheetPresets.imperial, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
                Section("Metric") {
                    ForEach(StockSheetPresets.metric, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summary: some View {
        Group {
            if let material = sheet?.material {
                Text("\(material.displayName) · \(material.category.displayName) · "
                    + "\(Int(material.maxFeedRateMmPerMin)) mm/min max feed · "
                    + "\(Self.formatDim(material.maxDepthOfCutMm)) mm/pass · "
                    + "\(material.coolantType.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No material selected — toolpaths will use conservative defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dimensionField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(commitDimensions)
        }
    }

    // MARK: - Bindings & actions

    /// Pick by material name ("" = none); resolves through the database and
    /// persists the choice as the last-used material.
    private var materialBinding: Binding<String> {
        Binding(
            get: { sheet?.material?.name ?? "" },
            set: { newName in
                let material = newName.isEmpty
                    ? nil
                    : MaterialDatabase.shared.lookup(byName: newName)
                session.setSheetMaterial(material)
                MaterialStore().saveLastUsed(material)
            }
        )
    }

    /// Pick a stock sheet preset by name ("" = custom). Applies through the
    /// session so the change is undoable, dirty, and persisted.
    private var presetBinding: Binding<String> {
        Binding(
            get: { sheet?.stockPresetName ?? "" },
            set: { newName in
                guard let preset = StockSheetPresets.preset(named: newName) else { return }
                session.applyStockPreset(preset)
            }
        )
    }

    private var categories: [MaterialCategory] {
        MaterialDatabase.shared.materialsByCategory.keys
            .sorted { $0.displayName < $1.displayName }
    }

    private func syncFromSheet() {
        guard let sheet else { return }
        widthText = Self.formatDim(sheet.width)
        depthText = Self.formatDim(sheet.depth)
        heightText = Self.formatDim(sheet.height)
    }

    private func commitDimensions() {
        guard let parsed = parsedDimensions else {
            syncFromSheet() // Revert invalid input to the sheet's values.
            return
        }
        session.updateSheetDimensions(
            width: parsed.0,
            depth: parsed.1,
            height: parsed.2
        )
    }

    /// (width, depth, height) when every field parses to a positive number.
    private var parsedDimensions: (Double, Double, Double)? {
        guard
            let width = Double(widthText.trimmingCharacters(in: .whitespaces)),
            let depth = Double(depthText.trimmingCharacters(in: .whitespaces)),
            let height = Double(heightText.trimmingCharacters(in: .whitespaces)),
            width > 0, depth > 0, height > 0
        else { return nil }
        return (width, depth, height)
    }

    private static func formatDim(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct MaterialSetupView_Previews: PreviewProvider {
    static var previews: some View {
        MaterialSetupView(session: AppSession())
            .frame(width: 420, height: 320)
            .padding()
    }
}
#endif
