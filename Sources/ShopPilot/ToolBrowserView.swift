import SwiftUI
import ShopPilotCore

// MARK: - Tool Browser View

/// Left-panel tool browser showing all tools in the database with selection.
struct ToolBrowserView: View {
    @ObservedObject var database: ToolDatabase
    @Binding var selectedToolID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TOOLS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(database.tools.count) tool\(database.tools.count != 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(database.tools) { tool in
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
        case .endMill: return "circle.fill"
        case .vBit: return "triangle.fill"
        case .ballNose: return "circle.slash.fill"
        case .drill: return "pin.fill"
        case .slotCutter: return "rectangle.fill"
        }
    }

    private var toolSpecsString: String {
        switch tool.type {
        case .endMill, .ballNose, .slotCutter:
            return String(format: "%.1f mm · %d flutes", tool.diameter, tool.flutes)
        case .vBit:
            return String(format: "%.1f mm V-Bit", tool.diameter)
        case .drill:
            return String(format: "%.1f mm drill", tool.diameter)
        }
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
