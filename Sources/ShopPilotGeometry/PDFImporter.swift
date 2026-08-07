import Foundation
import zlib
import ShopPilotCore

// MARK: - PDF vector importer (Tier-2 import breadth: PDF)

/// Honest lean slice: parses PDF **vector content streams** — the path
/// operators (`m l c v y h re`), painting operators (`S s f F B b`), graphics
/// state (`q Q cm`) and FlateDecode streams — into `VectorShape`s. Text,
/// images, and complex shadings are skipped tolerantly (they're not cuttable
/// vectors anyway). This covers the vast majority of vector logos / line art
/// PDFs exported from Illustrator/CAD without a full PDF interpreter.
public struct PDFImportResult: Codable, Sendable {
    public let shapes: [VectorShape]
    public let pathCount: Int
    public let fileSizeBytes: Int
    public let success: Bool
    public let errorMessage: String?

    public init(
        shapes: [VectorShape],
        pathCount: Int,
        fileSizeBytes: Int,
        success: Bool,
        errorMessage: String?
    ) {
        self.shapes = shapes
        self.pathCount = pathCount
        self.fileSizeBytes = fileSizeBytes
        self.success = success
        self.errorMessage = errorMessage
    }
}

public enum PDFImporterError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case notPDF(String)
    case noContentStreams

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "PDF file not found: \(p)"
        case .unreadable(let m): return "PDF unreadable: \(m)"
        case .notPDF(let m): return "Not a PDF: \(m)"
        case .noContentStreams: return "No vector content streams found in PDF"
        }
    }
}

/// Scoped PDF vector importer. See `PDFImportResult` for the lean slice.
public enum PDFImporter {

    // MARK: - Entry point

    public static func importPDF(at path: String, scale: Double = 1.0) -> PDFImportResult {
        let byteCount = fileSize(at: path) ?? 0
        guard let data = FileManager.default.contents(atPath: path) else {
            return PDFImportResult(shapes: [], pathCount: 0, fileSizeBytes: 0, success: false,
                                   errorMessage: PDFImporterError.fileNotFound(path).errorDescription)
        }
        let head = String(data: data.prefix(1024), encoding: String.Encoding.ascii)
            ?? String(decoding: data.prefix(1024), as: UTF8.self)
        guard data.count >= 5, head.hasPrefix("%PDF") else {
            return PDFImportResult(shapes: [], pathCount: 0, fileSizeBytes: byteCount, success: false,
                                   errorMessage: PDFImporterError.notPDF("missing %PDF header").errorDescription)
        }

        let streams = extractContentStreams(from: data)
        guard !streams.isEmpty else {
            return PDFImportResult(shapes: [], pathCount: 0, fileSizeBytes: byteCount, success: false,
                                   errorMessage: PDFImporterError.noContentStreams.errorDescription)
        }

        var shapes: [VectorShape] = []
        var pathCount = 0
        for stream in streams {
            let parsed = parseContentStream(stream, scale: scale)
            shapes.append(contentsOf: parsed.shapes)
            pathCount += parsed.pathCount
        }
        return PDFImportResult(
            shapes: shapes,
            pathCount: pathCount,
            fileSizeBytes: byteCount,
            success: true,
            errorMessage: nil
        )
    }

    // MARK: - Stream extraction

    /// Pulls every `stream … endstream` blob (FlateDecode-inflated) from the
    /// raw PDF bytes. Operates on raw bytes (binary streams are legal PDFs —
    /// a string scan would corrupt compressed payloads). Object headers are
    /// matched loosely so xref-less hand-written PDFs still work.
    static func extractContentStreams(from data: Data) -> [Data] {
        var out: [Data] = []
        var scanner = PDFScanner(data: data)
        while scanner.skip(upTo: "stream") {
            // Now positioned just after "stream"; skip its EOL.
            scanner.skipEOL()
            // Capture everything up to "endstream" (exclusive).
            guard let payload = scanner.scan(upTo: "endstream") else { break }
            var bytes = payload
            // Strip the trailing EOL before endstream.
            while let last = bytes.last, last == 0x0A || last == 0x0D {
                bytes.removeLast()
            }
            out.append(inflateIfNeeded(Data(bytes)))
        }
        return out
    }

    /// Try FlateDecode (zlib) inflate; return the raw bytes unchanged when the
    /// stream is not compressed (plain content streams are legal). Uses the
    /// REAL system zlib — Apple's `Compression` framework COMPRESSION_ZLIB is
    /// not RFC-1950-interoperable with standard zlib streams (it emits raw
    /// deflate), which is what FlateDecode requires.
    static func inflateIfNeeded(_ data: Data) -> Data {
        // zlib magic: 0x78 0x01 (no/low), 0x78 0x9C (default), 0x78 0xDA (best).
        guard data.count >= 2, data[0] == 0x78,
              data[1] == 0x01 || data[1] == 0x9C || data[1] == 0xDA else {
            return data
        }
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil
        let initRet = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initRet == Z_OK else { return data }

        var srcPtr: UnsafeMutablePointer<UInt8>? = nil
        data.withUnsafeBytes { srcPtr = UnsafeMutablePointer(mutating: $0.bindMemory(to: UInt8.self).baseAddress) }
        var out = [UInt8](repeating: 0, count: max(256, data.count * 24 + 64))
        var dstPtr: UnsafeMutablePointer<UInt8>? = nil
        out.withUnsafeMutableBufferPointer { dstPtr = $0.baseAddress }

        stream.next_in = srcPtr
        stream.avail_in = uInt(data.count)
        stream.next_out = dstPtr
        stream.avail_out = uInt(out.count)
        let r = inflate(&stream, Z_FINISH)
        let produced = out.count - Int(stream.avail_out)
        inflateEnd(&stream)
        guard r == Z_STREAM_END, produced > 0, produced < out.count else { return data }
        return Data(out.prefix(produced))
    }

    static func fileSize(at path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
    }
}
