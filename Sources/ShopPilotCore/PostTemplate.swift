import Foundation

// MARK: - Post template (SPK-1134: template grammar + bundled posts)

/// A post-processor template: a text recipe that turns raw move lines
/// (`G0 X10 Y20 Z5`) into machine-specific G-code. Lines containing format
/// specifiers are MOVE templates (emitted once per move); all other lines are
/// emitted verbatim (header/footer/modals).
///
/// Grammar (modeled on the observed `.pp` pattern):
///   `[<WORD>|<MODE>|<OUT>|<FORMAT>]`
///   - WORD:   the raw-move word to format — X, Y, Z, A, B, C, F, S, T, N, D
///   - MODE:   `A` absolute value · `C` current (last-emitted) value ·
///             `I` incremental delta since the previous move
///   - OUT:    the letter(s) to emit (e.g. "X"), or `-` to suppress
///   - FORMAT: `w.d` decimal format (e.g. `1.3` = 3 decimals, `1.0` = none)
///
/// A specifier whose word is absent from the current move emits nothing, so
/// one move template serves Z-less rapids and full 3D feeds alike.
public struct PostTemplate: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Short UI description.
    public let summary: String
    /// The template recipe (see `PostTemplateEngine` for directives).
    public let text: String
    /// Whether Y coordinates wrap onto the rotary A axis (Y2A).
    public let rotaryWrap: Bool
    /// Stock diameter (mm) used by the rotary wrap conversion.
    public let wrapDiameterMm: Double

    public init(
        id: String,
        name: String,
        summary: String,
        text: String,
        rotaryWrap: Bool = false,
        wrapDiameterMm: Double = 50.0
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.text = text
        self.rotaryWrap = rotaryWrap
        self.wrapDiameterMm = wrapDiameterMm
    }
}

// MARK: - Shipped templates

extension PostTemplate {

    /// GRBL in/mm — the standard hobby-CNC post. Emits G21 (mm) or G20
    /// (inch) from the `units` parameter (SPK-0415 linkage), absolute
    /// positioning, spindle on, and a safe retract at the end.
    public static func grbl(units: GCodeUnits) -> PostTemplate {
        PostTemplate(
            id: "grbl-\(units == .millimeter ? "mm" : "in")",
            name: "GRBL \(units == .millimeter ? "mm" : "inch")",
            summary: "GRBL 1.1 — \(units == .millimeter ? "metric (G21)" : "imperial (G20)")",
            text: grblTemplateText(units: units)
        )
    }

    /// GRBL rotary wrap (Y2A) — the Y axis maps to the rotary A axis
    /// (rotation about X). Linear X stays linear; every Y coordinate becomes
    /// A degrees via `a = y / (π·diameter) · 360`. The A word is always
    /// absolute (the wrap is monotonic around the cylinder).
    public static func grblRotaryWrap(diameterMm: Double = 50.0) -> PostTemplate {
        PostTemplate(
            id: "grbl-rotary-y2a",
            name: "GRBL Rotary Wrap (Y2A)",
            summary: "Y → A degrees about X (wrap diameter \(Int(diameterMm)) mm)",
            text: rotaryWrapTemplateText,
            rotaryWrap: true,
            wrapDiameterMm: diameterMm
        )
    }

    /// All shipped templates.
    public static let shipped: [PostTemplate] = [
        .grbl(units: .millimeter),
        .grbl(units: .inch),
        .grblRotaryWrap(),
    ]

    public static func shipped(byID id: String) -> PostTemplate? {
        shipped.first { $0.id == id }
    }

    // MARK: Recipes

    static func grblTemplateText(units: GCodeUnits) -> String {
        let modal = units.modalCode
        let unitsComment = units == .millimeter ? "Millimeter units" : "Inch units"
        return """
        %
        (ShopPilot \(units == .millimeter ? "mm" : "in") post)
        [N|A|N|3.0] \(modal) ; \(unitsComment)
        [N|A|N|3.0] G90 ; Absolute positioning
        [N|A|N|3.0] G17 ; XY plane
        (--- moves ---)
        [N|A|N|3.0] [G]
        (--- end ---)
        [N|A|N|3.0] M9
        [N|A|N|3.0] G0 Z5.000 ; Retract to safe height
        [N|A|N|3.0] M2
        %
        """
    }

    static let rotaryWrapTemplateText = """
    %
    (ShopPilot GRBL rotary wrap Y2A post)
    [N|A|N|3.0] G21 ; Millimeter units
    [N|A|N|3.0] G90 ; Absolute positioning
    [N|A|N|3.0] G17 ; XY plane
    (Y maps to A degrees about X — wrap diameter [D|A|-|1.1] mm)
    (--- moves ---)
    [N|A|N|3.0] [G]
    (--- end ---)
    [N|A|N|3.0] M9
    [N|A|N|3.0] G0 Z5.000 ; Retract to safe height
    [N|A|N|3.0] M2
    %
    """
}
