import SwiftUI

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

/// Left browser panel showing document structure tree.
struct LeftPanelView: View {
    let jobName: String
    let sheetCount: Int
    let layerCount: Int
    
    @State private var selectedRow: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("DOCUMENT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Job root
                    treeItem(
                        id: "job",
                        title: jobName.isEmpty ? "Untitled" : jobName,
                        icon: "folder.fill",
                        isExpanded: true,
                        selectedRow: $selectedRow
                    )
                    
                    // Sheets group
                    if sheetCount > 0 {
                        treeItem(
                            id: "sheets",
                            title: "\(sheetCount) Sheet\(sheetCount > 1 ? "s" : "")",
                            icon: "doc.fill",
                            isExpanded: true,
                            selectedRow: $selectedRow
                        )
                        
                        // Sheet children (stub — real data from Job model)
                        ForEach(0..<min(sheetCount, 5), id: \.self) { idx in
                            treeItem(
                                id: "sheet_\(idx)",
                                title: "Sheet \(idx + 1)",
                                icon: "doc",
                                isExpanded: false,
                                selectedRow: $selectedRow,
                                indentLevel: 1
                            )
                        }
                    }
                    
                    // Layers group
                    if layerCount > 0 {
                        treeItem(
                            id: "layers",
                            title: "\(layerCount) Layer\(layerCount > 1 ? "s" : "")",
                            icon: "layers.fill",
                            isExpanded: true,
                            selectedRow: $selectedRow
                        )
                        
                        // Layer children (stub — real data from Sheet model)
                        ForEach(0..<min(layerCount, 5), id: \.self) { idx in
                            treeItem(
                                id: "layer_\(idx)",
                                title: "Layer \(idx + 1)",
                                icon: "layers",
                                isExpanded: false,
                                selectedRow: $selectedRow,
                                indentLevel: 1
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func treeItem(
        id: String,
        title: String,
        icon: String,
        isExpanded: Bool,
        selectedRow: Binding<String?>,
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
        .background(selectedRow.wrappedValue == id ? Color.accentColor.opacity(0.15) : Color.clear)
        .onTapGesture {
            selectedRow.wrappedValue = selectedRow.wrappedValue == id ? nil : id
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
        HSplitView {
            LeftPanelView(jobName: "My Project", sheetCount: 2, layerCount: 4)
                .frame(width: 240)
            
            Text("Canvas Area")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            RightPanelView(selectedItemType: .job(name: "My Project", sheetCount: 2, layerCount: 4))
                .frame(width: 280)
        }
    }
}
#endif
