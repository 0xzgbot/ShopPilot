import Foundation

// MARK: - Manufacturer Preset

/// SPK-1315 — one entry in the bundled manufacturer tool catalog. Mirrors the
/// `Tool` geometry fields so a preset can be materialized into a real `Tool`
/// via `ManufacturerToolCatalog.makeTool`.
public struct ManufacturerPreset: Codable, Equatable, Sendable {
    public let manufacturer: String  // "Amana" | "Whiteside"
    public let partNumber: String
    public let name: String
    public let type: ToolType
    public let diameter: Double      // mm
    public let cuttingLength: Double // mm
    public let totalLength: Double   // mm
    public let shankDiameter: Double // mm
    public let flutes: Int
    public let material: String

    public init(
        manufacturer: String,
        partNumber: String,
        name: String,
        type: ToolType,
        diameter: Double,
        cuttingLength: Double,
        totalLength: Double,
        shankDiameter: Double,
        flutes: Int = 2,
        material: String = "carbide"
    ) {
        self.manufacturer = manufacturer
        self.partNumber = partNumber
        self.name = name
        self.type = type
        self.diameter = diameter
        self.cuttingLength = cuttingLength
        self.totalLength = totalLength
        self.shankDiameter = shankDiameter
        self.flutes = flutes
        self.material = material
    }
}

// MARK: - Manufacturer Tool Catalog

/// SPK-1315 — bundled catalog of REAL, common Amana + Whiteside router bits
/// (catalog part numbers, imperial dims converted to mm) so the app can offer
/// "Import manufacturer catalog" into the tool database — the classic
/// advantage over hand-typing every bit.
public enum ManufacturerToolCatalog {

    /// All bundled presets — at least 10 real part numbers across both
    /// manufacturers. Dimensions are catalog values converted with the
    /// standard 1/8" = 3.175 mm, 1/4" = 6.35 mm, 1/2" = 12.7 mm scale.
    public static func presets() -> [ManufacturerPreset] {
        [
            // Amana Tool
            ManufacturerPreset(
                manufacturer: "Amana", partNumber: "455",
                name: "1/8in 2-Flute Carbide End Mill", type: .endMill,
                diameter: 3.175, cuttingLength: 9.525, totalLength: 38.1, shankDiameter: 3.175
            ),
            ManufacturerPreset(
                manufacturer: "Amana", partNumber: "456",
                name: "1/4in 2-Flute Carbide End Mill", type: .endMill,
                diameter: 6.35, cuttingLength: 12.7, totalLength: 50.8, shankDiameter: 6.35
            ),
            ManufacturerPreset(
                manufacturer: "Amana", partNumber: "46282-K",
                name: "60° V-Bit", type: .vBit,
                diameter: 6.35, cuttingLength: 12.7, totalLength: 38.1, shankDiameter: 6.35
            ),
            ManufacturerPreset(
                manufacturer: "Amana", partNumber: "51454",
                name: "1/8in 2-Flute Ball Nose", type: .ballNose,
                diameter: 3.175, cuttingLength: 9.525, totalLength: 38.1, shankDiameter: 3.175
            ),
            ManufacturerPreset(
                manufacturer: "Amana", partNumber: "46182-K",
                name: "60° Engraving", type: .engraving,
                diameter: 6.35, cuttingLength: 12.7, totalLength: 38.1, shankDiameter: 6.35
            ),
            // Whiteside
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "1110",
                name: "1/4in Straight Spiral", type: .endMill,
                diameter: 6.35, cuttingLength: 19.05, totalLength: 63.5, shankDiameter: 6.35
            ),
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "1500",
                name: "60° V-Bit", type: .vBit,
                diameter: 12.7, cuttingLength: 12.7, totalLength: 63.5, shankDiameter: 12.7
            ),
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "1550",
                name: "90° V-Bit", type: .vBit,
                diameter: 12.7, cuttingLength: 12.7, totalLength: 63.5, shankDiameter: 12.7
            ),
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "2110",
                name: "1/8in 2-Flute Ball Nose", type: .ballNose,
                diameter: 3.175, cuttingLength: 9.525, totalLength: 38.1, shankDiameter: 3.175
            ),
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "3110",
                name: "60° Engraving", type: .engraving,
                diameter: 6.35, cuttingLength: 12.7, totalLength: 38.1, shankDiameter: 6.35
            ),
            ManufacturerPreset(
                manufacturer: "Whiteside", partNumber: "5110",
                name: "1/4in Downcut Spiral", type: .endMill,
                diameter: 6.35, cuttingLength: 19.05, totalLength: 63.5, shankDiameter: 6.35
            ),
        ]
    }

    /// Materialize a preset into a real `Tool`. The tool name carries the
    /// manufacturer + part number so imported tools are identifiable and the
    /// name-collision check in `importAll` is deterministic.
    public static func makeTool(_ preset: ManufacturerPreset) -> Tool {
        Tool(
            name: "\(preset.manufacturer) \(preset.partNumber) \(preset.name)",
            type: preset.type,
            diameter: preset.diameter,
            cuttingLength: preset.cuttingLength,
            totalLength: preset.totalLength,
            shankDiameter: preset.shankDiameter,
            flutes: preset.flutes,
            material: preset.material
        )
    }

    /// Import every preset into `database` via `ToolDatabase.add`.
    /// - Parameter duplicatesAllowed: when `false` (default), presets whose
    ///   materialized tool name already exists in the database are skipped.
    /// - Returns: the number of tools actually added.
    public static func importAll(into database: ToolDatabase, duplicatesAllowed: Bool = false) -> Int {
        var added = 0
        for preset in presets() {
            let tool = makeTool(preset)
            if duplicatesAllowed || !database.tools.contains(where: { $0.name == tool.name }) {
                database.add(tool)
                added += 1
            }
        }
        return added
    }
}
