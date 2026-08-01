// FileUtilities — shared file operations for ShopPilot documents

import Foundation

/// Errors that can occur during file operations.
public enum FileError: Error, LocalizedError {
    case fileNotFound(URL)
    case fileInUse(URL)
    case cannotCreate(URL)
    case cannotWrite(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .fileInUse(let url):
            return "File is in use and cannot be opened for writing: \(url.lastPathComponent)"
        case .cannotCreate(let url):
            return "Could not create file at: \(url.path)"
        case .cannotWrite(let url):
            return "Cannot write to file: \(url.lastPathComponent)"
        }
    }
}

/// Utility functions for ShopPilot document file operations.
public struct FileUtilities {

    /// The file extension used by ShopPilot documents.
    public static let documentExtension = "shoppilot"

    // MARK: - Document validation

    /// Returns true if the given URL points to a file with a `.shoppilot` extension.
    public static func isValidDocumentFile(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == documentExtension
    }

    // MARK: - URL generation

    /// Returns a URL for a new document in the given directory, using the
    /// default name "Untitled.shoppilot".
    public static func createDefaultDocumentURL(in directory: URL) -> URL {
        return directory.appendingPathComponent("Untitled").appendingPathExtension(documentExtension)
    }

    /// Generates a URL with a unique filename in the given directory.
    /// If a file with `base.ext` already exists, appends an incrementing
    /// number (e.g. "document.shoppilot", "document 1.shoppilot", etc.).
    public static func generateUniqueFileName(
        base: String,
        in directory: URL,
        extension: String
    ) -> URL {
        let url = directory.appendingPathComponent(base).appendingPathExtension(`extension`)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }

        var counter = 1
        while true {
            let candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(`extension`)
            guard !FileManager.default.fileExists(atPath: candidate.path) else {
                counter += 1
                continue
            }
            return candidate
        }
    }

    // MARK: - Formatting

    /// Returns a human-readable file size string, e.g. "1.5 MB", "2.3 KB", "512 B".
    public static func fileSizePretty(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var index = 0

        while size >= 1024.0 && index < units.count - 1 {
            size /= 1024.0
            index += 1
        }

        if size == Double(Int(size)) {
            return "\(Int(size)) \(units[index])"
        } else if index == 0 {
            return "\(Int(size)) \(units[index])"
        } else {
            return String(format: "%.1f %s", size, units[index])
        }
    }

    // MARK: - File availability

    /// Returns true if the file at the given URL cannot be opened for writing
    /// (i.e. it is likely in use by another process).
    public static func isFileInUse(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.close()
            return false
        } catch {
            return true
        }
    }

    // MARK: - Directory creation

    /// Creates the directory at the given URL (and any parent directories) if it
    /// does not already exist. Returns true if the directory was created or
    /// already exists, false on failure.
    public static func createDirectoryIfNotExists(_ url: URL) -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return true
        }

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return true
        } catch {
            return false
        }
    }
}
