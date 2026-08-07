import Foundation
import ShopPilotCore

// MARK: - EPS Import Result

/// Result of importing an EPS file.
public struct EPSImportResult: Codable, Sendable {
    /// The parsed shapes from the EPS (each completed path becomes a `.freehand`).
    public let shapes: [VectorShape]
    /// Number of completed paths that produced a shape (equals `shapes.count`).
    public let pathCount: Int
    /// Size of the source file in bytes.
    public let fileSizeBytes: Int
    /// Whether the import succeeded (file readable + EPS `%!PS` header present).
    public let success: Bool
    /// Human-readable error message when `success` is false.
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

// VectorShape carries only value types (VectorPoint is Sendable, plus Double/Int),
// so it is trivially thread-safe. The explicit conformance lets EPSImportResult
// legitimately be `Sendable` while keeping the exact contract signature.
extension VectorShape: @unchecked Sendable {}

// MARK: - EPS Importer

/// Parses Encapsulated PostScript (EPS) files into vector shapes.
///
/// This is an HONEST MINIMAL SUBSET — not a PostScript interpreter. Supported:
/// - `%%BoundingBox: llx lly urx ury` header (coordinates are offset by llx/lly)
/// - the path operators `moveto` / `lineto` / `curveto` (sampled) / `closepath`
/// - `newpath` as a subpath boundary
///
/// Everything else (`setrgbcolor`, `setlinewidth`, `gsave`/`grestore`, `stroke`,
/// `fill`, `show` text, transforms, relative ops, arcs, …) is skipped gracefully.
/// PostScript is postfix: operands are pushed before the operator, so numbers are
/// consumed only by the supported path operators and stale operands from skipped
/// operators never corrupt the path state.
public enum EPSImporter {

    /// Import an EPS file at the given path.
    ///
    /// - Parameters:
    ///   - path: Filesystem path to the `.eps` file.
    ///   - scale: Uniform scale applied after the BoundingBox offset.
    /// - Returns: An `EPSImportResult`; never throws, never crashes on garbage.
    public static func importEPS(at path: String, scale: Double = 1.0) -> EPSImportResult {
        guard let (content, byteCount) = readFile(at: path) else {
            return EPSImportResult(
                shapes: [], pathCount: 0, fileSizeBytes: fileSize(at: path) ?? 0,
                success: false, errorMessage: "Could not read file at '\(path)'"
            )
        }

        guard !content.isEmpty else {
            return EPSImportResult(
                shapes: [], pathCount: 0, fileSizeBytes: byteCount,
                success: false, errorMessage: "File is empty"
            )
        }

        // Require the EPS/PS magic header so arbitrary text is rejected as garbage.
        guard content.contains("%!PS") else {
            return EPSImportResult(
                shapes: [], pathCount: 0, fileSizeBytes: byteCount,
                success: false, errorMessage: "Not an EPS/PostScript file (missing %!PS header)"
            )
        }

        let bbox = extractBoundingBox(from: content)
        let offsetX = bbox?.minX ?? 0
        let offsetY = bbox?.minY ?? 0

        func mapPoint(_ x: Double, _ y: Double) -> VectorPoint {
            VectorPoint(x: (x - offsetX) * scale, y: (y - offsetY) * scale)
        }

        var shapes: [VectorShape] = []
        var currentPath: [VectorPoint] = []
        var isClosed = false
        var numbers: [Double] = []

        /// Commit the current subpath as a `.freehand` shape. A `closepath`-marked
        /// subpath is closed by appending the start point when it is not already
        /// there, so `first == last` holds and `isClosedShape`/`GeometryBridge`
        /// treat it as a closed loop.
        func flush() {
            if currentPath.count >= 2 {
                if isClosed,
                   let first = currentPath.first, let last = currentPath.last,
                   abs(first.x - last.x) > 1e-9 || abs(first.y - last.y) > 1e-9 {
                    currentPath.append(first)
                }
                shapes.append(VectorShape.freehand(points: currentPath))
            }
            currentPath = []
            isClosed = false
        }

        for token in tokenize(content) {
            switch token {
            case .number(let value):
                numbers.append(value)

            case .word(let word):
                switch word.lowercased() {
                case "moveto":
                    guard numbers.count >= 2 else { numbers = []; continue }
                    let y = numbers.removeLast()
                    let x = numbers.removeLast()
                    flush()
                    currentPath = [mapPoint(x, y)]
                    isClosed = false

                case "lineto":
                    guard numbers.count >= 2 else { numbers = []; continue }
                    let y = numbers.removeLast()
                    let x = numbers.removeLast()
                    currentPath.append(mapPoint(x, y))

                case "curveto":
                    guard numbers.count >= 6 else { numbers = []; continue }
                    let y3 = numbers.removeLast()
                    let x3 = numbers.removeLast()
                    let y2 = numbers.removeLast()
                    let x2 = numbers.removeLast()
                    let y1 = numbers.removeLast()
                    let x1 = numbers.removeLast()
                    let start = currentPath.last ?? VectorPoint()
                    let curve = sampleCubic(
                        from: start,
                        cp1: mapPoint(x1, y1),
                        cp2: mapPoint(x2, y2),
                        to: mapPoint(x3, y3),
                        segments: 16
                    )
                    currentPath.append(contentsOf: curve.dropFirst())

                case "closepath":
                    isClosed = true

                case "newpath":
                    flush()

                default:
                    // Any other PostScript operator: its operands (if any) are
                    // stale here — drop them so they cannot feed a later path op.
                    numbers = []
                }
            }
        }
        flush()

        return EPSImportResult(
            shapes: shapes,
            pathCount: shapes.count,
            fileSizeBytes: byteCount,
            success: true,
            errorMessage: nil
        )
    }

    // MARK: - Bounding Box

    private static func extractBoundingBox(
        from content: String
    ) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        let pattern = #"%%BoundingBox:\s*([-+]?(?:\d+\.?\d*|\.\d+))\s+([-+]?(?:\d+\.?\d*|\.\d+))\s+([-+]?(?:\d+\.?\d*|\.\d+))\s+([-+]?(?:\d+\.?\d*|\.\d+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range) else { return nil }
        func value(at idx: Int) -> Double? {
            guard let r = Range(match.range(at: idx), in: content) else { return nil }
            return Double(String(content[r]))
        }
        guard let minX = value(at: 1), let minY = value(at: 2),
              let maxX = value(at: 3), let maxY = value(at: 4) else { return nil }
        return (minX, minY, maxX, maxY)
    }

    // MARK: - File IO

    private static func readFile(at path: String) -> (content: String, bytes: Int)? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) {
            return (utf8, data.count)
        }
        // Latin-1 maps every byte 1:1, so non-UTF8 legacy EPS still parses;
        // the path operators we care about are ASCII anyway.
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return (latin1, data.count)
        }
        return nil
    }

    private static func fileSize(at path: String) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.intValue
    }

    // MARK: - Tokenizer

    private enum Token {
        case number(Double)
        case word(String)
    }

    /// Tokenize EPS text: splits on whitespace, skips `%` comments and
    /// parenthesized string literals, and classifies each chunk as a number
    /// or a word.
    private static func tokenize(_ content: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inComment = false
        var inString = false
        var escaped = false

        func flushChunk() {
            guard !current.isEmpty else { return }
            if let value = Double(current) {
                tokens.append(.number(value))
            } else {
                tokens.append(.word(current))
            }
            current = ""
        }

        for ch in content {
            if inComment {
                if ch == "\n" || ch == "\r" { inComment = false }
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                } else if ch.asciiValue == 92 {
                    escaped = true
                } else if ch == ")" {
                    inString = false
                }
                continue
            }
            if ch == "%" {
                flushChunk()
                inComment = true
                continue
            }
            if ch == "(" {
                flushChunk()
                inString = true
                continue
            }
            if ch.isWhitespace {
                flushChunk()
            } else {
                current.append(ch)
            }
        }
        flushChunk()
        return tokens
    }

    // MARK: - Curve sampling

    /// Approximate a cubic Bezier with `segments` line segments (16 by default),
    /// returning `segments + 1` points including the start point.
    private static func sampleCubic(
        from start: VectorPoint, cp1: VectorPoint, cp2: VectorPoint, to end: VectorPoint,
        segments: Int = 16
    ) -> [VectorPoint] {
        var points: [VectorPoint] = [start]
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let mt = 1.0 - t
            let mt2 = mt * mt, mt3 = mt2 * mt
            let t2 = t * t, t3 = t2 * t
            let x = mt3 * start.x + 3 * mt2 * t * cp1.x + 3 * mt * t2 * cp2.x + t3 * end.x
            let y = mt3 * start.y + 3 * mt2 * t * cp1.y + 3 * mt * t2 * cp2.y + t3 * end.y
            points.append(VectorPoint(x: x, y: y))
        }
        return points
    }
}
