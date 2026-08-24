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

    /// All shipped templates (SPK-2000a: expanded to the full router/industrial/
    /// firmware/laser catalog — parity with VectorPilot's 54-post surface).
    public static let shipped: [PostTemplate] = [
        .grbl(units: .millimeter),
        .grbl(units: .inch),
        .grblRotaryWrap(),
    ] + PostCatalog.templates

    /// Grouped catalog for pickers: section name → templates in that group,
    /// in stable display order. The legacy GRBL entries stay at the top of
    /// "Routers" implicitly via their ids.
    public static var groupedShipped: [(group: String, templates: [PostTemplate])] {
        let groups = ["Routers", "Industrial", "Firmware", "Laser & Plasma"]
        return groups.map { group in
            (group, shipped.filter { Self.group(of: $0) == group })
        }.filter { !$0.templates.isEmpty }
    }

    /// Which display group a template belongs to (derived from id prefix —
    /// single source of truth is the catalog definition itself).
    public static func group(of template: PostTemplate) -> String {
        switch template.id {
        case let id where id.hasPrefix("haas") || id.hasPrefix("fanuc")
            || id.hasPrefix("sinumerik") || id.hasPrefix("heidenhain")
            || id.hasPrefix("okuma") || id.hasPrefix("centroid"):
            return "Industrial"
        case let id where id.hasPrefix("marlin") || id.hasPrefix("smoothie")
            || id.hasPrefix("duet") || id.hasPrefix("linuxcnc"):
            return "Firmware"
        case let id where id.hasPrefix("laser") || id.hasPrefix("plasma"):
            return "Laser & Plasma"
        default:
            return "Routers"
        }
    }

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

// MARK: - Shipped post catalog (SPK-2000a — cross-platform parity)

/// The full shipped post surface: routers, industrial, firmware, laser+plasma.
/// Every controller family shares one of a small number of template bodies
/// (GRBL-style ok-wait dialects vs Fanuc-style G-code dialects) parameterized
/// by units; ids stay distinct per machine so profiles/persisted jobs keep
/// pointing at the exact post they were written with.
public enum PostCatalog {

    /// Controllers whose dialect is GRBL-like enough to reuse the hobby body.
    private static let grblStyleRouters: [(id: String, name: String, summary: String)] = [
        ("fluidnc", "FluidNC", "FluidNC — ESP32 GRBL-class"),
        ("mach3", "Mach3", "Mach3 — legacy parallel-port standard"),
        ("mach4", "Mach4", "Mach4 — Hobby/Industrial"),
        ("wincnc", "WinCNC", "WinCNC — Windows motion control"),
        ("masso", "Masso", "Masso G3 — standalone controller"),
        ("uccnc", "UCCNC", "UCCNC — CNC12 family"),
        ("planet-cnc", "PlanetCNC", "PlanetCNC Mk3/4"),
        ("shopbot", "ShopBot", "ShopBot OpenSBP-capable (G-code mode)"),
        ("xcarve", "X-Carve", "X-Carve / Carbide-style GRBL"),
        ("longmill", "LongMill", "LongMill MK2 — gSender default"),
        ("shapeoko", "Shapeoko", "Shapeoko XXL / Carbide Motion"),
        ("onefinity", "OneFinity", "OneFinity Journeyman/Elite (Buildbotics)"),
        ("avid", "Avid CNC", "Avid PRO (Centroid acorn GRBL mode)"),
        ("openbuilds", "OpenBuilds", "OpenBuilds CONTROL (GRBL)"),
        ("workbee", "WorkBee", "WorkBee Z1+ (GRBL)"),
        ("cnc12", "Centroid CNC12", "CNC12 mill/lathe wizard dialect"),
    ]

    /// Industrial controls — Fanuc-style dialect (G28 retract, no `%` wrapper,
    /// program numbers via O-word comment line).
    private static let industrial: [(id: String, name: String, summary: String)] = [
        ("haas", "Haas", "Haas NGC — mill/lathe dialect"),
        ("fanuc", "Fanuc", "Fanuc 0i/30i — industry-standard G-code"),
        ("sinumerik", "SINUMERIK", "Siemens SINUMERIK 828/840"),
        ("heidenhain", "Heidenhain", "Heidenhain TNC (DIN/ISO mode)"),
        ("okuma", "Okuma", "Okuma OSP — THINC control"),
        ("centroid", "Centroid", "Centroid Acorn (G-code mode)"),
    ]

    /// Firmware stacks — Marlin-family and LinuxCNC.
    private static let firmware: [(id: String, name: String, summary: String)] = [
        ("marlin", "Marlin", "Marlin 2.x — 3D-printer-class CNC firmware"),
        ("smoothie", "Smoothieware", "Smoothieware — networked step controllers"),
        ("duet", "Duet (RepRap)", "RepRapFirmware on Duet 2/3"),
        ("linuxcnc", "LinuxCNC", "LinuxCNC (EMC2) rs274ngc"),
    ]

    /// Laser & plasma — lightburn-compatible laser dialects + plasma THC header.
    private static let laserPlasma: [(id: String, name: String, summary: String)] = [
        ("laser-grbl-m4", "Laser GRBL (M4 dynamic power)", "Laser-mode GRBL: $32=1, M4 dynamic power, S-scaled"),
        ("laser-lightburn", "LightBurn (gcode device)", "LightBurn-compatible GRBL laser dialect ($32=1)"),
        ("laser-marlin", "Laser Marlin (M3/M4)", "Marlin laser: M3/M4 OCR power, R-pixel raster friendly"),
        ("plasma-thc", "Plasma (THC)", "Plasma table: torch-on delay + THC enable/disable"),
    ]

    /// Every entry, mm + inch variants where the dialect distinguishes units
    /// (industrial posts carry explicit G21/G20; firmware posts are mm-only
    /// because that's what those firmwares accept).
    public static var templates: [PostTemplate] {
        var result: [PostTemplate] = []

        // Routers: GRBL-family body, mm + inch each.
        for router in grblStyleRouters {
            result.append(PostTemplate(
                id: "\(router.id)-mm",
                name: "\(router.name) (mm)",
                summary: "\(router.summary) — metric (G21)",
                text: dialectBody(modal: "G21", retractWord: "G0 Z5.000")
            ))
            result.append(PostTemplate(
                id: "\(router.id)-in",
                name: "\(router.name) (inch)",
                summary: "\(router.summary) — imperial (G20)",
                text: dialectBody(modal: "G20", retractWord: "G0 Z0.200")
            ))
        }

        // Industrial: Fanuc-flavored body, mm + inch each.
        for machine in industrial {
            result.append(PostTemplate(
                id: "\(machine.id)-mm",
                name: "\(machine.name) (mm)",
                summary: "\(machine.summary) — metric",
                text: industrialBody(unitsLine: "G21")
            ))
            result.append(PostTemplate(
                id: "\(machine.id)-in",
                name: "\(machine.name) (inch)",
                summary: "\(machine.summary) — inch",
                text: industrialBody(unitsLine: "G20")
            ))
        }

        // Firmware: mm-only (these firmwares reject G20 as configured here).
        for fw in firmware {
            result.append(PostTemplate(
                id: "\(fw.id)-mm",
                name: "\(fw.name) (mm)",
                summary: fw.summary,
                text: dialectBody(modal: "G21", retractWord: "G0 Z5.000")
            ))
        }

        // Laser & plasma: mm-only laser dialect with $32=1 + M4 dynamic power.
        for lp in laserPlasma {
            let body = lp.id == "plasma-thc"
                ? plasmaBody
                : laserBody(name: lp.name)
            result.append(PostTemplate(
                id: "\(lp.id)-mm",
                name: "\(lp.name) (mm)",
                summary: lp.summary,
                text: body
            ))
        }

        return result
    }

    /// Count helper for asserts/UI badges.
    public static var count: Int { templates.count + 3 } // + legacy GRBL trio

    // MARK: - Bodies

    /// GRBL-family dialect: % wrapper, units, absolute, XY plane, moves, M9
    /// coolant-off, safe retract, M2 end.
    private static func dialectBody(modal: String, retractWord: String) -> String {
        """
        %
        (ShopPilot post)
        [N|A|N|3.0] \(modal)
        [N|A|N|3.0] G90 ; Absolute positioning
        [N|A|N|3.0] G17 ; XY plane
        (--- moves ---)
        [N|A|N|3.0] [G]
        (--- end ---)
        [N|A|N|3.0] M9
        [N|A|N|3.0] \(retractWord) ; Retract to safe height
        [N|A|N|3.0] M2
        %
        """
    }

    /// Fanuc-family dialect: no % wrapper, G28-safe retract, program-name
    /// comment first line, M30 end code instead of M2.
    private static func industrialBody(unitsLine: String) -> String {
        """
        (SHOPPILOT PROGRAM)
        [N|A|N|3.0] \(unitsLine)
        [N|A|N|3.0] G90 G17 G40 G49 G80 ; Safety block
        (--- moves ---)
        [N|A|N|3.0] [G]
        (--- end ---)
        [N|A|N|3.0] M09 ; Coolant off
        [N|A|N|3.0] G91 G28 Z0. ; Retract Z to machine zero
        [N|A|N|3.0] G90
        [N|A|N|3.0] M30 ; Program end and rewind
        """
    }

    /// Laser dialect: $32=1 laser mode, M4 dynamic power (off when moving),
    /// S-power scaled moves, M5 at end.
    private static func laserBody(name: String) -> String {
        """
        %
        (ShopPilot \(name) post)
        [N|A|N|3.0] $32=1 ; Laser mode on
        [N|A|N|3.0] G21
        [N|A|N|3.0] G90 ; Absolute positioning
        (--- moves ---)
        [N|A|N|3.0] [G]
        (--- end ---)
        [N|A|N|3.0] S0 ; Power to zero
        [N|A|N|3.0] M5 ; Laser off
        [N|A|N|3.0] G0 Z5.000 ; Focus clearance
        [N|A|N|3.0] M2
        %
        """
    }

    /// Plasma dialect: torch-on dwell + THC enable before moves, THC disable +
    /// torch-off after.
    private static let plasmaBody = """
    %
    (ShopPilot plasma post)
    [N|A|N|3.0] G21
    [N|A|N|3.0] G90 ; Absolute positioning
    [N|A|N|3.0] M3 S100 ; Torch on
    [N|A|N|3.0] G4 P0.3 ; Arc-stable dwell
    [N|A|N|3.0] M64 P1 ; THC enable (Mach3/GRBL-Mega style output)
    (--- moves ---)
    [N|A|N|3.0] [G]
    (--- end ---)
    [N|A|N|3.0] M65 P1 ; THC disable
    [N|A|N|3.0] M5 ; Torch off
    [N|A|N|3.0] G0 Z10.000 ; Retract torch
    [N|A|N|3.0] M2
    %
    """
}
