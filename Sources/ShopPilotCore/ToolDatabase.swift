import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - Tool Type

/// Tool classes. SPK-1133: expanded to the installer-verified 13-class
/// taxonomy (end mill, radiused end mill, ball nose, V-bit, engraving,
/// radiused engraving, drill, diamond drag, laser, thread mill, multi
/// thread mill, plasma, form). `slotCutter` is retained for backward
/// decode of pre-1133 persisted tools.
public enum ToolType: String, Codable, CaseIterable {
    case endMill
    case radiusedEndMill
    case ballNose
    case vBit
    case engraving
    case radiusedEngraving
    case drill
    case diamondDrag
    case laser
    case threadMill
    case multiThreadMill
    case plasma
    case form
    case slotCutter // legacy pre-1133 case, kept for persisted decode

    public var displayName: String {
        switch self {
        case .endMill: return "End Mill"
        case .radiusedEndMill: return "Radiused End Mill"
        case .ballNose: return "Ball Nose"
        case .vBit: return "V-Bit"
        case .engraving: return "Engraving"
        case .radiusedEngraving: return "Radiused Engraving"
        case .drill: return "Drill"
        case .diamondDrag: return "Diamond Drag"
        case .laser: return "Laser"
        case .threadMill: return "Thread Mill"
        case .multiThreadMill: return "Multi Thread Mill"
        case .plasma: return "Plasma"
        case .form: return "Form"
        case .slotCutter: return "Slot Cutter"
        }
    }
}

// MARK: - Tool

/// SPK-1133b — per-material cutting data (the "cut-data" part of the 3-part
/// linkage geometry / cut-data / machine-cut-data). One entry per material;
/// resolution picks the entry matching the job material, then applies any
/// machine override.
public struct ToolCutData: Codable, Equatable, Hashable, Sendable {
    public var material: String  // "hardwood", "softwood", "plastic", "aluminum", "steel"
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double
    public var maxDepthOfCutMm: Double

    public init(
        material: String,
        feedRateMmPerMin: Double,
        plungeRateMmPerMin: Double,
        spindleRpm: Double,
        maxDepthOfCutMm: Double
    ) {
        self.material = material
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
        self.maxDepthOfCutMm = maxDepthOfCutMm
    }
}

/// SPK-1133b — per-machine cutting data (the "machine-cut-data" part of the
/// linkage). Machines have different rigidity/spindles, so their safe feeds
/// and depths legitimately differ; switching machines swaps these values
/// without touching tool geometry or per-material cut data.
public struct MachineCutData: Codable, Equatable, Hashable, Sendable {
    public var machineName: String  // key: machine profile name ("GRBL 3018", …)
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double
    public var maxDepthOfCutMm: Double

    public init(
        machineName: String,
        feedRateMmPerMin: Double,
        plungeRateMmPerMin: Double,
        spindleRpm: Double,
        maxDepthOfCutMm: Double
    ) {
        self.machineName = machineName
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
        self.maxDepthOfCutMm = maxDepthOfCutMm
    }
}

/// SPK-1133b — the fully resolved cutting data for a (tool, material, machine)
/// triple after walking the 3-part linkage: derived defaults → per-material
/// cut data → per-machine override.
public struct ResolvedCutData: Equatable, Sendable {
    public var feedRateMmPerMin: Double
    public var plungeRateMmPerMin: Double
    public var spindleRpm: Double
    public var maxDepthOfCutMm: Double

    public init(
        feedRateMmPerMin: Double,
        plungeRateMmPerMin: Double,
        spindleRpm: Double,
        maxDepthOfCutMm: Double
    ) {
        self.feedRateMmPerMin = feedRateMmPerMin
        self.plungeRateMmPerMin = plungeRateMmPerMin
        self.spindleRpm = spindleRpm
        self.maxDepthOfCutMm = maxDepthOfCutMm
    }
}

public struct Tool: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public let type: ToolType
    public let diameter: Double  // mm
    public let cuttingLength: Double  // mm
    public let totalLength: Double  // mm
    public let shankDiameter: Double  // mm
    public let flutes: Int
    public var material: String = "carbide"
    public var createdAt: Date
    public var updatedAt: Date

    // SPK-1133b — 3-part linkage. Geometry stays above; cutting data is
    // per-material, machine cutting data is per-machine. Both are additive
    // (custom Codable decodes their absence as `[]`, so pre-1133b persisted
    // tools still load).
    public var cutData: [ToolCutData] = []
    public var machineCutData: [MachineCutData] = []

    public init(
        id: UUID = UUID(),
        name: String,
        type: ToolType,
        diameter: Double,
        cuttingLength: Double,
        totalLength: Double,
        shankDiameter: Double,
        flutes: Int = 2,
        material: String = "carbide",
        cutData: [ToolCutData] = [],
        machineCutData: [MachineCutData] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.diameter = diameter
        self.cuttingLength = cuttingLength
        self.totalLength = totalLength
        self.shankDiameter = shankDiameter
        self.flutes = flutes
        self.material = material
        self.cutData = cutData
        self.machineCutData = machineCutData
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    // MARK: Codable — backward compatible: pre-1133b persisted tools (no
    // `cutData`/`machineCutData` keys) decode with empty arrays.

    private enum CodingKeys: String, CodingKey {
        case id, name, type, diameter, cuttingLength, totalLength
        case shankDiameter, flutes, material, createdAt, updatedAt
        case cutData, machineCutData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(ToolType.self, forKey: .type)
        diameter = try c.decode(Double.self, forKey: .diameter)
        cuttingLength = try c.decode(Double.self, forKey: .cuttingLength)
        totalLength = try c.decode(Double.self, forKey: .totalLength)
        shankDiameter = try c.decode(Double.self, forKey: .shankDiameter)
        flutes = try c.decode(Int.self, forKey: .flutes)
        material = try c.decodeIfPresent(String.self, forKey: .material) ?? "carbide"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        cutData = try c.decodeIfPresent([ToolCutData].self, forKey: .cutData) ?? []
        machineCutData = try c.decodeIfPresent([MachineCutData].self, forKey: .machineCutData) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(diameter, forKey: .diameter)
        try c.encode(cuttingLength, forKey: .cuttingLength)
        try c.encode(totalLength, forKey: .totalLength)
        try c.encode(shankDiameter, forKey: .shankDiameter)
        try c.encode(flutes, forKey: .flutes)
        try c.encode(material, forKey: .material)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(cutData, forKey: .cutData)
        try c.encode(machineCutData, forKey: .machineCutData)
    }

    // MARK: - SPK-1133b resolution

    /// Default spindle RPM when no linked cutting data is configured.
    /// Inverse-diameter heuristic (small tools spin fast), clamped to the
    /// range a typical router spindle actually delivers.
    public static func recommendedSpindleRpm(diameter: Double) -> Double {
        min(24000, max(6000, 12000 * (6.35 / max(diameter, 0.5))))
    }

    /// Default pass depth when no linked cutting data is configured.
    public static func recommendedDepthOfCut(diameter: Double) -> Double {
        min(2.0, max(0.5, diameter * 0.5))
    }

    /// Walk the 3-part linkage and return the effective cutting data:
    ///   1. machine override (machineCutData matching `machineName`) wins —
    ///      per-machine cut data can differ, and switching machines swaps
    ///      speeds without touching geometry or material data;
    ///   2. else per-material cut data (`cutData` matching `material`);
    ///   3. else geometry-derived defaults.
    public func resolvedCutData(material: String?, machineName: String?) -> ResolvedCutData {
        if let machineName,
           let mc = machineCutData.first(where: {
               $0.machineName.caseInsensitiveCompare(machineName) == .orderedSame
           }) {
            return ResolvedCutData(
                feedRateMmPerMin: mc.feedRateMmPerMin,
                plungeRateMmPerMin: mc.plungeRateMmPerMin,
                spindleRpm: mc.spindleRpm,
                maxDepthOfCutMm: mc.maxDepthOfCutMm
            )
        }
        if let material,
           let cd = cutData.first(where: {
               $0.material.caseInsensitiveCompare(material) == .orderedSame
           }) {
            return ResolvedCutData(
                feedRateMmPerMin: cd.feedRateMmPerMin,
                plungeRateMmPerMin: cd.plungeRateMmPerMin,
                spindleRpm: cd.spindleRpm,
                maxDepthOfCutMm: cd.maxDepthOfCutMm
            )
        }
        return ResolvedCutData(
            feedRateMmPerMin: ToolDatabase.recommendedFeedRate(diameter: diameter),
            plungeRateMmPerMin: ToolDatabase.recommendedPlungeRate(diameter: diameter),
            spindleRpm: Tool.recommendedSpindleRpm(diameter: diameter),
            maxDepthOfCutMm: Tool.recommendedDepthOfCut(diameter: diameter)
        )
    }
}

// MARK: - Tool Database

public final class ToolDatabase: ObservableObject {
    
    @Published public var tools: [Tool] = []
    
    /// Storage key. Internal so tests can clear it for isolation.
    static let userDefaultsKey = "shopPilotTools"
    
    public init() {
        // Preload defaults only on a genuine first run — when nothing has ever
        // been persisted. An explicitly saved empty list must stay empty.
        if !load() {
            preloadDefaultTools()
        }
    }
    
    // MARK: - CRUD
    
    public func add(_ tool: Tool) {
        tools.append(tool)
        save()
    }
    
    public func remove(id: UUID) {
        tools.removeAll { $0.id == id }
        save()
    }
    
    public func update(_ tool: Tool) {
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            var updated = tool
            updated.updatedAt = Date()
            tools[index] = updated
            save()
        }
    }
    
    // MARK: - Persistence
    
    public func save() {
        if let encoded = try? JSONEncoder().encode(tools) {
            UserDefaults.standard.set(encoded, forKey: ToolDatabase.userDefaultsKey)
        }
    }
    
    /// Load tools from persisted storage.
    /// - Returns: `true` when persisted data existed and was loaded.
    @discardableResult
    public func load() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: ToolDatabase.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Tool].self, from: data) else {
            return false
        }
        tools = decoded
        return true
    }
    
    // MARK: - Lookup

    /// Find a tool by id, or nil if unknown.
    public func tool(withID id: UUID?) -> Tool? {
        guard let id else { return nil }
        return tools.first { $0.id == id }
    }

    /// Tools restricted to the given types (order preserved).
    public func tools(ofTypes types: Set<ToolType>) -> [Tool] {
        tools.filter { types.contains($0.type) }
    }

    // MARK: - Calculations

    /// Recommended feed rate in mm/min based on tool diameter (SPK-1133:
    /// static so toolpath recalc can derive feeds without a database instance).
    public static func recommendedFeedRate(diameter: Double, material: String = "hardwood") -> Double {
        let baseRate: [String: Double] = [
            "hardwood": 3.0,
            "softwood": 4.0,
            "plastic": 5.0,
            "aluminum": 1.5,
            "steel": 0.8
        ]
        let materialFactor = baseRate[material.lowercased()] ?? 3.0
        return 10 * diameter * sqrt(diameter) * materialFactor
    }

    /// Recommended plunge rate as a fraction of the cut feed rate.
    public static func recommendedPlungeRate(diameter: Double, material: String = "hardwood") -> Double {
        recommendedFeedRate(diameter: diameter, material: material) * 0.4
    }

    /// Recommended feed rate in mm/min based on tool diameter.
    public func recommendedFeedRate(diameter: Double, material: String = "hardwood") -> Double {
        Self.recommendedFeedRate(diameter: diameter, material: material)
    }
    
    /// Recommended plunge rate as percentage of cut feed rate.
    public func recommendedPlungeRate(for tool: Tool, in material: String = "hardwood") -> Double {
        Self.recommendedPlungeRate(diameter: tool.diameter, material: material)
    }
    
    // MARK: - Defaults

    /// SPK-1133 — the installer-verified 17 default tool assignments, keyed by
    /// strategy name (Aspire V12.5 seed catalog). Used for first-run seeding
    /// AND the strategy→default mapping so Cut ops start with a real tool.
    public static let defaultToolCatalog: [(strategy: String, name: String, type: ToolType, diameterMm: Double)] = [
        ("Profile", "End Mill 1/4\"", .endMill, 6.35),
        ("Pocket", "End Mill 1/8\"", .endMill, 3.175),
        ("V-Carve", "V-Bit 90° 1¼\"", .vBit, 31.75),
        ("V-Inlay", "V-Bit 90° 1¼\"", .vBit, 31.75),
        ("3Carve", "V-Bit 60° 1/4\"", .vBit, 6.35),
        ("Finish", "Ball Nose 1/8\"", .ballNose, 3.175),
        ("Rough", "End Mill 1/4\"", .endMill, 6.35),
        ("Drilling", "Drill 118° 1/4\"", .drill, 6.35),
        ("Chamfer", "V-Bit 60° 1/4\"", .vBit, 6.35),
        ("Fluting", "Ball Nose 1/4\"", .ballNose, 6.35),
        ("SweptProfile", "Ball Nose 1/4\"", .ballNose, 6.35),
        ("Texture", "Ball Nose 1/4\"", .ballNose, 6.35),
        ("QuickEngrave", "Diamond Drag 90° 1/8\" 0.002\"", .diamondDrag, 3.175),
        ("BevelCarving", "V-Bit 90° 1¼\"", .vBit, 31.75),
        ("ThreadMilling", "Thread Mill 60° 3/4\"", .threadMill, 19.05),
        ("LaserEngrave", "Laser Cutter 3.8W 0.3mm", .laser, 0.3),
        ("PhotoVCarve", "V-Bit 60° 1/4\"", .vBit, 6.35),
    ]

    /// Default tool for a strategy name ("Profile", "V-Carve", …), or nil when
    /// the strategy has no catalog entry or the tool isn't in the database.
    public func defaultTool(forStrategy strategy: String) -> Tool? {
        guard let entry = ToolDatabase.defaultToolCatalog.first(where: {
            $0.strategy.caseInsensitiveCompare(strategy) == .orderedSame
        }) else { return nil }
        return tools.first { $0.name == entry.name && $0.type == entry.type }
    }

    private func preloadDefaultTools() {
        // The 17 installer-verified defaults, one tool per distinct catalog
        // entry (several strategies share the same physical tool).
        var seen = Set<String>()
        for entry in ToolDatabase.defaultToolCatalog {
            let key = "\(entry.name)|\(entry.type.rawValue)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            // SPK-1133b: seeded tools carry per-material cut data (hardwood
            // entry matching the derived formulas, so recalc behavior is
            // unchanged) — the 3-part linkage is real out of the box.
            let feed = ToolDatabase.recommendedFeedRate(diameter: entry.diameterMm)
            let plunge = ToolDatabase.recommendedPlungeRate(diameter: entry.diameterMm)
            let tool = Tool(
                name: entry.name,
                type: entry.type,
                diameter: entry.diameterMm,
                cuttingLength: max(4.0, entry.diameterMm * 3),
                totalLength: max(20.0, entry.diameterMm * 5),
                shankDiameter: min(entry.diameterMm, 6.35),
                flutes: entry.type == .vBit || entry.type == .drill || entry.type == .diamondDrag ? 1 : 2,
                cutData: [
                    ToolCutData(
                        material: "hardwood",
                        feedRateMmPerMin: feed,
                        plungeRateMmPerMin: plunge,
                        spindleRpm: Tool.recommendedSpindleRpm(diameter: entry.diameterMm),
                        maxDepthOfCutMm: Tool.recommendedDepthOfCut(diameter: entry.diameterMm)
                    )
                ]
            )
            tools.append(tool)
        }
        // Deliberately NOT persisted here: defaults are first-run seeds only.
        // They land on disk via the next explicit save (add/remove/update), so
        // an empty persisted store stays empty and a fresh launch re-seeds.
    }
}
