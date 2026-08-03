import Foundation

// MARK: - Material Store

/// Persists the user's last-chosen material across app launches.
///
/// `MaterialDatabase` deliberately stays in-memory (static presets); this store
/// keeps just the *selection* key in `UserDefaults` so the setup UI can restore
/// it and newly created jobs can default their sheet material to it.
public struct MaterialStore {

    /// UserDefaults key holding the last-selected material name.
    public static let lastUsedKey = "shop_pilot_last_material_name"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Name of the material the user last picked, if any.
    public var lastUsedMaterialName: String? {
        defaults.string(forKey: Self.lastUsedKey)
    }

    /// Remember the given material (or clear the memory when `nil`).
    public func saveLastUsed(_ material: Material?) {
        defaults.set(material?.name, forKey: Self.lastUsedKey)
    }

    /// The material to default a new sheet to: the last-used material when it
    /// still exists in the database, otherwise the MDF preset.
    public func defaultMaterial() -> Material? {
        if let name = lastUsedMaterialName,
           let material = MaterialDatabase.shared.lookup(byName: name) {
            return material
        }
        return MaterialDatabase.shared.lookup(byName: "MDF")
    }
}
