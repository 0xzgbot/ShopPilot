import Foundation

// MARK: - Recent files store (SPK-1209)

/// Persistent list of recently imported files (UserDefaults JSON, capped,
/// deduped by path). The Import hub's "Recent" rail shows these for
/// one-click re-import — the pain point: re-importing a file you just
/// worked with means re-navigating the picker.
public final class RecentFilesStore: ObservableObject {

    public struct RecentFile: Codable, Identifiable, Equatable, Sendable {
        public let url: URL
        public let importedAt: Date

        public var id: String { url.path }

        public init(url: URL, importedAt: Date = Date()) {
            self.url = url
            self.importedAt = importedAt
        }
    }

    @Published public private(set) var recent: [RecentFile]

    /// Cap on retained entries.
    public let capacity: Int

    private let defaults: UserDefaults
    private static let storageKey = "shop_pilot_recent_imports_v1"

    public init(defaults: UserDefaults = .standard, capacity: Int = 10) {
        self.defaults = defaults
        self.capacity = max(1, capacity)
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) {
            self.recent = decoded
        } else {
            self.recent = []
        }
    }

    /// Record an import: dedupe by path, bump to front, cap the list.
    public func record(_ url: URL) {
        recent.removeAll { $0.url.path == url.path }
        recent.insert(RecentFile(url: url), at: 0)
        if recent.count > capacity {
            recent = Array(recent.prefix(capacity))
        }
        save()
    }

    /// Drop an entry (e.g. the file was deleted).
    public func remove(url: URL) {
        recent.removeAll { $0.url.path == url.path }
        save()
    }

    public func clear() {
        recent.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
