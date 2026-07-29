import Foundation

// MARK: - Job

/// Top-level document representing a CNC job.
/// A job contains one or more sheets (single-sided, double-sided, rotary).
public struct Job: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var sheets: [Sheet]
    public let createdAt: Date
    public var updatedAt: Date

    /// Whether the job has unsaved changes.
    public var isDirty: Bool { false } // Managed by DirtyDocument protocol

    public init(
        id: UUID = UUID(),
        name: String = "Untitled Job",
        sheets: [Sheet] = []
    ) {
        self.id = id
        self.name = name
        self.sheets = sheets
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// Add a sheet to this job.
    public mutating func addSheet(_ sheet: Sheet) {
        sheets.append(sheet)
        updatedAt = .now
    }

    /// Remove a sheet by ID.
    @discardableResult
    public mutating func removeSheet(id: UUID) -> Bool {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else { return false }
        sheets.remove(at: index)
        updatedAt = .now
        return true
    }

    /// Convenience: first sheet, or create one.
    public mutating func ensureSingleSheet() -> Sheet {
        if let existing = sheets.first {
            return existing
        }
        let newSheet = Sheet(name: "Sheet 1")
        addSheet(newSheet)
        return newSheet
    }
}

// MARK: - Job Persistence

extension Job {
    /// Encode job to JSON Data for .shoppilot native format.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decode job from JSON Data.
    public static func decode(_ data: Data) throws -> Job {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Job.self, from: data)
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct Job_Previews: PreviewProvider {
    static var previews: some View {
        Text("Job preview requires Xcode Previews")
    }
}
#endif
