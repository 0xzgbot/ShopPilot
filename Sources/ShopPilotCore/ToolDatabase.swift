import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - Tool Type

public enum ToolType: String, Codable {
    case endMill
    case vBit
    case ballNose
    case drill
    case slotCutter
    
    public var displayName: String {
        switch self {
        case .endMill: return "End Mill"
        case .vBit: return "V-Bit"
        case .ballNose: return "Ball Nose"
        case .drill: return "Drill"
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
    
    /// Recommended feed rate in mm/min based on tool diameter.
    public func recommendedFeedRate(diameter: Double, material: String = "hardwood") -> Double {
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
    
    /// Recommended plunge rate as percentage of cut feed rate.
    public func recommendedPlungeRate(for tool: Tool, in material: String = "hardwood") -> Double {
        let cutRate = recommendedFeedRate(diameter: tool.diameter, material: material)
        return cutRate * 0.4
    }
    
    // MARK: - Defaults
    
    private func preloadDefaultTools() {
        let defaults: [(String, ToolType, Double, Double, Double, Double, Int)] = [
            ("3mm End Mill", .endMill, 3.0, 9.0, 25.0, 6.0, 2),
            ("6mm End Mill", .endMill, 6.0, 14.0, 30.0, 8.0, 2),
            ("90° V-Bit", .vBit, 3.0, 8.0, 25.0, 6.0, 1),
            ("Ball Nose 3mm", .ballNose, 3.0, 4.0, 20.0, 6.0, 2)
        ]
        
        for (name, type, diameter, cuttingLength, totalLength, shankDiameter, flutes) in defaults {
            let tool = Tool(
                name: name,
                type: type,
                diameter: diameter,
                cuttingLength: cuttingLength,
                totalLength: totalLength,
                shankDiameter: shankDiameter,
                flutes: flutes
            )
            tools.append(tool)
        }
        // Deliberately NOT persisted here: defaults are first-run seeds only.
        // They land on disk via the next explicit save (add/remove/update), so
        // an empty persisted store stays empty and a fresh launch re-seeds.
    }
}
