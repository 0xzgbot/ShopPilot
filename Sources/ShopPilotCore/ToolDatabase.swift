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
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: ToolType,
        diameter: Double,
        cuttingLength: Double,
        totalLength: Double,
        shankDiameter: Double,
        flutes: Int = 2,
        material: String = "carbide"
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
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
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
            let tool = Tool(
                name: entry.name,
                type: entry.type,
                diameter: entry.diameterMm,
                cuttingLength: max(4.0, entry.diameterMm * 3),
                totalLength: max(20.0, entry.diameterMm * 5),
                shankDiameter: min(entry.diameterMm, 6.35),
                flutes: entry.type == .vBit || entry.type == .drill || entry.type == .diamondDrag ? 1 : 2
            )
            tools.append(tool)
        }
        // Deliberately NOT persisted here: defaults are first-run seeds only.
        // They land on disk via the next explicit save (add/remove/update), so
        // an empty persisted store stays empty and a fresh launch re-seeds.
    }
}
