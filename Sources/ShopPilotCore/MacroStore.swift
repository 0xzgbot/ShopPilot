import Foundation

// MARK: - Macro buttons (SPK-2022g)

/// One user-editable macro button on the machine dock: a display name plus an
/// ordered list of G-code lines. Sending happens ONLY on an explicit button
/// click through the same sender `touchOffZ` uses — never automatically
/// (Safety Req #9 / §2 non-negotiable: no auto-run on connect).
public struct MacroButton: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    /// Ordered G-code lines, sent top-to-bottom.
    public var lines: [String]

    public init(id: UUID = UUID(), name: String, lines: [String]) {
        self.id = id
        self.name = name
        self.lines = lines
    }
}

/// Persistence for macro buttons (UserDefaults JSON — same pattern as
/// `LastDeviceProfileStore` / `ToolDatabase`). Pure Foundation, no UI.
public enum MacroStore {

    public static let defaultsKey = "shop_pilot_macro_buttons_v1"

    /// Suggested starting set: park, bit change, wasteboard-surface prep.
    /// Every entry is motion-safe by itself and nothing here ever fires
    /// without a click.
    public static let suggestedDefaults: [MacroButton] = [
        MacroButton(
            name: "Park",
            lines: [
                "G91 G0 Z5",
                "G90 G0 X0 Y0",
                "G90"
            ]
        ),
        MacroButton(
            name: "Bit change",
            lines: [
                "M5",
                "G91 G0 Z10",
                "G90"
            ]
        ),
        MacroButton(
            name: "Surface prep",
            lines: [
                "M5",
                "G90 G0 Z2",
                "G90"
            ]
        )
    ]

    /// Load stored macros; fall back to the suggested defaults when nothing
    /// (or something undecodable) is stored.
    public static func load(defaults: UserDefaults = .standard) -> [MacroButton] {
        guard let data = defaults.data(forKey: defaultsKey),
              let macros = try? JSONDecoder().decode([MacroButton].self, from: data),
              !macros.isEmpty
        else {
            return suggestedDefaults
        }
        return macros
    }

    /// Persist macros back to UserDefaults.
    public static func save(_ macros: [MacroButton], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(macros) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Drop user edits and restore the suggested defaults (also persists).
    public static func resetToSuggestedDefaults(defaults: UserDefaults = .standard) -> [MacroButton] {
        save(suggestedDefaults, defaults: defaults)
        return suggestedDefaults
    }
}
