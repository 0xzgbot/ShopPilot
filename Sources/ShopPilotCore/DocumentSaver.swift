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
    
    /// Save a Job to the specified URL as a `.shoppilot` package.
    /// The package is a directory bundle containing manifest.json and sheets/ subdirectory.
    public func save(_ job: Job, to url: URL) throws {
        let packageURL = ensurePackageDirectory(at: url)
        
        // Write manifest
        try writeManifest(job, to: packageURL)
        
        // Write each sheet as a separate JSON file
        let sheetsDir = packageURL.appendingPathComponent("sheets")
        for sheet in job.sheets {
            let sheetData = try JSONEncoder().encode(sheet)
            let sheetFile = sheetsDir.appendingPathComponent("\(sheet.id.uuidString).json")
            try sheetData.write(to: sheetFile, options: .atomic)
        }
        
        // Update the job's updatedAt timestamp
        var mutableJob = job
        mutableJob.updatedAt = .now
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
        
        // Create sheets subdirectory
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
    
    /// Write the manifest.json file for a Job.
    private func writeManifest(_ job: Job, to packageURL: URL) throws {
        let manifest = [
            "id": job.id.uuidString,
            "name": job.name,
            "createdAt": job.createdAt.iso8601String(),
            "updatedAt": job.updatedAt.iso8601String(),
            "version": "0.1",
            "sheetCount": job.sheets.count
        ] as [String: Any]
        
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
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
