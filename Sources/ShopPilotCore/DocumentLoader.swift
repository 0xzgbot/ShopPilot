import Foundation

// MARK: - Document Loader

/// Loads a Job from a `.shoppilot` package directory bundle.
public struct DocumentLoader {

    /// The file manager used for I/O operations.
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Load

    /// Load the full package payload from the specified URL.
    public func loadPayload(from url: URL) throws -> ShopPilotPackagePayload {
        let packageURL = url.pathExtension == "shoppilot" ? url : url.appendingPathExtension("shoppilot")

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw DocumentError.notAValidPackage(packageURL)
        }

        let jobMetadata = try readManifest(from: packageURL)
        let loadedSheets = try loadSheets(from: packageURL)
        let toolpaths = try loadToolpaths(from: packageURL)

        var job = Job(id: jobMetadata.id, name: jobMetadata.name, sheets: loadedSheets)
        job.documentVariables = jobMetadata.documentVariables

        return ShopPilotPackagePayload(job: job, toolpaths: toolpaths)
    }

    /// Load a Job from the specified URL (a `.shoppilot` package directory).
    public func load(from url: URL) throws -> Job {
        try loadPayload(from: url).job
    }

    private func loadSheets(from packageURL: URL) throws -> [Sheet] {
        let sheetsDir = packageURL.appendingPathComponent("sheets")
        var sheetsIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sheetsDir.path, isDirectory: &sheetsIsDir),
              sheetsIsDir.boolValue else {
            throw DocumentError.missingSheetsDirectory(packageURL)
        }

        var loadedSheets: [Sheet] = []
        let enumerator = fileManager.enumerator(at: sheetsDir, includingPropertiesForKeys: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "json" else { continue }

            let data = try Data(contentsOf: fileURL)
            do {
                let sheet = try JSONDecoder().decode(Sheet.self, from: data)
                loadedSheets.append(sheet)
            } catch {
                continue
            }
        }

        return loadedSheets
    }

    private func loadToolpaths(from packageURL: URL) throws -> [PersistedToolpath] {
        let toolpathsURL = packageURL.appendingPathComponent("toolpaths.json")
        guard fileManager.fileExists(atPath: toolpathsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: toolpathsURL)
        return try JSONDecoder().decode([PersistedToolpath].self, from: data)
    }

    /// Read the manifest.json file and extract job metadata.
    private func readManifest(from packageURL: URL) throws -> (
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        documentVariables: [DocumentVariable]
    ) {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw DocumentError.missingManifest(packageURL)
        }

        let data = try Data(contentsOf: manifestURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentError.invalidManifestFormat
        }

        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = json["name"] as? String,
              let createdAtStr = json["createdAt"] as? String,
              let updatedAtStr = json["updatedAt"] as? String else {
            throw DocumentError.missingManifestFields
        }

        let dateFormatter = ISO8601DateFormatter()
        let createdAt = dateFormatter.date(from: createdAtStr) ?? .now
        let updatedAt = dateFormatter.date(from: updatedAtStr) ?? .now

        var documentVariables: [DocumentVariable] = []
        if let varsArray = json["documentVariables"] {
            let varsData = try JSONSerialization.data(withJSONObject: varsArray)
            let decoder = JSONDecoder()
            documentVariables = (try? decoder.decode([DocumentVariable].self, from: varsData)) ?? []
        }

        return (id, name, createdAt, updatedAt, documentVariables)
    }
}

// MARK: - Document Error

public enum DocumentError: LocalizedError {
    case notAValidPackage(URL)
    case missingManifest(URL)
    case invalidManifestFormat
    case missingManifestFields
    case missingSheetsDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .notAValidPackage(let url):
            return "Not a valid ShopPilot package: \(url.path)"
        case .missingManifest(let url):
            return "Missing manifest.json in package: \(url.path)"
        case .invalidManifestFormat:
            return "Invalid manifest format — expected JSON object"
        case .missingManifestFields:
            return "Manifest missing required fields (id, name, createdAt, updatedAt)"
        case .missingSheetsDirectory(let url):
            return "Missing sheets/ directory in package: \(url.path)"
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct DocumentLoader_Previews: PreviewProvider {
    static var previews: some View {
        Text("Document loader is a non-visual component")
    }
}
#endif
