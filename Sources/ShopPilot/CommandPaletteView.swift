import SwiftUI

// MARK: - Command Palette View

/// ⌘K command palette overlay — shows all available commands grouped by category.
struct CommandPaletteView: View {
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    
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
            return CommandRegistry.flatCommands
        }
        return CommandRegistry.search(searchText)
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
        .frame(width: 520, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isFocused = true
            selectedIndex = min(selectedIndex, flatFiltered.count - 1)
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }
    
    // MARK: - Subviews
    
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search commands…", text: $searchText)
                .textFieldStyle(.plain)
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
                            Text(group.category.rawValue.uppercased())
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            
                            // Commands in this category — use rawValue as ID since CommandID isn't Identifiable
                            ForEach(group.items.map { ($0.category.rawValue + "_" + $0.command.rawValue, $0) }, id: \.0) { _, item in
                                commandRow(item.command, isHighlighted: selectedIndex == globalIndex(for: item))
                                    .onHover { hovering in
                                        if hovering {
                                            selectedIndex = globalIndex(for: item)
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
                
                // Keyboard shortcut hint
                if let shortcut = cmd.keyboardShortcut {
                    Text(shortcut.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.separatorColor))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
            .background(isHighlighted ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
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
