import Foundation

// MARK: - AppSettings (SPK-1602)

/// Shared app-settings resolution, in Core so the UI and any future CLT share
/// one source of truth. The raw stores (`@AppStorage("shop_pilot_theme")` in
/// PreferencesView) keep writing the string values; this type maps them to
/// SwiftUI color schemes.
public enum AppSettings {

    /// The theme string as stored by PreferencesView.
    public static let themeKey = "shop_pilot_theme"

    /// Resolved appearance — UI layers map this to their own color-scheme
    /// type (SwiftUI ColorScheme at the call site; Core stays UI-free).
    public enum Appearance: String {
        case light
        case dark
        case system
    }

    /// Resolve the stored theme string ("light" / "dark" / "system") to the
    /// Appearance enum. Unknown/absent → `.system` (follow the OS).
    public static func resolvedTheme(_ stored: String?) -> Appearance {
        switch stored {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    /// The units string as stored by PreferencesView ("mm" / "inch").
    public static let unitsKey = "shop_pilot_units"

    /// Whether the user's unit preference is inches (default: millimeters).
    public static func usesInches(_ stored: String?) -> Bool {
        stored == "inch"
    }
}
