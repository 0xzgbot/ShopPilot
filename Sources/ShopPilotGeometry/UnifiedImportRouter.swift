import Foundation
import ShopPilotCore

// MARK: - Unified import router (SPK-0216)

/// One entry point for every vector import format the app supports.
/// Dispatches by file extension to the format-specific importer, so the
/// Import Hub UI (and any future callers) never switches on format
/// themselves. Binary formats (PDF/DWG/AI) are read as raw data by their
/// importers; text formats are read as UTF-8.
public enum UnifiedImportRouter {

    public enum Format: String, CaseIterable, Sendable {
        case svg, dxf, eps, pdf, ai, dwg

        /// Extensions (lowercased, no dot) that route to this format.
        public var extensions: [String] {
            switch self {
            case .svg: return ["svg"]
            case .dxf: return ["dxf"]
            case .eps: return ["eps"]
            case .pdf: return ["pdf"]
            case .ai: return ["ai"]
            case .dwg: return ["dwg"]
            }
        }

        public var displayName: String {
            switch self {
            case .svg: return "SVG"
            case .dxf: return "DXF"
            case .eps: return "EPS"
            case .pdf: return "PDF"
            case .ai: return "AI"
            case .dwg: return "DWG"
            }
        }

        public static func from(extension ext: String) -> Format? {
            let lower = ext.lowercased()
            return allCases.first { $0.extensions.contains(lower) }
        }
    }

    public struct Result: Sendable {
        public let format: Format
        public let shapes: [VectorShape]
        public let warnings: [String]
        public init(format: Format, shapes: [VectorShape], warnings: [String]) {
            self.format = format
            self.shapes = shapes
            self.warnings = warnings
        }
    }

    public enum ImportError: Error, LocalizedError {
        case unsupportedExtension(String)
        case readFailed(String)
        case parseFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext): return "Unsupported file extension: \(ext)"
            case .readFailed(let msg): return "Failed to read file: \(msg)"
            case .parseFailed(let msg): return "Import failed: \(msg)"
            }
        }
    }

    /// Import vectors from a file, dispatching on its extension.
    public static func importFile(at url: URL) -> Result {
        let ext = url.pathExtension
        guard let format = Format.from(extension: ext) else {
            return Result(format: .svg, shapes: [], warnings: ["Unsupported file extension: \(ext)"])
        }
        return importFile(at: url, format: format)
    }

    /// Import vectors from a file, forcing a format (the hub's picker mode).
    public static func importFile(at url: URL, format: Format) -> Result {
        switch format {
        case .svg:
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return Result(format: format, shapes: [], warnings: ["Failed to read SVG"])
            }
            let parsed = SVGImporter.parse(content)
            return Result(format: format, shapes: parsed.shapes,
                          warnings: parsed.errors.isEmpty ? [] : parsed.errors)

        case .dxf:
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return Result(format: format, shapes: [], warnings: ["Failed to read DXF"])
            }
            let parsed = DXFParser.parse(content)
            return Result(format: format, shapes: parsed.shapes,
                          warnings: parsed.errors.isEmpty ? [] : ["Some entities were skipped or malformed"])

        case .eps:
            let result = EPSImporter.importEPS(at: url.path)
            return Result(format: format, shapes: result.shapes,
                          warnings: result.success ? [] : [result.errorMessage ?? "EPS import failed"])

        case .pdf:
            let result = PDFImporter.importPDF(at: url.path)
            return Result(format: format, shapes: result.shapes,
                          warnings: result.success ? [] : [result.errorMessage ?? "PDF import failed"])

        case .ai:
            let result = AIImporter.importAI(at: url.path)
            return Result(format: format, shapes: result.shapes,
                          warnings: result.success ? [] : [result.errorMessage ?? "AI import failed"])

        case .dwg:
            let result = DWGImporter.importDWG(at: url.path)
            return Result(format: format, shapes: result.shapes,
                          warnings: result.success ? [] : [result.errorMessage ?? "DWG import failed"])
        }
    }
}
