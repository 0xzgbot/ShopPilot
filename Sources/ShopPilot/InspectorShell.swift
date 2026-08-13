import SwiftUI
import ShopPilotCore

// MARK: - Inspector Shell

/// Stage-specific inspector panel wired to the live AppSession.
struct InspectorShell: View {
    @ObservedObject var session: AppSession
    @Binding var currentStage: Stage

    /// SPK-1607 — millimetre formatting for the selection geometry readout
    /// (1 decimal; 3 for sub-mm values).
    private static func mm(_ value: Double) -> String {
        value >= 1 ? String(format: "%.1f", value) : String(format: "%.3f", value)
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(title: currentStage.title) {
                Image(systemName: currentStage.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: SP.Space.l) {
                    documentSummary
                    selectionInfo

                    switch currentStage {
                    case .setup:
                        setupInspector
                    case .design:
                        designInspector
                    case .model:
                        modelInspector
                    case .cut:
                        cutInspector
                    case .preview:
                        previewInspector
                    case .machine:
                        machineInspector
                    }
                }
            }
            .padding(.top, SP.Space.m)
        }
    }

    // MARK: - Live document summary

    private var documentSummary: some View {
        VStack(alignment: .leading, spacing: SP.Space.xs) {
            SectionLabel("Document")
                .padding(.horizontal, SP.Space.m)

            PropertyRow(label: "Job", value: session.job.name.isEmpty ? "Untitled" : session.job.name)
            PropertyRow(label: "Sheets", value: "\(session.sheetCount)")
            PropertyRow(label: "Layers", value: "\(session.layerCount)")
            PropertyRow(label: "Vectors", value: "\(session.vectors.count)")
            PropertyRow(label: "Toolpaths", value: "\(session.toolpaths.count)")

            if session.isDirty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                    Text("Unsaved changes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Selection Info

    private var selectionInfo: some View {
        Group {
            switch session.selection {
            case .none:
                if session.hasSelection {
                    Text("\(session.selectedVectorIDs.count) vector(s) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    Text("No selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            case .job:
                SelectionBadge(name: "Job", type: session.job.name)
            case .sheet(let id):
                let sheetName = session.job.sheets.first(where: { $0.id == id })?.name ?? "Sheet"
                SelectionBadge(name: sheetName, type: "Sheet")
            case .layer(let id):
                let layerName = session.layers.first(where: { $0.id == id })?.name ?? "Layer"
                SelectionBadge(name: layerName, type: "Layer")
            case .toolpath(let id):
                let tp = session.toolpaths.first(where: { $0.id == id })
                SelectionBadge(name: tp?.name ?? "Toolpath", type: tp?.typeLabel ?? "Operation")
            }
        }
    }

    private func SelectionBadge(name: String, type: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(type)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Setup Stage

    private var setupInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Stock dimensions")

            if let sheet = session.activeSheet {
                StockDimensionEditor(session: session, sheet: sheet)
                if session.job.sheets.count > 1 {
                    Text("Editing active sheet: \(sheet.name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No sheet in this job yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !session.docVars.variables.isEmpty {
                SectionLabel("Document variables")
                    .padding(.top, 4)

                ForEach(session.docVars.variables.prefix(6)) { variable in
                    PropertyRow(label: variable.key, value: variable.value)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// Editable stock W/D/H bound to the session's ACTIVE sheet. Commits go
    /// through `updateSheetDimensions` (undo + dirty), so the inspector never
    /// shows fake or first-sheet-only values (SPK-1400g).
    private struct StockDimensionEditor: View {
        @ObservedObject var session: AppSession
        let sheet: Sheet

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(sheet.stockDimensions, id: \.label) { dimension in
                        StockDimensionField(session: session, dimension: dimension)
                    }
                }
            }
        }
    }

    /// One editable W/D/H field. Labels + formatting come from the Core
    /// `StockDimension` seam; commits target the axis the field represents.
    private struct StockDimensionField: View {
        @ObservedObject var session: AppSession
        let dimension: StockDimension
        @State private var text: String = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(dimension.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField(dimension.label, text: $text)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
            }
            .onAppear(perform: syncFromSheet)
            .onChange(of: session.activeSheetID) { _ in syncFromSheet() }
            .onChange(of: dimension.valueMm) { _ in syncFromSheet() }
        }

        private func syncFromSheet() {
            text = dimension.formatted
        }

        private func commit() {
            guard let parsed = Double(text.trimmingCharacters(in: CharacterSet.whitespaces)),
                  parsed > 0,
                  let sheet = session.activeSheet else {
                syncFromSheet() // Revert invalid input to the sheet's values.
                return
            }
            session.updateSheetDimensions(
                width: dimension.axis == .width ? parsed : sheet.width,
                depth: dimension.axis == .depth ? parsed : sheet.depth,
                height: dimension.axis == .height ? parsed : sheet.height
            )
            syncFromSheet()
        }
    }

    // MARK: - Design Stage

    private var designInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            // SPK-1607 — selected-vector geometry: exactly one selected
            // shape shows its bounding box X/Y/W/H (mm); none hides the
            // block; multi shows the count (the selectionInfo badge above
            // already handles the count).
            if session.selectedShapeIndices.count == 1,
               let index = session.selectedShapeIndices.first,
               session.shapes.indices.contains(index) {
                let rect = session.shapes[index].boundingRect
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Selection")
                    HStack(spacing: 10) {
                        PropertyRow(label: "X", value: Self.mm(rect.minX))
                        PropertyRow(label: "Y", value: Self.mm(rect.minY))
                        PropertyRow(label: "W", value: Self.mm(rect.width))
                        PropertyRow(label: "H", value: Self.mm(rect.height))
                    }
                }
                .padding(.horizontal, 12)
            }

            SectionLabel("Layers")

            if session.layers.isEmpty {
                Text("No layers yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.layers) { layer in
                    HStack {
                        Image(systemName: layer.isLocked ? "lock.fill" : "layers.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)

                        Text(layer.name)
                            .font(.system(size: 13))

                        Spacer()

                        Text("\(layer.vectors.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                _ = session.addLayer(Layer(name: "Layer \(session.layerCount + 1)"))
            } label: {
                Label("Add Layer", systemImage: "plus.circle.fill")
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Model Stage

    private var modelInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("3D model")

            if let hf = session.job.stlHeightfield {
                PropertyRow(label: "Grid", value: "\(hf.width)×\(hf.height)")
                PropertyRow(label: "Cell", value: String(format: "%.1f mm", hf.cellSizeMm))
                PropertyRow(label: "Max height", value: String(format: "%.1f mm", hf.maxHeight))
                PropertyRow(label: "Components", value: "\(session.reliefComponents.count)")
                Text("Edit the relief in the Model stage; Rough 3D / Finish 3D add toolpaths to Cut.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No relief yet. Import an STL or add an image relief to start modeling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Cut Stage

    private var cutInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Toolpaths")

            if session.toolpaths.isEmpty {
                Text("No toolpaths yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.toolpaths) { tp in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tp.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("~\(Int(tp.estimatedTimeSeconds))s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(session.lastToolpathSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Preview Stage

    private var previewInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            PropertyRow(label: "G-code lines", value: "\(session.gcodeLines.count)")
            PropertyRow(label: "Paths", value: "\(session.vectors.count)")
            Text(session.lastToolpathSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Machine Stage

    private var machineInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use the Machine panel for jog and stream controls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Property Row Helper

private struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: SP.Space.s) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: SP.Space.s)

            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, SP.Space.m)
        .frame(height: 20)
    }
}

// MARK: - Preview

#if canImport(SwiftUI) && DEBUG
struct InspectorShell_Previews: PreviewProvider {
    static var previews: some View {
        InspectorShell(session: AppSession(), currentStage: .constant(.setup))
            .frame(width: 280)
    }
}
#endif
