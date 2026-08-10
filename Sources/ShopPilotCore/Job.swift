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

    /// V-Carve pass count from the last toolpath calculation.
    public var vcarvePasses: Int = 0

    /// V-Carve estimated time in seconds.
    public var vcarveTimeSeconds: Double = 0.0

    /// Precomputed V-Carve G-code for the sign recipe's text (SPK-1106a).
    /// Set by `SignRecipeManager.createSignJob`; `replaceJob` materializes
    /// it into the session toolpath tree. Optional → older documents decode
    /// unchanged.
    public var vcarveGCode: [String]?
    /// V-Carve params used for the precomputed pass (JSON-encoded), so the
    /// tree node carries the same configuration the recipe used.
    public var vcarveParamsJSON: String?

    /// SPK-3D-spine-a — imported STL relief as a heightfield grid. Optional →
    /// older documents decode unchanged (synthesized Codable).
    public var stlHeightfield: HeightfieldData?

    /// SPK-0700/0701 lean slice — the document's relief component stack.
    /// Each component holds a heightfield + combine mode; the compositor
    /// folds them into the ACTIVE relief (`stlHeightfield`). Optional →
    /// older documents decode unchanged. When nil/empty, `stlHeightfield`
    /// is used directly (single-relief docs behave exactly as before).
    public var reliefComponents: [ReliefComponent]?

    /// SPK-0319 lite — persisted Follow-source mode ("manual" | "autoFollow").
    /// Optional → older documents decode unchanged.
    public var followSourceModeRaw: String?

    /// Keep-out zones for this document (SPK-0308): toolpaths must not enter
    /// active zones. Optional + legacy-safe — documents saved before zones
    /// existed decode as nil (no zones).
    public var keepOutZones: [KeepOutZone]?

    /// Document-level variables (key-value pairs for stock size, material, etc.).
    public var documentVariables: [DocumentVariable] = []

    /// Driven (computed) dimensions whose values are derived from expressions.
    public var drivenDimensions: [DrivenDimension] = []

    /// SPK-0800 — the sheet id the session's design surface + toolpaths last
    /// targeted (restored on open so the document reopens on the same sheet).
    /// Optional + legacy-safe — older documents decode nil (first sheet).
    public var activeSheetID: UUID?

    /// SPK-0801 — double-sided job configuration (front/back sheet pairing,
    /// registration alignment, back-side Z offset/flip/rotation). Optional +
    /// legacy-safe — single-sided documents decode nil.
    public var doubleSidedConfig: DoubleSidedJobConfig?

    /// Whether this document is a double-sided job.
    public var isDoubleSided: Bool { doubleSidedConfig != nil }

    /// SPK-0903 — job-level rotary setup: stock diameter + axis length for
    /// rotary machining. Optional + legacy-safe; rotary wrap/fluting ops read
    /// it as their stock Ø default (per-op params still override).
    public var rotaryConfig: RotaryConfig?

    /// UI-polish cluster — persisted vector groups as index lists into the
    /// sheet's vector order (one entry per group). Optional + legacy-safe:
    /// documents saved before grouping existed decode as nil (no groups).
    /// Indices are validated against the shape count on load
    /// (`ShapeGroupEngine.sanitized`), so stale indices never crash.
    public var shapeGroups: [[Int]]?

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

    /// Evaluate a single driven dimension, returning its computed value.
    ///
    /// - Parameter dim: The driven dimension to evaluate.
    /// - Returns: The computed `Double`, or `nil` if the expression cannot be resolved.
    public func evaluateDrivenDimension(_ dim: DrivenDimension) -> Double? {
        return DrivenDimensionResolver.resolve(
            expression: dim.expression,
            variables: documentVariables
        )
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
