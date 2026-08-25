import SwiftUI
import ShopPilotCore

// MARK: - Cut-Layers table (SPK-1201)

/// The LightBurn-style cut overview: a sortable grid over every operation —
/// status | # | name | strategy | tool | feed | depth | time — with inline
/// feed editing, per-row tool assignment, and the Recalc-All affordance.
/// This is the PRIMARY cut overview; the tree remains for grouping/params.
struct CutLayersTableView: View {
    @ObservedObject var session: AppSession

    enum SortKey: String, CaseIterable, Identifiable {
        case order, name, strategy, feed, depth, time
        var id: String { rawValue }
    }

    @State private var sortKey: SortKey = .order
    @State private var sortAscending = true
    @State private var editingFeedID: UUID?
    /// SPK-1210 — the row being hovered; its op's G-code segments highlight
    /// on the Preview canvas (session drives the preview, so we publish here).
    @State private var hoveredRowID: UUID?

    private var rows: [CutLayerRow] {
        let built = session.cutLayerRows
        guard sortKey != .order else { return built } // tree order is the default
        let sorted: [CutLayerRow]
        switch sortKey {
        case .order: sorted = built
        case .name: sorted = built.sorted { $0.name < $1.name }
        case .strategy: sorted = built.sorted { $0.strategy < $1.strategy }
        case .feed: sorted = built.sorted { ($0.feedRate ?? 0) < ($1.feedRate ?? 0) }
        case .depth: sorted = built.sorted { ($0.cutDepth ?? 0) < ($1.cutDepth ?? 0) }
        case .time: sorted = built.sorted { $0.estimatedTime < $1.estimatedTime }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                table
            }
            Divider()
            footer
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tablecells")
                .foregroundStyle(Color.accentColor)
            Text("CUT LAYERS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(rows.count) op(s)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $sortKey) {
                Text("Order").tag(SortKey.order)
                Text("Name").tag(SortKey.name)
                Text("Type").tag(SortKey.strategy)
                Text("Feed").tag(SortKey.feed)
                Text("Depth").tag(SortKey.depth)
                Text("Time").tag(SortKey.time)
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
            .frame(width: 90)
            .help("Sort the cut layers (default: tree order)")
            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.plain)
            .controlSize(.mini)
            .help(sortAscending ? "Ascending" : "Descending")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tablecells")
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
        .padding(.vertical, 24)
        .padding(.horizontal, 10)
    }

    private var table: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func rowView(_ row: CutLayerRow) -> some View {
        // SPK-2022e — per-op send-enable state drives both the checkbox and
        // the row dimming.
        let enabled = session.toolpathTree.findNode(id: row.id)?.isEnabled ?? true
        return HStack(spacing: 6) {
            // SPK-2022e — enable checkbox: unchecked ops are excluded from
            // the program sent to the Machine stage / queue.
            Toggle("Enable \(row.name)", isOn: Binding(
                get: { session.toolpathTree.findNode(id: row.id)?.isEnabled ?? true },
                set: { session.setToolpathEnabled($0, nodeID: row.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Enable \(row.name)")
            .controlSize(.mini)
            .help(enabled ? "Enabled — included in Send. Uncheck to exclude “\(row.name)”"
                          : "Disabled — excluded from Send. Check to include “\(row.name)”")
            .frame(width: 16)

            // Status dot (SPK-1207).
            statusDot(row.status)
                .frame(width: 8)
            // Order / sort badge.
            Text("\(row.order + 1)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            // Name + strategy (dimmed while the op is send-disabled).
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(row.strategy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Feed — inline edit on the four core strategies.
            if let feed = row.feedRate {
                if editingFeedID == row.id {
                    TextField("", value: Binding(
                        get: { feed },
                        set: { newValue in
                            _ = session.setToolpathFeedRate(newValue, nodeID: row.id)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .frame(width: 56)
                    .onSubmit { editingFeedID = nil }
                } else {
                    Text("\(Int(feed))")
                        .font(.caption.monospaced())
                        .frame(width: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                        .onTapGesture { editingFeedID = row.id }
                        .help("Click to edit feed (mm/min)")
                }
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
            }

            // Depth.
            if let depth = row.cutDepth {
                Text(String(format: "%.1f", depth))
                    .font(.caption.monospaced())
                    .frame(width: 40, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Time.
            Text(CutLayersTableView.timeString(row.estimatedTime))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(session.selectedToolpathID == row.id
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { session.selectToolpath(row.id) }
        .onHover { hovering in
            // SPK-1210 — publish the hovered op to the session so the
            // Preview canvas can highlight exactly its segments.
            hoveredRowID = hovering ? row.id : nil
            session.hoveredToolpathID = hovering ? row.id : nil
        }
        .contextMenu {
            // SPK-1204 — same registry as the tree rows.
            if let action = CommandRegistryAction.action(id: "tp.recalc"),
               action.isEnabled(.toolpathNode(id: row.id, isDirty: row.status == .stale, toolID: nil)) {
                Button { _ = session.recalculateToolpath(id: row.id) } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
            if let action = CommandRegistryAction.action(id: "tp.duplicate") {
                Button { _ = session.duplicateToolpath(id: row.id) } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
            Divider()
            if let action = CommandRegistryAction.action(id: "tp.delete") {
                Button(role: .destructive) { _ = session.deleteToolpath(id: row.id) } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
    }

    private func statusDot(_ status: ToolpathStatus) -> some View {
        let color: Color
        switch status {
        case .pending: color = .gray
        case .current: color = .green
        case .stale: color = .orange
        case .error: color = .red
        }
        return Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(color)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            let attention = CutLayerTableBuilder.attentionCount(rows)
            if attention > 0 {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.orange)
                Text("\(attention) op(s) need recalc")
            } else {
                Text("All toolpaths up to date")
            }
            Spacer()
            // SPK-1314 — spinner while the background recalc runs.
            if session.isRecalculating {
                ProgressView()
                    .controlSize(.mini)
                    .help("Recalculating toolpaths…")
            }
            if attention > 0 {
                Button("Recalc All") {
                    _ = session.recalculateDirtyToolpathsAsync()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Text("Total ~\(CutLayersTableView.timeString(CutLayerTableBuilder.totalTime(rows)))")
                .fontWeight(.medium)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    static func timeString(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        return String(format: "%.1fm", seconds / 60)
    }
}

// MARK: - Row registry accessor (shared with the tree — SPK-1204)

/// Same file-private registry the tree rows use, so the table's context
/// menu and the tree's can never drift.
private enum CommandRegistryAction {
    static let registry = AppCommandRegistry.make()

    static func action(id: String) -> CommandAction? {
        registry.action(id: id)
    }
}
