import Foundation

// MARK: - Recent Packages (SPK-1611)

/// Remembers the last N `.shoppilot` package URLs opened or saved, newest
/// first, in UserDefaults. Backs the File ▸ Open Recent submenu without a
/// full NSDocumentController (one-window app — DocumentGroup stays out of
/// scope per the lean plan).
public enum RecentPackagesStore {

    private static let key = "shop_pilot_recent_packages"
    private static let maxCount = 8

    /// The stored recent package URLs, newest first.
    public static func recent() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.compactMap { URL(fileURLWithPath: $0) }
    }

    /// Record a successfully opened/saved package: moves it to the front and
    /// caps the list at `maxCount`. Drops entries that no longer exist on
    /// disk so the menu never lists dead files.
    public static func record(_ url: URL) {
        let fileManager = FileManager.default
        var list = [url.path]
        for existing in recent() where existing.path != url.path {
            if fileManager.fileExists(atPath: existing.path) {
                list.append(existing.path)
            }
        }
        let capped = Array(list.prefix(maxCount))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
