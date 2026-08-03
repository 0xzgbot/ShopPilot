import SwiftUI
import ShopPilotCore

// MARK: - Tool Picker Menu

/// SPK-1131 — tool database picker attached to toolpath operation nodes.
///
/// A compact `Menu` that lists the session tool database (filtered to the
/// tool types the Cut stage supports — end mill + V-bit) plus a "No tool"
/// clear option. The label shows the currently assigned tool; picking one
/// routes through `onSelect(toolID?)` so the owning session can mark the
/// node dirty and persist the assignment.
struct ToolPickerMenu: View {
    /// The assigned tool id (nil = no tool yet).
    let selectedToolID: UUID?

    /// Tools to offer, already filtered to supported types.
    let tools: [Tool]

    /// Called with the picked tool id, or nil for "No tool".
    let onSelect: (UUID?) -> Void

    /// When true, render as a bare icon button (tree rows) instead of a
    /// labeled pill (detail pane).
    var compact = false

    var body: some View {
        Menu {
            Button(action: { onSelect(nil) }) {
                Label("No tool", systemImage: "slash.circle")
            }
            if !tools.isEmpty {
                Divider()
                ForEach(tools) { tool in
                    Button(action: { onSelect(tool.id) }) {
                        if tool.id == selectedToolID {
                            Label(toolMenuTitle(tool), systemImage: "checkmark")
                        } else {
                            Text(toolMenuTitle(tool))
                        }
                    }
                }
            }
        } label: {
            if compact {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(selectedToolID == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 14, height: 14)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 11))
                    Text(labelText)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(selectedToolID == nil ? Color.secondary : Color.primary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose a tool for this toolpath")
    }

    private var selectedTool: Tool? {
        guard let selectedToolID else { return nil }
        return tools.first { $0.id == selectedToolID }
    }

    private var iconName: String {
        guard let selectedTool else { return "wrench.and.screwdriver" }
        switch selectedTool.type {
        case .endMill: return "circle.fill"
        case .vBit: return "triangle.fill"
        default: return "wrench.and.screwdriver"
        }
    }

    private var labelText: String {
        guard let selectedTool else { return "No tool" }
        return selectedTool.name
    }

    private func toolMenuTitle(_ tool: Tool) -> String {
        if tool.type == .vBit {
            return "\(tool.name) — \(String(format: "%.1f mm", tool.diameter)) V-Bit"
        }
        return "\(tool.name) — \(String(format: "%.1f mm", tool.diameter))"
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct ToolPickerMenu_Previews: PreviewProvider {
    static var previews: some View {
        let db = ToolDatabase()
        VStack(spacing: 12) {
            ToolPickerMenu(
                selectedToolID: db.tools.first?.id,
                tools: db.tools(ofTypes: [.endMill, .vBit]),
                onSelect: { _ in }
            )
            ToolPickerMenu(
                selectedToolID: nil,
                tools: db.tools(ofTypes: [.endMill, .vBit]),
                onSelect: { _ in },
                compact: true
            )
        }
        .padding()
    }
}
#endif
