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
    
    /// Load a Job from the specified URL (a `.shoppilot` package directory).
    public func load(from url: URL) throws -> Job {
        let packageURL = url.pathExtension == "shoppilot" ? url : url.appendingPathExtension("shoppilot")
        
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw DocumentError.notAValidPackage(packageURL)
        }
        
        // Read manifest for job metadata
        let jobMetadata = try readManifest(from: packageURL)
        
        // Read all sheets from the sheets/ subdirectory
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
                // Skip malformed sheet files rather than failing the entire load
                continue
            }
        }
        
        // Return job with loaded sheets
        return Job(id: jobMetadata.id, name: jobMetadata.name, sheets: loadedSheets)
    }
    
    /// Read the manifest.json file and extract job metadata.
    private func readManifest(from packageURL: URL) throws -> (id: UUID, name: String, createdAt: Date, updatedAt: Date) {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw DocumentError.missingManifest(packageURL)
        }
        
        let data = try Data(contentsOf: manifestURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentError.invalidManifestFormat
        }
        
        // Parse fields from manifest
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
        
        return (id, name, createdAt, updatedAt)
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
