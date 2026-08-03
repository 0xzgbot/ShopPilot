import SwiftUI
import ShopPilotCore

// MARK: - Toolpath Tree View

/// SPK-1132 — Toolpath tree UI (list, select, dirty badge, delete).
///
/// Renders the session's `ToolpathTreeManager` recursively: operations and
/// groups with expand/collapse, selection mirrored into
/// `AppSession.selectedToolpathID` / `.toolpath` selection, an orange dirty
/// badge on nodes awaiting recalculation, and per-row delete (hover trash +
/// context menu) routed through `AppSession.deleteToolpath`.
struct ToolpathTreeView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if session.toolpaths.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.toolpathTree.root.children) { node in
                            nodeRow(node, indent: 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            footer
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25))
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "scissors")
                .foregroundStyle(Color.accentColor)
            Text("TOOLPATHS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(operationCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "scissors")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No toolpaths yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Generate a toolpath from the Cut toolbar to see it here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if dirtyOperationCount > 0 {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.orange)
                Text("\(dirtyOperationCount) operation(s) need recalculation")
            } else {
                Text("All toolpaths up to date")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recursive rows

    @ViewBuilder
    private func nodeRow(_ node: ToolpathTreeNode, indent: Int) -> some View {
        ToolpathRow(
            node: node,
            indent: indent,
            isSelected: session.selectedToolpathID == node.id,
            onSelect: { session.selectToolpath(node.id) },
            onToggle: { node.isExpanded.toggle() },
            onDelete: { session.deleteToolpath(id: node.id) },
            pickerTools: session.toolDatabase.tools(ofTypes: [.endMill, .vBit]),
            onAssignTool: { toolID in
                session.assignTool(toolID, toToolpath: node.id)
            }
        )

        if case .group = node.type, node.isExpanded {
            ForEach(node.children) { child in
                // AnyView breaks the opaque-type recursion for nested levels.
                AnyView(nodeRow(child, indent: indent + 1))
            }
        }
    }

    // MARK: - Derived counts

    /// Number of operation nodes in the tree (excludes groups and root).
    private var operationCount: Int {
        var count = 0
        func walk(_ node: ToolpathTreeNode) {
            if case .operation = node.type { count += 1 }
            node.children.forEach(walk)
        }
        walk(session.toolpathTree.root)
        return count
    }

    /// Number of operation nodes flagged dirty (groups inherit via cascade,
    /// so only operations are counted for the summary).
    private var dirtyOperationCount: Int {
        var count = 0
        func walk(_ node: ToolpathTreeNode) {
            if node.isDirty, case .operation = node.type { count += 1 }
            node.children.forEach(walk)
        }
        walk(session.toolpathTree.root)
        return count
    }
}

// MARK: - Row

/// Single tree row: icon, name, tool picker, dirty badge, time, hover delete.
private struct ToolpathRow: View {
    let node: ToolpathTreeNode
    let indent: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    /// Tools offered by the picker (already filtered to supported types).
    let pickerTools: [Tool]
    let onAssignTool: (UUID?) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if case .group = node.type {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)
            } else {
                Color.clear
                    .frame(width: 10, height: 10)
            }

            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            if case .operation = node.type {
                ToolPickerMenu(
                    selectedToolID: node.toolID,
                    tools: pickerTools,
                    onSelect: onAssignTool,
                    compact: true
                )
            }

            if node.isDirty {
                dirtyBadge
            }

            if case .operation = node.type, node.estimatedTimeSeconds > 0 {
                Text(ToolpathRow.timeString(node.estimatedTimeSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete toolpath")
            }
        }
        .padding(.horizontal, CGFloat(8 + indent * 14))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var iconName: String {
        if case .group = node.type { return "folder" }
        return "scissors"
    }

    /// Compact dirty badge: orange dot + label pill.
    private var dirtyBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
            Text("dirty")
                .font(.system(size: 9))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(3)
        .help("Needs recalculation")
    }

    static func timeString(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct ToolpathTreeView_Previews: PreviewProvider {
    static var previews: some View {
        ToolpathTreeView(session: AppSession())
            .frame(width: 260, height: 320)
            .padding()
    }
}
#endif
