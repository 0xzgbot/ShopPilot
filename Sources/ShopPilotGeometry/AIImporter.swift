import Foundation
import ShopPilotCore

// MARK: - Adobe Illustrator (AI) importer (Tier-2 import breadth: AI)

/// Adobe Illustrator files are containers: classic AI = EPS (PostScript with
/// `%!PS-Adobe` header + `%%BoundingBox`), modern AI = PDF with embedded
/// vector content streams (`%PDF`). This importer detects the flavor from the
/// magic bytes and dispatches to the corresponding engine, so one import path
/// covers both generations.
public struct AIImportResult: Codable, Sendable {
    public let shapes: [VectorShape]
    public let pathCount: Int
    public let fileSizeBytes: Int
    public let flavor: String   // "EPS" or "PDF"
    public let success: Bool
    public let errorMessage: String?

    public init(
        shapes: [VectorShape],
        pathCount: Int,
        fileSizeBytes: Int,
        flavor: String,
        success: Bool,
        errorMessage: String?
    ) {
        self.shapes = shapes
        self.pathCount = pathCount
        self.fileSizeBytes = fileSizeBytes
        self.flavor = flavor
        self.success = success
        self.errorMessage = errorMessage
    }
}

public enum AIImporterError: Error, LocalizedError {
    case fileNotFound(String)
    case notAI(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "AI file not found: \(p)"
        case .notAI(let m): return "Not an Illustrator file: \(m)"
        }
    }
}

public enum AIImporter {

    /// Detect EPS vs PDF flavor and delegate. EPS result shapes come back
    /// directly; PDF result shapes are re-wrapped with the AI flavor tag.
    public static func importAI(at path: String, scale: Double = 1.0) -> AIImportResult {
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        guard let data = FileManager.default.contents(atPath: path) else {
            return AIImportResult(shapes: [], pathCount: 0, fileSizeBytes: 0, flavor: "",
                                  success: false, errorMessage: AIImporterError.fileNotFound(path).errorDescription)
        }
        guard data.count >= 8,
              let head = String(data: data.prefix(1024), encoding: .ascii) else {
            return AIImportResult(shapes: [], pathCount: 0, fileSizeBytes: byteCount, flavor: "",
                                  success: false, errorMessage: AIImporterError.notAI("unreadable header").errorDescription)
        }

        if head.hasPrefix("%PDF") {
            let pdf = PDFImporter.importPDF(at: path, scale: scale)
            return AIImportResult(shapes: pdf.shapes, pathCount: pdf.pathCount,
                                  fileSizeBytes: byteCount, flavor: "PDF",
                                  success: pdf.success, errorMessage: pdf.errorMessage)
        }
        if head.hasPrefix("%!PS-Adobe") {
            let eps = EPSImporter.importEPS(at: path, scale: scale)
            return AIImportResult(shapes: eps.shapes, pathCount: eps.pathCount,
                                  fileSizeBytes: byteCount, flavor: "EPS",
                                  success: eps.success, errorMessage: eps.errorMessage)
        }
        return AIImportResult(shapes: [], pathCount: 0, fileSizeBytes: byteCount, flavor: "",
                              success: false,
                              errorMessage: AIImporterError.notAI("expected %PDF or %!PS-Adobe header").errorDescription)
    }
}
