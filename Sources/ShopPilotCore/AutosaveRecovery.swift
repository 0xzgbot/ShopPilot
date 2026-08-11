import Foundation

// MARK: - Autosave Recovery

/// A single autosaved package found on disk by `AutosaveRecovery.scan`.
public struct RecoverySnapshot: Equatable, Sendable {
    /// Location of the autosaved `.shoppilot` package.
    public let url: URL
    /// Last modification date of the package (newest first in scan results).
    public let modifiedAt: Date

    public init(url: URL, modifiedAt: Date) {
        self.url = url
        self.modifiedAt = modifiedAt
    }
}

/// Recovery surface for autosaved `.shoppilot` packages: find, list, and clear
/// unsaved work so the app can offer "Recover unsaved work?" on launch.
public enum AutosaveRecovery {

    /// The directory autosaves live in: Application Support/ShopPilot/Autosave.
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ShopPilot/Autosave", isDirectory: true)
    }

    /// List every `.shoppilot` file in `directory` (default `defaultDirectory()`),
    /// sorted newest first by modification date. Missing/non-existent directory → `[]`.
    public static func scan(directory: URL? = nil) -> [RecoverySnapshot] {
        let dir = directory ?? defaultDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        let snapshots = urls.compactMap { url -> RecoverySnapshot? in
            guard url.pathExtension == "shoppilot" else { return nil }
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? .distantPast
            return RecoverySnapshot(url: url, modifiedAt: modifiedAt)
        }

        return snapshots.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
    }

    /// The most recent snapshot — the first of an already newest-first array.
    public static func latest(in snapshots: [RecoverySnapshot]) -> RecoverySnapshot? {
        snapshots.first
    }

    /// Delete every `.shoppilot` file in `directory` (default `defaultDirectory()`);
    /// returns the number deleted. Missing directory → 0.
    public static func clear(directory: URL? = nil) -> Int {
        scan(directory: directory).reduce(into: 0) { count, snapshot in
            if (try? FileManager.default.removeItem(at: snapshot.url)) != nil {
                count += 1
            }
        }
    }

    /// Set a file's modification date (used after a successful autosave so
    /// `scan()` sees freshness). Returns false if the file doesn't exist.
    @discardableResult
    public static func markTouched(_ url: URL, at date: Date = Date()) -> Bool {
        (try? FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )) != nil
    }
}
