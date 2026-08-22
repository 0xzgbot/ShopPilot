import SwiftUI
import ShopPilotCore

// MARK: - Command Palette View

/// ⌘K command palette overlay — shows all available commands grouped by category.
struct CommandPaletteView: View {
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    /// SPK-1900c — Beginner mode filters pro import formats out of the list.
    @AppStorage("shop_pilot_beginner_mode") private var beginnerMode = false
    
    /// Currently selected index in the filtered list.
    @State private var selectedIndex = 0
    
    /// Whether the palette is open.
    @Binding var isOpen: Bool
    
    /// Callback when a command is selected.
    var onCommandSelected: (CommandID) -> Void
    
    // MARK: - Computed Properties
    
    /// Filtered and grouped commands based on search text.
    private var filteredCommands: [(category: CommandCategory, command: CommandID)] {
        if searchText.isEmpty {
            return CommandRegistry.flatCommands(beginnerMode: beginnerMode)
        }
        return CommandRegistry.search(searchText, beginnerMode: beginnerMode)
    }
    
    /// Flat list for indexing (used by keyboard navigation).
    private var flatFiltered: [CommandID] {
        filteredCommands.map(\.command)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField
            
            Divider()
            
            // Command list grouped by category
            commandList
            
            // Footer with selection info
            footer
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SP.Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SP.Radius.overlay, style: .continuous)
                .strokeBorder(.separator.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        // The footer promises ↑↓ / ↵ / ⎋, so wire them up. Zero-sized buttons
        // are used rather than `onKeyPress` because the search field holds
        // focus and would otherwise eat the arrow keys as cursor movement.
        .background { keyboardShortcuts }
        .onAppear {
            isFocused = true
            selectedIndex = min(max(selectedIndex, 0), max(flatFiltered.count - 1, 0))
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Keyboard navigation

    private var keyboardShortcuts: some View {
        VStack(spacing: 0) {
            Button("") { moveSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { moveSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { activateSelection() }
                .keyboardShortcut(.return, modifiers: [])
            Button("") { isOpen = false }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Move the highlight, stopping at the ends rather than wrapping.
    private func moveSelection(by delta: Int) {
        let count = flatFiltered.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    /// Run whatever is highlighted.
    private func activateSelection() {
        guard flatFiltered.indices.contains(selectedIndex) else { return }
        onCommandSelected(flatFiltered[selectedIndex])
        isOpen = false
    }
    
    // MARK: - Subviews
    
    private var searchField: some View {
        HStack(spacing: SP.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
            
            TextField("Search commands…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
    
    private var commandList: some View {
        ScrollViewReader { proxy in
            scrollableCommandList
                .onChange(of: selectedIndex) { _, index in
                    withAnimation(SP.Motion.state) { proxy.scrollTo(index, anchor: .center) }
                }
        }
    }

    private var scrollableCommandList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredCommands.isEmpty {
                    noResults
                } else {
                    // Build grouped display with explicit category ordering
                    ForEach(
                        CommandCategory.allCases.compactMap { cat -> (category: CommandCategory, items: [(category: CommandCategory, command: CommandID)])? in
                            let items = filteredCommands.filter { $0.category == cat }
                            return !items.isEmpty ? (cat, items) : nil
                        },
                        id: \.category.self
                    ) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            // Category header
                            SectionLabel(group.category.rawValue)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            
                            // Commands in this category — use rawValue as ID since CommandID isn't Identifiable
                            ForEach(group.items.map { ($0.category.rawValue + "_" + $0.command.rawValue, $0) }, id: \.0) { _, item in
                                let index = globalIndex(for: item)
                                commandRow(item.command, isHighlighted: selectedIndex == index)
                                    .id(index)
                                    .onHover { hovering in
                                        if hovering {
                                            selectedIndex = index
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
    private func commandRow(_ cmd: CommandID, isHighlighted: Bool) -> some View {
        Button(action: {
            onCommandSelected(cmd)
            isOpen = false
        }) {
            HStack(spacing: 12) {
                // Command name
                Text(cmd.name)
                    .font(.system(size: 13))
                
                Spacer()
                
                // Keyboard shortcut hint (UI-polish cluster: honors user
                // overrides from Preferences → Keyboard Shortcuts).
                if let shortcut = ShortcutStore.shortcut(for: cmd.rawValue, default: cmd.keyboardShortcut) {
                    Text(shortcut.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary.opacity(0.6))
                        )
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
        }
        .buttonStyle(CommandRowStyle(isHighlighted: isHighlighted))
    }
    
    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("No commands found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
    
    private var footer: some View {
        HStack(spacing: 16) {
            Text("\(filteredCommands.count) command\(filteredCommands.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Keyboard shortcuts help
            HStack(spacing: 8) {
                Label("↑↓ Navigate", systemImage: "arrow.up.arrow.down")
                Label("↵ Select", systemImage: "return")
                Label("⎋ Close", systemImage: "escape")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Helpers
    
    /// Convert a (category, command) pair to its global index in the filtered list.
    private func globalIndex(for item: (category: CommandCategory, command: CommandID)) -> Int {
        var count = 0
        for cat in CommandCategory.allCases {
            let itemsInCat = filteredCommands.filter { $0.category == cat }
            if itemsInCat.contains(where: { $0.command == item.command }) {
                return count + itemsInCat.firstIndex(where: { $0.command == item.command })!
            }
            count += itemsInCat.count
        }
        return 0
    }
}

// MARK: - Command Row Style

struct CommandRowStyle: ButtonStyle {
    var isHighlighted: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .padding(.horizontal, SP.Space.s)
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct CommandPaletteView_Previews: PreviewProvider {
    static var previews: some View {
        CommandPaletteView(isOpen: .constant(true), onCommandSelected: { _ in })
            .preferredColorScheme(.dark)
    }
}
#endif
