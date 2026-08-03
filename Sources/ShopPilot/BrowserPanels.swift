import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

// MARK: - Browser Divider

/// Thin vertical divider between panels and main content.
struct BrowserDivider: View {
    let width: CGFloat = 1
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: width)
    }
}

// MARK: - Left Panel (Document Tree)

/// Left browser panel showing document structure tree — wired to AppSession.
/// Layers get full CRUD: add, rename (double-click / context menu), visibility,
/// lock, reorder (up/down chevrons), and delete (context menu).
struct LeftPanelView: View {
    @ObservedObject var session: AppSession
    @State private var selectedItemID: String? = nil
    @State private var editingLayerID: UUID? = nil
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("DOCUMENT")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                // Dirty indicator
                if session.isDirty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Job root
                    treeItem(
                        id: "job",
                        title: session.job.name.isEmpty ? "Untitled" : session.job.name,
                        icon: "folder.fill",
                        isExpanded: true,
                        selectedItemID: $selectedItemID
                    )

                    // Sheets + their interactive layer lists
                    ForEach(session.job.sheets, id: \.id) { sheet in
                        treeItem(
                            id: "sheet_\(sheet.id.uuidString)",
                            title: sheet.name,
                            icon: "doc.fill",
                            isExpanded: true,
                            selectedItemID: $selectedItemID
                        )

                        layerSection(sheet)
                    }

                    // Toolpaths section
                    if !session.toolpaths.isEmpty {
                        ForEach(session.toolpaths, id: \.id) { tp in
                            treeItem(
                                id: "tp_\(tp.id.uuidString)",
                                title: tp.name + (tp.isDirty ? " ⚠" : ""),
                                icon: "scissors",
                                isExpanded: false,
                                selectedItemID: $selectedItemID,
                                indentLevel: 0
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Layers section (SPK-1123 CRUD)

    @ViewBuilder
    private func layerSection(_ sheet: Sheet) -> some View {
        // Section header with Add Layer button
        HStack(spacing: 4) {
            Text("LAYERS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                _ = session.addLayer(named: "Layer \(session.layerCount + 1)")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Add Layer")
        }
        .padding(.horizontal, CGFloat(12 + 16))
        .padding(.vertical, 4)

        ForEach(Array(sheet.layers.enumerated()), id: \.element.id) { index, layer in
            layerRow(layer, index: index, count: sheet.layers.count)
        }
    }

    private func layerRow(_ layer: Layer, index: Int, count: Int) -> some View {
        let id = "layer_\(layer.id.uuidString)"
        return HStack(spacing: 4) {
            // Visibility toggle (eye)
            Button {
                session.setLayerVisible(id: layer.id, isVisible: !layer.isVisible)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(layer.isVisible ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Hide layer" : "Show layer")

            // Lock toggle
            Button {
                session.setLayerLocked(id: layer.id, isLocked: !layer.isLocked)
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10))
                    .foregroundStyle(layer.isLocked ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(layer.isLocked ? "Unlock layer" : "Lock layer")

            if editingLayerID == layer.id {
                TextField("Layer name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($renameFocused)
                    .onSubmit { commitRename(layer.id) }
                    .onExitCommand { editingLayerID = nil }
            } else {
                Text(layer.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { beginRename(layer) }
            }

            Spacer(minLength: 2)

            Text("\(layer.vectors.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Reorder up
            Button {
                session.moveLayerUp(id: layer.id)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("Move layer up")

            // Reorder down
            Button {
                session.moveLayerDown(id: layer.id)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .disabled(index == count - 1)
            .help("Move layer down")
        }
        .padding(.horizontal, CGFloat(12 + 16))
        .padding(.vertical, 3)
        .background(selectedItemID == id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItemID = selectedItemID == id ? nil : id
            session.selection = .layer(layer.id)
        }
        .contextMenu {
            Button("Rename…") { beginRename(layer) }
            Divider()
            Button("Delete Layer", role: .destructive) {
                _ = session.removeLayer(id: layer.id)
            }
        }
    }

    private func beginRename(_ layer: Layer) {
        renameDraft = layer.name
        editingLayerID = layer.id
        renameFocused = true
    }

    private func commitRename(_ id: UUID) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            session.renameLayer(id: id, to: trimmed)
        }
        editingLayerID = nil
    }

    private func treeItem(
        id: String,
        title: String,
        icon: String,
        isExpanded: Bool,
        selectedItemID: Binding<String?>,
        indentLevel: Int = 0
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, CGFloat(12 + indentLevel * 16))
        .padding(.vertical, 4)
        .background(selectedItemID.wrappedValue == id ? Color.accentColor.opacity(0.15) : Color.clear)
        .onTapGesture {
            selectedItemID.wrappedValue = selectedItemID.wrappedValue == id ? nil : id
        }
    }
}

// MARK: - Right Panel (Properties Inspector)

/// Right panel showing properties for the currently selected item.
struct RightPanelView: View {
    let selectedItemType: SelectionType
    
    enum SelectionType {
        case none
        case job(name: String, sheetCount: Int, layerCount: Int)
        case sheet(index: Int, width: Double, depth: Double, height: Double)
        case layer(index: Int, name: String, isVisible: Bool)
    }
    
    @State private var layerVisible = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROPERTIES")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch selectedItemType {
                    case .none:
                        Text("Select an item to view its properties.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                    
                    case let .job(name, sheetCount, layerCount):
                        propertySection(title: "Job") {
                            PropertyRow(label: "Name", value: name.isEmpty ? "Untitled" : name)
                            PropertyRow(label: "Sheets", value: "\(sheetCount)")
                            PropertyRow(label: "Layers", value: "\(layerCount)")
                        }
                    
                    case let .sheet(index, width, depth, height):
                        propertySection(title: "Sheet \(index + 1)") {
                            PropertyRow(label: "Width", value: String(format: "%.2f mm", width))
                            PropertyRow(label: "Depth", value: String(format: "%.2f mm", depth))
                            PropertyRow(label: "Height", value: String(format: "%.2f mm", height))
                        }
                    
                    case let .layer(index, name, isVisible):
                        propertySection(title: "Layer \(index + 1)") {
                            PropertyRow(label: "Name", value: name)
                            
                            Toggle("Visible", isOn: Binding(
                                get: { isVisible },
                                set: { _ in /* Would update layer state */ }
                            ))
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }
    
    private func propertySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            
            Divider()
            
            content()
        }
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
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Preview (only in debug builds with SwiftUI available)

#if canImport(SwiftUI) && DEBUG
struct BrowserPanels_Previews: PreviewProvider {
    static var previews: some View {
        LeftPanelView(session: AppSession())
            .frame(width: 240)
    }
}
#endif
