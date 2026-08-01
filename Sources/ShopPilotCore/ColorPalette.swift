import SwiftUI

/// Convenience initialiser from a hex string (e.g. `"1E88E5"` or `"#1E88E5"`).
extension Color {
    /// Creates a colour from a 6-digit hex string (e.g. `"1E88E5"`).
    ///
    /// The leading `#` is optional and will be ignored if present.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789ABCDEFabcdef").inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a = Double((int >> 24) & 0xFF) / 255.0
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// App-wide colour constants for ShopPilot.
struct ColorPalette {

    // MARK: - Core

    /// Accent colour — blue-600.
    static let primary = Color(hex: "1E88E5")

    /// Secondary UI colour — gray-500.
    static let secondary = Color(hex: "9E9E9E")

    /// Success / confirmation — green-500.
    static let success = Color(hex: "4CAF50")

    /// Warning / caution — yellow-500.
    static let warning = Color(hex: "FFC107")

    /// Error / danger — red-500.
    static let error = Color(hex: "F44336")

    // MARK: - Surfaces

    /// System background colour.
    static let background = Color(NSColor.controlBackgroundColor)

    /// Card / surface background.
    static let surface = Color(NSColor.underPageBackgroundColor)

    // MARK: - Text

    /// Primary text colour (near-black).
    static let textPrimary = Color(NSColor.labelColor)

    /// Secondary / muted text colour.
    static let textSecondary = Color(NSColor.secondaryLabelColor)

    // MARK: - Borders

    /// Border / divider colour.
    static let border = Color(NSColor.separatorColor)
}
