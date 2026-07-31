import SwiftUI
import ShopPilotCore

// MARK: - Sheet List Row

/// A single row in the sheet list, showing name, dimensions, and material.
private struct SheetRowView: View {
    let sheet: Sheet
    let isSelected: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Sheet name
            Text(sheet.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Dimensions
            Text("\(Int(sheet.width)) × \(Int(sheet.depth)) × \(Int(sheet.height)) mm")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Material
            if let material = sheet.material {
                Text(material.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No material")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineLimit(1)
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove sheet")
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Sheet List View

/// A panel that lists all sheets in a job, with add/remove controls and selection.
public struct SheetListView: View {
    
    /// The current list of sheets.
    @Binding var sheets: [Sheet]
    
    /// The ID of the currently selected sheet.
    @Binding var selectedSheetId: UUID?
    
    /// Closure called when the user wants to add a new sheet.
    /// If nil, a default sheet is created; otherwise the caller handles creation.
    var onAddSheet: (() -> Sheet)? = nil
    
    public init(
        sheets: Binding<[Sheet]>,
        selectedSheetId: Binding<UUID?>,
        onAddSheet: (() -> Sheet)? = nil
    ) {
        self._sheets = sheets
        self._selectedSheetId = selectedSheetId
        self.onAddSheet = onAddSheet
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SHEETS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("(\(sheets.count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Sheet list
            if sheets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No sheets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add a sheet")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sheets) { sheet in
                            SheetRowView(
                                sheet: sheet,
                                isSelected: selectedSheetId == sheet.id,
                                onRemove: { removeSheet(id: sheet.id) }
                            )
                            .onTapGesture {
                                selectedSheetId = sheet.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Add button
            HStack {
                Button(action: addSheet) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Sheet")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
        }
        .alert("Remove Sheet", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let id = sheetToRemove {
                    _sheets.wrappedValue.removeAll { $0.id == id }
                    if selectedSheetId == id {
                        selectedSheetId = nil
                    }
                }
            }
        } message: {
            if let name = sheetToRemoveName {
                Text("Are you sure you want to remove \"\(name)\"?")
            }
        }
    }
    
    // MARK: - Actions
    
    private func addSheet() {
        if let factory = onAddSheet {
            let newSheet = factory()
            sheets.append(newSheet)
            selectedSheetId = newSheet.id
        } else {
            let newSheet = Job.makeDefaultSheet()
            sheets.append(newSheet)
            selectedSheetId = newSheet.id
        }
    }
    
    private func removeSheet(id: UUID) {
        let sheet = sheets.first { $0.id == id }
        sheetToRemove = id
        sheetToRemoveName = sheet?.name
        showingRemoveAlert = true
    }
    
    // MARK: - State
    
    @State private var showingRemoveAlert = false
    @State private var sheetToRemove: UUID? = nil
    @State private var sheetToRemoveName: String? = nil
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct SheetListView_Previews: PreviewProvider {
    static var previews: some View {
        @State var sheets = [
            Sheet(name: "Face 1", width: 600, depth: 400, height: 25),
            Sheet(name: "Face 2", width: 800, depth: 500, height: 30),
        ]
        @State var selectedId: UUID? = sheets[0].id
        
        return SheetListView(sheets: $sheets, selectedSheetId: $selectedId)
            .frame(width: 300, height: 400)
    }
}
#endif
