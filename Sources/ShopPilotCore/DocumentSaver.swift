import Foundation

// MARK: - Document Saver

/// Saves a Job to a `.shoppilot` package directory bundle.
public struct DocumentSaver {

    /// The file manager used for I/O operations.
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Save

    /// Save a full package payload (job + toolpaths) to the specified URL.
    public func save(_ payload: ShopPilotPackagePayload, to url: URL) throws {
        let packageURL = ensurePackageDirectory(at: url)

        try writeManifest(payload.job, to: packageURL)
        try writeToolpaths(payload.toolpaths, to: packageURL)

        let sheetsDir = packageURL.appendingPathComponent("sheets")
        for sheet in payload.job.sheets {
            let sheetData = try JSONEncoder().encode(sheet)
            let sheetFile = sheetsDir.appendingPathComponent("\(sheet.id.uuidString).json")
            try sheetData.write(to: sheetFile, options: .atomic)
        }
    }

    /// Save a Job to the specified URL as a `.shoppilot` package (no toolpaths).
    public func save(_ job: Job, to url: URL) throws {
        try save(ShopPilotPackagePayload(job: job), to: url)
    }

    /// Ensure a `.shoppilot` package directory exists at the given URL.
    private func ensurePackageDirectory(at url: URL) -> URL {
        let packageURL = url.pathExtension == "shoppilot" ? url : url.appendingPathExtension("shoppilot")

        if !fileManager.fileExists(atPath: packageURL.path) {
            try? fileManager.createDirectory(
                at: packageURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let sheetsDir = packageURL.appendingPathComponent("sheets")
        if !fileManager.fileExists(atPath: sheetsDir.path) {
            try? fileManager.createDirectory(
                at: sheetsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return packageURL
    }

    /// Write the manifest.json file for a Job (includes document variables).
    private func writeManifest(_ job: Job, to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let varsData = try encoder.encode(job.documentVariables)
        let varsJSON = try JSONSerialization.jsonObject(with: varsData)

        let manifest: [String: Any] = [
            "id": job.id.uuidString,
            "name": job.name,
            "createdAt": job.createdAt.iso8601String(),
            "updatedAt": Date.now.iso8601String(),
            "version": "0.2",
            "sheetCount": job.sheets.count,
            "documentVariables": varsJSON,
        ]

        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    private func writeToolpaths(_ toolpaths: [PersistedToolpath], to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(toolpaths)
        let toolpathsURL = packageURL.appendingPathComponent("toolpaths.json")
        try data.write(to: toolpathsURL, options: .atomic)
    }
}

// MARK: - Date Extension for ISO8601 String Conversion

extension Date {
    /// Convert a Date to an ISO 8601 string.
    func iso8601String() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct DocumentSaver_Previews: PreviewProvider {
    static var previews: some View {
        Text("Document saver is a non-visual component")
    }
}
#endif
