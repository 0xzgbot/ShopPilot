import SwiftUI

/// Persistent app settings backed by @AppStorage (UserDefaults).
struct AppSettings {

    // MARK: - Keys

    private enum Key {
        static let units       = "shop_pilot_units"         // "mm" or "inch"
        static let theme       = "shop_pilot_theme"          // "light", "dark", "system"
        static let proSkip     = "shop_pilot_pro_skip"       // skip beginner coach
    }

    // MARK: - Units (mm / inch)

    /// Preferred unit system. Defaults to `"mm"`.
    @AppStorage(Key.units) var units: String = "mm" {
        didSet { units = units == "inch" ? "inch" : "mm" }
    }

    /// Whether the user prefers inches (derived convenience).
    var isInches: Bool { units == "inch" }

    // MARK: - Theme (light / dark / system)

    /// Preferred appearance. Defaults to `"system"`.
    @AppStorage(Key.theme) var theme: String = "system" {
        didSet {
            guard ["light", "dark", "system"].contains(theme) else {
                theme = "system"
                return
            }
        }
    }

    /// The resolved `ColorScheme` for the current environment.
    func resolvedTheme(in env: EnvironmentValues) -> ColorScheme? {
        switch theme {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil // let system decide
        }
    }

    /// SPK-1602 — env-free resolver for the window root (no EnvironmentValues
    /// in a modifier chain): light → .light, dark → .dark, system/unknown →
    /// nil (follow the OS).
    var resolvedScheme: ColorScheme? {
        switch theme {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil
        }
    }

    // MARK: - Pro-skip (beginner coach)

    /// When `true`, the beginner coach is skipped on first run.
    @AppStorage(Key.proSkip) var proSkip: Bool = false
}
