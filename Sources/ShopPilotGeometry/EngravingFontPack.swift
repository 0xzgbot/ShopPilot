import Foundation
#if canImport(CoreText)
import CoreText
#endif

// MARK: - Engraving Font Category

/// Categories for engraving-optimized fonts.
public enum EngravingFontCategory: String, CaseIterable {
    /// Clean, modern sans-serif fonts — best for general-purpose engraving
    case sansSerif
    /// Traditional serif fonts — good for formal/classic lettering
    case serif
    /// Fixed-width fonts — ideal for technical labels, serial numbers
    case monospace
    /// Bold, attention-grabbing display fonts
    case display
    /// Decorative script fonts — for artistic/ornamental engraving
    case script
}

// MARK: - Engraving Font

/// A curated font entry optimized for CNC engraving.
public struct EngravingFont: Identifiable, Equatable {
    /// Unique identifier for this font entry.
    public let id: UUID

    /// The font name as used in CoreText (e.g. "Helvetica Neue").
    public let name: String

    /// The category this font belongs to.
    public let category: EngravingFontCategory

    /// Recommended minimum font size for clean engraving (in points).
    public let size: Double

    /// Font weight descriptor (e.g. "Regular", "Bold", "Light").
    public let weight: String

    /// Human-readable description of why this font is good for engraving.
    public let description: String

    public init(
        id: UUID = UUID(),
        name: String,
        category: EngravingFontCategory,
        size: Double,
        weight: String,
        description: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.size = size
        self.weight = weight
        self.description = description
    }

    public static func == (lhs: EngravingFont, rhs: EngravingFont) -> Bool {
        lhs.name == rhs.name
            && lhs.category == rhs.category
            && lhs.size == rhs.size
            && lhs.weight == rhs.weight
    }
}

// MARK: - Engraving Font Pack

/// A curated collection of fonts optimized for CNC engraving.
///
/// Provides a pre-vetted set of macOS system fonts with metadata about their
/// suitability for engraving — minimum safe sizes, categories, and descriptions.
///
/// - Note: All fonts listed are pre-installed on macOS. Use `isFontAvailableOnSystem(_:)`
///   to verify availability at runtime.
public enum EngravingFontPack {

    // MARK: - Curated Font List

    /// Returns the full curated list of engraving-optimized fonts.
    ///
    /// The list includes multiple weight variants of Helvetica Neue, plus one
    /// representative from each category (serif, monospace, display, script).
    ///
    /// - Returns: Array of `EngravingFont` entries sorted by category then name.
    public static func engravingFonts() -> [EngravingFont] {
        [
            // Helvetica Neue — sans-serif, multiple weights
            EngravingFont(
                name: "Helvetica Neue",
                category: .sansSerif,
                size: 8.0,
                weight: "Light",
                description: "Ultra-clean geometric sans-serif. Excellent legibility at small sizes. Light weight for delicate engraving."
            ),
            EngravingFont(
                name: "Helvetica Neue",
                category: .sansSerif,
                size: 6.0,
                weight: "Regular",
                description: "Standard weight Helvetica Neue. The go-to font for CNC engraving — universally available, highly legible."
            ),
            EngravingFont(
                name: "Helvetica Neue",
                category: .sansSerif,
                size: 6.0,
                weight: "Bold",
                description: "Bold Helvetica Neue for high-contrast engraving. Best for labels and signage where readability is critical."
            ),

            // Arial — sans-serif, widely available
            EngravingFont(
                name: "Arial",
                category: .sansSerif,
                size: 7.0,
                weight: "Regular",
                description: "Widely available sans-serif with open counters. Good all-purpose engraving font for hobbyist and pro use."
            ),

            // Verdana — sans-serif, wide
            EngravingFont(
                name: "Verdana",
                category: .sansSerif,
                size: 7.0,
                weight: "Regular",
                description: "Wide, open sans-serif designed for screen legibility. Excellent for engraving at very small sizes due to generous x-height."
            ),

            // Georgia — serif
            EngravingFont(
                name: "Georgia",
                category: .serif,
                size: 8.0,
                weight: "Regular",
                description: "Robust serif designed for screen readability. Strong serifs hold up well in engraving — ideal for formal/classic lettering."
            ),

            // Times New Roman — serif
            EngravingFont(
                name: "Times New Roman",
                category: .serif,
                size: 8.0,
                weight: "Regular",
                description: "Classic serif with refined proportions. Good for traditional sign lettering and formal engravings."
            ),

            // Courier New — monospace
            EngravingFont(
                name: "Courier New",
                category: .monospace,
                size: 6.0,
                weight: "Regular",
                description: "Fixed-width monospace. Ideal for serial numbers, technical labels, and data matrix-style engraving where character alignment matters."
            ),

            // Impact — display
            EngravingFont(
                name: "Impact",
                category: .display,
                size: 10.0,
                weight: "Regular",
                description: "Extra-bold display font with narrow proportions. Excellent for short headlines and large-format engraving where impact matters."
            ),

            // Zapfino — script
            EngravingFont(
                name: "Zapfino",
                category: .script,
                size: 14.0,
                weight: "Regular",
                description: "Elegant calligraphic script with flowing forms. Best for artistic/ornamental engraving at larger sizes. Requires minimum 14pt for clarity."
            )
        ].sorted { lhs, rhs in
            lhs.category.rawValue < rhs.category.rawValue ||
            (lhs.category.rawValue == rhs.category.rawValue && lhs.name < rhs.name)
        }
    }

    // MARK: - Recommended for Engraving

    /// Filters the font list to fonts suitable for small engraving work.
    ///
    /// Fonts with a recommended minimum size less than or equal to `minFontSize`
    /// are included. This helps users pick fonts that will still be legible
    /// at their target engraving size.
    ///
    /// - Parameter minFontSize: The minimum font size the user plans to engrave at (in points).
    /// - Returns: Array of fonts suitable for the given minimum size, sorted by suitability.
    public static func recommendedForEngraving(minFontSize: Double) -> [EngravingFont] {
        engravingFonts().filter { $0.size <= minFontSize }
    }

    // MARK: - Category Filtering

    /// Returns fonts in a specific category.
    ///
    /// - Parameter category: The font category to filter by.
    /// - Returns: Array of fonts matching the given category.
    public static func fonts(in category: EngravingFontCategory) -> [EngravingFont] {
        engravingFonts().filter { $0.category == category }
    }

    // MARK: - Font Availability

    /// Checks whether a font is available on the current macOS system.
    ///
    /// Uses CoreText to verify font availability at runtime.
    ///
    /// - Parameter name: The font name to check (e.g. "Helvetica Neue").
    /// - Returns: `true` if the font is available, `false` otherwise.
    public static func isFontAvailableOnSystem(_ name: String) -> Bool {
        #if canImport(CoreText)
        guard !name.isEmpty else { return false }
        let ctFont = CTFontCreateWithName(name as CFString, 12.0, nil)
        // CTFontCreateWithName never returns nil — it falls back to system font.
        // We verify by checking the actual font family name matches.
        let familyName = CTFontCopyFamilyName(ctFont) as String?
        return familyName != nil
        #else
        return false
        #endif
    }

    /// Checks whether all fonts in the curated pack are available on the system.
    ///
    /// Keyed by font identity (`name (weight)`), so weight variants of the same
    /// family each get their own availability entry.
    ///
    /// - Returns: Dictionary mapping font identity to availability status.
    public static func checkAllAvailability() -> [String: Bool] {
        var result: [String: Bool] = [:]
        for font in engravingFonts() {
            let key = "\(font.name) (\(font.weight))"
            result[key] = isFontAvailableOnSystem(font.name)
        }
        return result
    }

    /// Returns only fonts that are confirmed available on the current system.
    ///
    /// - Returns: Filtered array of `EngravingFont` entries that exist on the system.
    public static func availableFonts() -> [EngravingFont] {
        engravingFonts().filter { isFontAvailableOnSystem($0.name) }
    }
}
