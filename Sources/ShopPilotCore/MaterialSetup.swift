import Foundation

// MARK: - Material Category

/// Broad category of CNC material. Used for filtering and default parameter selection.
public enum MaterialCategory: String, Codable, Sendable {
    case wood
    case metal
    case plastic
    case composite
    
    public var displayName: String {
        switch self {
        case .wood: return "Wood"
        case .metal: return "Metal"
        case .plastic: return "Plastic"
        case .composite: return "Composite"
        }
    }
}

// MARK: - Coolant Type

/// Recommended coolant/lubrication type for a material during CNC machining.
public enum CoolantType: String, Codable, Sendable {
    case none          // Dry cut — no coolant needed or recommended
    case air           // Compressed air (blowout)
    case mist          // Oil/water mist
    case flood         // Flood coolant
    case vacuum        // Vacuum extraction only
    
    public var displayName: String {
        switch self {
        case .none: return "None (dry cut)"
        case .air: return "Compressed Air"
        case .mist: return "Mist"
        case .flood: return "Flood Coolant"
        case .vacuum: return "Vacuum Extraction"
        }
    }
}

// MARK: - Material

/// Physical properties of a CNC workpiece material. Used by toolpath algorithms to compute safe feed rates, depth-of-cut limits, and coolant requirements.
public struct Material: Identifiable, Codable, Sendable {
    
    // MARK: - Properties
    
    public let id: UUID
    public let name: String
    public let category: MaterialCategory
    
    /// Density in g/cm³ (grams per cubic centimeter).
    public let density: Double
    
    /// Brinell hardness rating on a 0–100 scale relative to common CNC materials.
    /// 0 = very soft (balsa), 50 = mild steel, 100 = hardened tool steel.
    public let hardnessRating: Double
    
    /// Maximum recommended feed rate in mm/min for a standard end mill on this material.
    public let maxFeedRateMmPerMin: Double
    
    /// Maximum recommended depth of cut in mm per pass for this material.
    public let maxDepthOfCutMm: Double
    
    /// Recommended coolant type during machining.
    public let coolantType: CoolantType
    
    /// Display name shown in UI pickers (may differ from internal name).
    public var displayName: String { name }
    
    // MARK: - Init
    
    public init(
        id: UUID = UUID(),
        name: String,
        category: MaterialCategory,
        density: Double,           // g/cm³
        hardnessRating: Double,    // 0–100 scale
        maxFeedRateMmPerMin: Double,
        maxDepthOfCutMm: Double,
        coolantType: CoolantType
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.density = density
        self.hardnessRating = hardnessRating
        self.maxFeedRateMmPerMin = maxFeedRateMmPerMin
        self.maxDepthOfCutMm = maxDepthOfCutMm
        self.coolantType = coolantType
    }
}

// MARK: - Predefined Materials

extension Material {
    
    /// Pine — softwood, easy to machine. Low density, low hardness.
    public static let pine = Material(
        name: "Pine",
        category: .wood,
        density: 0.50,           // g/cm³ (varies by species)
        hardnessRating: 12,
        maxFeedRateMmPerMin: 6000,
        maxDepthOfCutMm: 6.0,
        coolantType: .air
    )
    
    /// Oak — hardwood, moderate density and hardness.
    public static let oak = Material(
        name: "Oak",
        category: .wood,
        density: 0.75,
        hardnessRating: 35,
        maxFeedRateMmPerMin: 4000,
        maxDepthOfCutMm: 4.0,
        coolantType: .air
    )
    
    /// Maple — dense hardwood, higher hardness than oak.
    public static let maple = Material(
        name: "Maple",
        category: .wood,
        density: 0.72,
        hardnessRating: 40,
        maxFeedRateMmPerMin: 3500,
        maxDepthOfCutMm: 3.5,
        coolantType: .air
    )
    
    /// Aluminum 6061 — most common CNC aluminum alloy. Moderate density, low hardness for a metal.
    public static let aluminum6061 = Material(
        name: "Aluminum 6061",
        category: .metal,
        density: 2.70,
        hardnessRating: 30,
        maxFeedRateMmPerMin: 4500,
        maxDepthOfCutMm: 2.0,
        coolantType: .mist
    )
    
    /// Mild steel (A36) — common structural steel. High density, high hardness.
    public static let steel = Material(
        name: "Steel (A36)",
        category: .metal,
        density: 7.85,
        hardnessRating: 50,
        maxFeedRateMmPerMin: 1500,
        maxDepthOfCutMm: 1.0,
        coolantType: .flood
    )
    
    /// Acrylic (PMMA) — clear thermoplastic. Low density, low hardness, prone to melting if fed too slowly.
    public static let acrylic = Material(
        name: "Acrylic (PMMA)",
        category: .plastic,
        density: 1.18,
        hardnessRating: 15,
        maxFeedRateMmPerMin: 5000,
        maxDepthOfCutMm: 3.0,
        coolantType: .air
    )
    
    /// MDF — medium-density fiberboard. Uniform structure, moderate density.
    public static let mdf = Material(
        name: "MDF",
        category: .composite,
        density: 0.70,
        hardnessRating: 20,
        maxFeedRateMmPerMin: 5000,
        maxDepthOfCutMm: 5.0,
        coolantType: .vacuum
    )
    
    /// Plywood — layered wood composite. Moderate density, grain direction matters.
    public static let plywood = Material(
        name: "Plywood",
        category: .composite,
        density: 0.65,
        hardnessRating: 25,
        maxFeedRateMmPerMin: 4500,
        maxDepthOfCutMm: 4.5,
        coolantType: .air
    )
}
