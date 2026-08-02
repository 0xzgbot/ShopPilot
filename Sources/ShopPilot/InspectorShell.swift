import SwiftUI
import ShopPilotCore

// MARK: - Inspector Shell

/// Stage-specific inspector panel wired to the live AppSession.
struct InspectorShell: View {
    @ObservedObject var session: AppSession
    @Binding var currentStage: Stage

    var body: some View {
        VStack(spacing: 0) {
            Text("PROPERTIES")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
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
        }
    }

    // MARK: - Live document summary

    private var documentSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DOCUMENT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

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
                SelectionBadge(name: "Sheet", type: id.uuidString.prefix(8).uppercased())
            case .layer(let id):
                let layerName = session.layers.first(where: { $0.id == id })?.name ?? "Layer"
                SelectionBadge(name: layerName, type: id.uuidString.prefix(8).uppercased())
            case .toolpath(let id):
                let tpName = session.toolpaths.first(where: { $0.id == id })?.name ?? "Toolpath"
                SelectionBadge(name: tpName, type: id.uuidString.prefix(8).uppercased())
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
            Text("STOCK DIMENSIONS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let sheet = session.job.sheets.first {
                HStack(spacing: 8) {
                    dimensionField(label: "Width", value: String(format: "%.1f", sheet.width))
                    dimensionField(label: "Depth", value: String(format: "%.1f", sheet.depth))
                    dimensionField(label: "Height", value: String(format: "%.1f", sheet.height))
                }
            }

            if !session.docVars.variables.isEmpty {
                Text("DOCUMENT VARIABLES")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(session.docVars.variables.prefix(6)) { variable in
                    PropertyRow(label: variable.key, value: variable.value)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func dimensionField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
    }

    // MARK: - Design Stage

    private var designInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAYERS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

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
            Text("3D MODEL")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text("Requires Studio3D tier.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Cut Stage

    private var cutInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOOLPATHS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

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
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
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
