import Foundation

// MARK: - Shortcut registry (SPK-1317)

/// User-assignable keyboard shortcuts. Each command has a stable id, a
/// default key + modifiers, and the user's override (persisted via Codable
/// to UserDefaults). The app's CommandGroup buttons read from this registry
/// instead of hardcoded `.keyboardShortcut` values, so power users can
/// remap without touching code.
public struct ShortcutBinding: Codable, Equatable, Identifiable, Sendable {
    public let id: String          // stable command id ("stage.cut", "file.new")
    public let title: String       // menu label
    public let defaultKey: String  // "n", "g", "1"…
    public let defaultModifiers: [String]  // ["command"], ["command", "shift"]
    public var key: String         // user override (falls back to default)
    public var modifiers: [String] // user override

    public init(id: String, title: String,
                defaultKey: String, defaultModifiers: [String],
                key: String? = nil, modifiers: [String]? = nil) {
        self.id = id
        self.title = title
        self.defaultKey = defaultKey
        self.defaultModifiers = defaultModifiers
        self.key = key ?? defaultKey
        self.modifiers = modifiers ?? defaultModifiers
    }

    /// True when the user hasn't remapped this command.
    public var isDefault: Bool {
        key == defaultKey && modifiers == defaultModifiers
    }

    /// Reset to the shipped default.
    public mutating func reset() {
        key = defaultKey
        modifiers = defaultModifiers
    }
}

/// The app's shortcut catalog + persistence. Observable so a Preferences
/// pane can live-edit and the menus re-render.
public final class ShortcutRegistry: ObservableObject, @unchecked Sendable {

    /// Process-wide instance the menu bar + Preferences pane share, so a
    /// remap in Preferences live-updates the CommandGroup buttons. (The
    /// command palette's own shortcuts keep using ShortcutStore — this
    /// registry owns the MENU BAR bindings.)
    public static let shared = ShortcutRegistry()

    @Published public private(set) var bindings: [ShortcutBinding]

    /// The catalog of remappable commands.
    public static let catalog: [ShortcutBinding] = [
        ShortcutBinding(id: "file.new", title: "New Job", defaultKey: "n", defaultModifiers: ["command"]),
        ShortcutBinding(id: "palette", title: "Command Palette…", defaultKey: "k", defaultModifiers: ["command"]),
        ShortcutBinding(id: "edit.group", title: "Group", defaultKey: "g", defaultModifiers: ["command"]),
        ShortcutBinding(id: "edit.ungroup", title: "Ungroup", defaultKey: "g", defaultModifiers: ["command", "shift"]),
        ShortcutBinding(id: "prefs", title: "Preferences…", defaultKey: ",", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.setup", title: "Setup", defaultKey: "1", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.design", title: "Design", defaultKey: "2", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.model", title: "Model", defaultKey: "3", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.cut", title: "Cut", defaultKey: "4", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.preview", title: "Preview", defaultKey: "5", defaultModifiers: ["command"]),
        ShortcutBinding(id: "stage.machine", title: "Machine", defaultKey: "6", defaultModifiers: ["command"]),
    ]

    private static let defaultsKey = "spk.shortcutRegistry.v1"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Restore overrides on top of the catalog (unknown ids are dropped,
        // missing ids keep defaults).
        if let data = userDefaults.data(forKey: ShortcutRegistry.defaultsKey),
           let saved = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            self.bindings = ShortcutRegistry.catalog.map { original in
                saved[original.id] ?? original
            }
        } else {
            self.bindings = ShortcutRegistry.catalog
        }
    }

    /// The current binding for a command id (nil = unknown id).
    public func binding(for id: String) -> ShortcutBinding? {
        bindings.first { $0.id == id }
    }

    /// Set a user override. Returns false when the command id is unknown or
    /// the key is empty. Persists immediately.
    @discardableResult
    public func setOverride(id: String, key: String, modifiers: [String]) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }),
              !key.isEmpty else { return false }
        bindings[index].key = key
        bindings[index].modifiers = modifiers
        persist()
        return true
    }

    /// Reset one command to its default.
    public func reset(_ id: String) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].reset()
        persist()
    }

    /// Reset every command to defaults.
    public func resetAll() {
        for index in bindings.indices {
            bindings[index].reset()
        }
        persist()
    }

    private func persist() {
        var map: [String: ShortcutBinding] = [:]
        for binding in bindings where !binding.isDefault {
            map[binding.id] = binding
        }
        if let data = try? JSONEncoder().encode(map) {
            userDefaults.set(data, forKey: ShortcutRegistry.defaultsKey)
        }
    }
}
