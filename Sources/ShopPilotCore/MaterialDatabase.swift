import Foundation

// MARK: - Material Database

/// In-memory database of common CNC materials with lookup by name and category.
/// Mirrors the pattern used by ToolDatabase but without UserDefaults persistence —
/// material presets are static; users can extend via addMaterial().
public final class MaterialDatabase {
    
    /// All registered materials, keyed by name for fast lookup.
    private var _materials: [String: Material] = [:]
    
    public var allMaterials: [Material] {
        Array(_materials.values).sorted { $0.name < $1.name }
    }
    
    /// Materials grouped by category.
    public var materialsByCategory: [MaterialCategory: [Material]] {
        var groups: [MaterialCategory: [Material]] = [:]
        for mat in allMaterials {
            groups[mat.category, default: []].append(mat)
        }
        return groups
    }
    
    private init() {}
    
    // MARK: - Singleton
    
    public static let shared = MaterialDatabase()
    
    // MARK: - Registration
    
    /// Register a material. If a material with the same name exists, it is replaced.
    public func register(_ material: Material) {
        _materials[material.name] = material
    }
    
    /// Bulk-register materials (e.g., at startup).
    public func register(materials: [Material]) {
        for mat in materials {
            _materials[mat.name] = mat
        }
    }
    
    // MARK: - Preload Defaults
    
    /// Load the built-in material presets. Call once at app launch.
    public static func preloadDefaults() {
        let defaults: [Material] = [
            .pine,
            .oak,
            .maple,
            .aluminum6061,
            .steel,
            .acrylic,
            .mdf,
            .plywood
        ]
        shared.register(materials: defaults)
    }
    
    // MARK: - Lookup
    
    /// Look up a material by its exact name. Returns nil if not found.
    public func lookup(byName name: String) -> Material? {
        _materials[name]
    }
    
    /// Look up all materials in a given category.
    public func lookup(byCategory category: MaterialCategory) -> [Material] {
        allMaterials.filter { $0.category == category }
    }
    
    /// Check whether a material with the given name exists.
    public func contains(name: String) -> Bool {
        _materials[name] != nil
    }
}
