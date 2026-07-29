import Foundation
#if canImport(ShopPilotCore)
import ShopPilotCore
#endif

// MARK: - FileOperationError

/// Errors that can occur during .shoppilot file operations.
public enum FileOperationError: Error, LocalizedError {
    /// The target file does not exist at the given URL.
    case notFound(URL)
    /// The file contents are not valid JSON or do not match the expected schema.
    case invalidFormat(URL, String)
    /// The JSON was valid but could not be decoded into a Job (corrupted data).
    case decodingFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .notFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .invalidFormat(let url, let reason):
            return "Invalid format in '\(url.lastPathComponent)': \(reason)"
        case .decodingFailed(let url, let error):
            return "Failed to decode '\(url.lastPathComponent)': \(error.localizedDescription)"
        }
    }
}

// MARK: - FileSaver

/// Saves a Job to disk as a .shoppilot file using an atomic write pattern.
///
/// Writes to a temporary `.tmp` file in the same directory, then renames it
/// to the target path. This prevents corruption if the process crashes mid-write.
public enum FileSaver {

    /// Serializes the given Job to JSON and writes it atomically to the specified URL.
    ///
    /// - Parameters:
    ///   - job: The Job document to save.
    ///   - url: The destination file URL (should have a `.shoppilot` extension).
    /// - Throws: FileOperationError if encoding fails or the directory cannot be written.
    public static func save(job: Job, to url: URL) throws {
        // 1. Encode the job to JSON data using ISO-8601 date strategy.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let jsonData: Data

        do {
            jsonData = try encoder.encode(job)
        } catch {
            throw FileOperationError.decodingFailed(url, error)
        }

        // 2. Ensure the parent directory exists.
        let fileManager = FileManager.default
        let directoryURL = url.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // 3. Write to a temporary .tmp file in the same directory (atomic write).
        let tmpFilename = url.lastPathComponent + ".tmp"
        let tmpURL = directoryURL.appendingPathComponent(tmpFilename)

        do {
            try jsonData.write(to: tmpURL, options: .atomic)
        } catch {
            // Clean up partial temp file on failure.
            try? fileManager.removeItem(at: tmpURL)
            throw FileOperationError.invalidFormat(url, "Failed to write temporary file: \(error.localizedDescription)")
        }

        // 4. Rename the temp file to the final destination (atomic on same volume).
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tmpURL, to: url)
        } catch {
            // Clean up temp file if rename fails.
            try? fileManager.removeItem(at: tmpURL)
            throw FileOperationError.invalidFormat(url, "Failed to finalize save: \(error.localizedDescription)")
        }
    }
}

// MARK: - FileLoader

/// Loads a Job from a .shoppilot file on disk.
public enum FileLoader {

    /// Reads JSON from the given URL and decodes it into a Job.
    ///
    /// - Parameter url: The file URL to load (should have a `.shoppilot` extension).
    /// - Throws: FileOperationError.notFound, .invalidFormat, or .decodingFailed.
    public static func load(from url: URL) throws -> Job {
        let fileManager = FileManager.default

        // 1. Check that the file exists.
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileOperationError.notFound(url)
        }

        // 2. Read raw data from disk.
        let rawData: Data
        do {
            rawData = try Data(contentsOf: url)
        } catch {
            throw FileOperationError.invalidFormat(url, "Failed to read file contents: \(error.localizedDescription)")
        }

        // 3. Validate that the data is not empty.
        guard !rawData.isEmpty else {
            throw FileOperationError.invalidFormat(url, "File is empty")
        }

        // 4. Decode JSON into a Job using ISO-8601 date strategy.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(Job.self, from: rawData)
        } catch {
            throw FileOperationError.decodingFailed(url, error)
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct FileOperations_Previews: PreviewProvider {
    static var previews: some View {
        Text("File operations preview requires Xcode Previews")
    }
}
#endif
