import SwiftUI
import ShopPilotCore

// MARK: - Tool Browser View

/// Left-panel tool browser showing all tools in the database with selection.
struct ToolBrowserView: View {
    @ObservedObject var database: ToolDatabase
    @Binding var selectedToolID: UUID?
    @State private var showingCutDataEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TOOLS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                // SPK-1133b — cut-data editor for the selected tool (per-material
                // + per-machine cutting data).
                Button {
                    showingCutDataEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(selectedToolID == nil)
                .help("Edit linked cut data (material + machine) for the selected tool")
                Text("\(database.tools.count) tool\(database.tools.count != 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                // SPK-1133: tools grouped by class (installer 13-class
                // taxonomy), empty classes hidden.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ToolType.allCases, id: \.self) { type in
                        let tools = database.tools.filter { $0.type == type }
                        if !tools.isEmpty {
                            Text(type.displayName.uppercased())
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            ForEach(tools) { tool in
                                ToolRowView(
                                    tool: tool,
                                    isSelected: selectedToolID == tool.id
                                )
                                .onTapGesture {
                                    selectedToolID = tool.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCutDataEditor) {
            if let tool = selectedToolID.flatMap({ database.tool(withID: $0) }) {
                ToolCutDataEditorView(database: database, tool: tool)
            }
        }
    }
}

// MARK: - Tool Row

private struct ToolRowView: View {
    let tool: Tool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Tool type icon
            Image(systemName: toolTypeIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(isSelected ? Color.blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                // Tool name
                Text(tool.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Tool specs
                Text(toolSpecsString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(Color.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
    
    private var toolTypeIcon: String {
        switch tool.type {
        case .endMill, .radiusedEndMill: return "circle.fill"
        case .vBit: return "triangle.fill"
        case .ballNose: return "circle.slash.fill"
        case .drill: return "pin.fill"
        case .slotCutter: return "rectangle.fill"
        case .engraving, .radiusedEngraving: return "pencil.tip"
        case .diamondDrag: return "sparkles"
        case .laser: return "bolt.fill"
        case .threadMill, .multiThreadMill: return "gearshape"
        case .plasma: return "flame.fill"
        case .form: return "square.dashed"
        }
    }

    private var toolSpecsString: String {
        var specs: String
        switch tool.type {
        case .endMill, .radiusedEndMill, .ballNose, .slotCutter, .engraving,
             .radiusedEngraving, .threadMill, .multiThreadMill, .plasma, .form:
            specs = String(format: "%.1f mm · %d flutes", tool.diameter, tool.flutes)
        case .vBit:
            specs = String(format: "%.1f mm V-Bit", tool.diameter)
        case .drill:
            specs = String(format: "%.1f mm drill", tool.diameter)
        case .diamondDrag:
            specs = String(format: "%.1f mm drag", tool.diameter)
        case .laser:
            specs = String(format: "%.1f mm laser", tool.diameter)
        }
        // SPK-1133b — show the linked cut-data surface (per-material entries +
        // per-machine entries) so the 3-part linkage is visible in the browser.
        if !tool.cutData.isEmpty || !tool.machineCutData.isEmpty {
            let materials = tool.cutData.count
            let machines = tool.machineCutData.count
            specs += " · \(materials) mat\(materials == 1 ? "" : "s")"
            if machines > 0 {
                specs += " · \(machines) mach\(machines == 1 ? "" : "s")"
            }
        }
        return specs
    }
}

// MARK: - Cut Data Editor (SPK-1133b)

/// Edits a tool's 3-part cut-data linkage: per-material cut data (feed /
/// plunge / spindle RPM / pass depth) and per-machine cut data. Saves back
/// through the database (UserDefaults JSON) so recalc resolves the linked
/// values.
struct ToolCutDataEditorView: View {
    @ObservedObject var database: ToolDatabase
    let tool: Tool
    @Environment(\.dismiss) private var dismiss

    @State private var materialEntries: [ToolCutData]
    @State private var machineEntries: [MachineCutData]

    init(database: ToolDatabase, tool: Tool) {
        self.database = database
        self.tool = tool
        _materialEntries = State(initialValue: tool.cutData)
        _machineEntries = State(initialValue: tool.machineCutData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cut Data — \(tool.name)")
                .font(.headline)

            // Per-material cutting data.
            GroupBox("Per Material") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($materialEntries, id: \.self) { $entry in
                        HStack(spacing: 6) {
                            TextField("Material", text: $entry.material)
                                .frame(width: 90)
                            TextField("Feed", value: $entry.feedRateMmPerMin, format: .number)
                                .frame(width: 60)
                            TextField("Plunge", value: $entry.plungeRateMmPerMin, format: .number)
                                .frame(width: 60)
                            TextField("RPM", value: $entry.spindleRpm, format: .number)
                                .frame(width: 60)
                            TextField("Depth", value: $entry.maxDepthOfCutMm, format: .number)
                                .frame(width: 50)
                            Button {
                                materialEntries.removeAll { $0 == entry }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    }
                    HStack {
                        Button("Add Material") {
                            materialEntries.append(
                                ToolCutData(material: "hardwood", feedRateMmPerMin: 1000, plungeRateMmPerMin: 300, spindleRpm: 12000, maxDepthOfCutMm: 2.0)
                            )
                        }
                        Spacer()
                    }
                }
            }

            // Per-machine cutting data.
            GroupBox("Per Machine") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach($machineEntries, id: \.self) { $entry in
                        HStack(spacing: 6) {
                            TextField("Machine", text: $entry.machineName)
                                .frame(width: 90)
                            TextField("Feed", value: $entry.feedRateMmPerMin, format: .number)
                                .frame(width: 60)
                            TextField("Plunge", value: $entry.plungeRateMmPerMin, format: .number)
                                .frame(width: 60)
                            TextField("RPM", value: $entry.spindleRpm, format: .number)
                                .frame(width: 60)
                            TextField("Depth", value: $entry.maxDepthOfCutMm, format: .number)
                                .frame(width: 50)
                            Button {
                                machineEntries.removeAll { $0 == entry }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                    }
                    HStack {
                        Button("Add Machine") {
                            machineEntries.append(
                                MachineCutData(machineName: "GRBL 3018", feedRateMmPerMin: 800, plungeRateMmPerMin: 240, spindleRpm: 10000, maxDepthOfCutMm: 1.5)
                            )
                        }
                        Spacer()
                    }
                }
            }

            Text("Recalculate applies the resolved values (machine > material > derived) when an op still uses placeholder feed/rpm.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func save() {
        // Tool is a value type; rebuild with the new linked cut data.
        var updated = Tool(
            id: tool.id,
            name: tool.name,
            type: tool.type,
            diameter: tool.diameter,
            cuttingLength: tool.cuttingLength,
            totalLength: tool.totalLength,
            shankDiameter: tool.shankDiameter,
            flutes: tool.flutes,
            material: tool.material,
            cutData: materialEntries,
            machineCutData: machineEntries
        )
        updated.createdAt = tool.createdAt
        updated.updatedAt = Date()
        database.update(updated)
    }
}

// MARK: - Preview (only in debug builds with SwiftUI available)

#if canImport(SwiftUI) && DEBUG
struct ToolBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        let db = ToolDatabase()
        
        return ToolBrowserView(
            database: db,
            selectedToolID: .constant(nil)
        )
        .frame(width: 240)
    }
}
#endif
