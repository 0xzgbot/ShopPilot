import Foundation

// MARK: - ShortcutStore (UI-polish cluster: customizable shortcuts)

/// UserDefaults-backed remapping of command shortcuts. Keyed by the command's
/// raw id (a stable string), value is the shortcut key (e.g. "n", "shift+z",
/// "delete"). The app layer seeds defaults from `CommandID.keyboardShortcut`
/// and overlays any user override here; the store itself is app-agnostic so a
/// CLT can prove persistence and precedence.
public enum ShortcutStore {
    private static let key = "shop_pilot_shortcut_overrides"

    /// Load the persisted overrides (command id → shortcut key).
    public static func overrides() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    /// Effective shortcut for a command: override when present, else default.
    public static func shortcut(for commandID: String, default defaultKey: String?) -> String? {
        if let override = overrides()[commandID] {
            return override.isEmpty ? nil : override
        }
        return defaultKey
    }

    /// Set (or clear with nil/empty) a user override.
    public static func setOverride(_ key: String?, for commandID: String) {
        var current = overrides()
        if let key, !key.isEmpty {
            current[commandID] = key
        } else {
            current.removeValue(forKey: commandID)
        }
        UserDefaults.standard.set(current, forKey: Self.key)
    }

    /// Remove every override (restore defaults).
    public static func resetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Normalize a typed shortcut string: trim whitespace, lower-case.
    public static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
