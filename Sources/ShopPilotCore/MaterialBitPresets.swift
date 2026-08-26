import Foundation

// MARK: - SPK-2024b: named material + bit combo presets ("presets over parameters")
//
// A curated, NAMED cut recipe (material + bit combination) that fills the
// Cut depth / feed / rpm fields of a Cut 2D operation in one pick — instead
// of the user hand-typing numbers. Extends the SPK-1920e MaterialBitPreset-
// Picker (which lists per-tool cut-data presets) with a shipped catalog of
// named combos usable on EVERY strategy form, not just Rough 3D.
//
// Pure data + pure fill logic live here in Core so the CLT can prove the
// fill without the app target; UI wiring is compile-checked by the app build.

/// One named material+bit combo. All values are positive, machine-ready
/// numbers — picking the preset writes them verbatim into the form fields.
public struct NamedMaterialBitPreset: Codable, Sendable, Equatable {
    public let id: String
    /// Display name shown in the picker, e.g. "Walnut 18 mm + 90° V-bit".
    public let name: String
    public let materialName: String
    public let bitSummary: String
    /// Total cut depth written into the form's depth field (mm).
    public let cutDepthMm: Double
    public let feedRateMmPerMin: Double
    public let plungeFeedRateMmPerMin: Double
    public let spindleRpm: Double

    public init(
        id: String,
        name: String,
        materialName: String,
        bitSummary: String,
        cutDepthMm: Double,
        feedRateMmPerMin: Double,
        plungeFeedRateMmPerMin: Double,
        spindleRpm: Double
    ) {
        self.id = id
        self.name = name
        self.materialName = materialName
        self.bitSummary = bitSummary
        self.cutDepthMm = cutDepthMm
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeFeedRateMmPerMin = plungeFeedRateMmPerMin
        self.spindleRpm = spindleRpm
    }
}

/// Strategies whose params accept a preset fill through this protocol.
/// Each strategy stores its depth under its own field name; the conformance
/// maps the preset onto the right one (all three Cut 2D strategies use
/// maxDepthOfCutMm as their single depth field — labeled "Cut depth" or
/// "Depth/pass" depending on the form).
public protocol PresetFillable {
    mutating func applyPreset(_ preset: NamedMaterialBitPreset)
}

extension ProfileToolpathParams: PresetFillable {
    public mutating func applyPreset(_ preset: NamedMaterialBitPreset) {
        maxDepthOfCutMm = preset.cutDepthMm
        feedRateMmPerMin = preset.feedRateMmPerMin
        plungeFeedRateMmPerMin = preset.plungeFeedRateMmPerMin
        spindleRpm = preset.spindleRpm
    }
}

extension PocketToolpathParams: PresetFillable {
    public mutating func applyPreset(_ preset: NamedMaterialBitPreset) {
        maxDepthOfCutMm = preset.cutDepthMm
        feedRateMmPerMin = preset.feedRateMmPerMin
        plungeFeedRateMmPerMin = preset.plungeFeedRateMmPerMin
        spindleRpm = preset.spindleRpm
    }
}

extension VCarveParams: PresetFillable {
    public mutating func applyPreset(_ preset: NamedMaterialBitPreset) {
        maxDepthOfCutMm = preset.cutDepthMm
        feedRateMmPerMin = preset.feedRateMmPerMin
        plungeFeedRateMmPerMin = preset.plungeFeedRateMmPerMin
        spindleRpm = preset.spindleRpm
    }
}

/// Shipped catalog of named combos. Lookup is exact-name; the picker keys
/// selections on `name`, so names must be unique across the catalog.
public enum MaterialBitPresetCatalog {
    public static let shipped: [NamedMaterialBitPreset] = [
        NamedMaterialBitPreset(
            id: "walnut-18mm-vbit-90",
            name: "Walnut 18 mm + 90° V-bit",
            materialName: "walnut",
            bitSummary: "90° V-bit",
            cutDepthMm: 3.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 250,
            spindleRpm: 18000
        ),
        NamedMaterialBitPreset(
            id: "plywood-12mm-endmill-6",
            name: "Plywood 12 mm + 6 mm end mill",
            materialName: "plywood",
            bitSummary: "6 mm spiral upcut",
            cutDepthMm: 6.0,
            feedRateMmPerMin: 1400,
            plungeFeedRateMmPerMin: 350,
            spindleRpm: 18000
        ),
    ]

    /// Exact-name lookup (case-sensitive — the picker always passes back a
    /// name it listed verbatim).
    public static func named(_ name: String) -> NamedMaterialBitPreset? {
        shipped.first(where: { $0.name == name })
    }
}
