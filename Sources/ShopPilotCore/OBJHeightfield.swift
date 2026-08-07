import Foundation

// MARK: - OBJ Heightfield Importer

/// SPK-3D-spine-a — ASCII Wavefront OBJ → heightfield (top surface) importer.
/// Mirrors `STLHeightfieldImporter`: same result shape, same grid math
/// (reuses its rasterizer), tolerant parsing of `v`/`f` records.
public struct OBJHeightfieldResult: Sendable {
    public let heightfield: HeightfieldData?
    public let triangleCount: Int
    /// Number of `v` vertex records parsed.
    public let vertexCount: Int
    /// Number of valid `f` face records parsed (before fan triangulation).
    public let faceCount: Int
    public let fileSizeBytes: Int64
    public let success: Bool
    public let errorMessage: String?
}

public enum OBJHeightfieldError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case binaryNotSupported
    case notOBJ(String)
    case noFaces(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "OBJ file not found: \(p)"
        case .unreadable(let m): return "OBJ unreadable: \(m)"
        case .binaryNotSupported: return "Binary input is not a supported OBJ — export ASCII Wavefront OBJ"
        case .notOBJ(let m): return "Not a recognized ASCII OBJ file: \(m)"
        case .noFaces(let m): return "OBJ contains no valid faces: \(m)"
        }
    }
}

public enum OBJHeightfieldImporter {

    // MARK: - Public entry

    /// Import an ASCII Wavefront OBJ and rasterize its top surface onto a
    /// heightfield grid. Never throws and never crashes: failures are reported
    /// through `success` / `errorMessage` (mirroring STLHeightfieldImporter).
    public static func importOBJ(
        at path: String,
        cellSizeMm: Double = 1.0,
        scale: Double = 1.0
    ) -> OBJHeightfieldResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return OBJHeightfieldResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, faceCount: 0, fileSizeBytes: 0,
                success: false, errorMessage: OBJHeightfieldError.fileNotFound(path).localizedDescription
            )
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard !data.contains(0) else {
                throw OBJHeightfieldError.binaryNotSupported
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw OBJHeightfieldError.notOBJ("not valid UTF-8 text")
            }
            let parsed = try parseASCII(text: text)
            guard !parsed.triangles.isEmpty else {
                throw OBJHeightfieldError.noFaces("\(parsed.faceCount) faces / \(parsed.vertexCount) vertices parsed")
            }
            // Same grid math as the STL importer (identical rasterizer).
            let grid = STLHeightfieldImporter.rasterize(
                triangles: parsed.triangles, cellSizeMm: cellSizeMm, scale: scale
            )
            return OBJHeightfieldResult(
                heightfield: grid, triangleCount: parsed.triangles.count,
                vertexCount: parsed.vertexCount, faceCount: parsed.faceCount,
                fileSizeBytes: fileSize, success: true, errorMessage: nil
            )
        } catch let e as OBJHeightfieldError {
            return OBJHeightfieldResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, faceCount: 0,
                fileSizeBytes: fileSize, success: false, errorMessage: e.localizedDescription
            )
        } catch {
            return OBJHeightfieldResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, faceCount: 0,
                fileSizeBytes: fileSize, success: false,
                errorMessage: OBJHeightfieldError.unreadable(error.localizedDescription).localizedDescription
            )
        }
    }

    // MARK: - ASCII parsing

    public struct ParseResult {
        public let triangles: [STLHeightfieldImporter.Triangle]
        public let vertexCount: Int
        public let faceCount: Int
    }

    /// Parse ASCII Wavefront OBJ: `v x y z` vertex records and `f` face records.
    /// Face indices accept `i`, `i/j/k`, `i//k` and `i/j` forms (1-based, or
    /// negative = relative to the current vertex count). Faces with 3+ vertices
    /// are fan-triangulated. Tolerant of CRLF, comments, leading whitespace,
    /// and unknown records (`vt`, `vn`, `o`, `g`, `s`, `usemtl`, `mtllib` …).
    public static func parseASCII(text: String) throws -> ParseResult {
        var verts: [(Double, Double, Double)] = []
        var triangles: [STLHeightfieldImporter.Triangle] = []
        var faceCount = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine
            // Belt-and-suspenders: drop a stray trailing CR if one survived.
            if line.last == "\r" { line = line.dropLast() }
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = tokens.first else { continue }

            switch keyword {
            case "v":
                guard tokens.count >= 4,
                      let x = Double(tokens[1]), let y = Double(tokens[2]), let z = Double(tokens[3]) else {
                    continue
                }
                verts.append((x, y, z))

            case "f":
                guard tokens.count >= 4 else { continue }
                var indices: [Int] = []
                var valid = true
                for tok in tokens.dropFirst() {
                    // Take the vertex index (first '/' component).
                    guard let comp = tok.split(separator: "/").first, let raw = Int(comp) else {
                        valid = false
                        break
                    }
                    let resolved: Int
                    if raw > 0 {
                        resolved = raw - 1
                    } else if raw < 0 {
                        // Negative indices count back from the end.
                        resolved = verts.count + raw
                    } else {
                        valid = false // 0 is not a valid OBJ index
                        break
                    }
                    guard resolved >= 0, resolved < verts.count else {
                        valid = false
                        break
                    }
                    indices.append(resolved)
                }
                guard valid, indices.count >= 3 else { continue }
                faceCount += 1
                // Fan triangulation: (0,1,2), (0,2,3), (0,3,4), …
                for i in 1..<(indices.count - 1) {
                    let a = verts[indices[0]]
                    let b = verts[indices[i]]
                    let c = verts[indices[i + 1]]
                    // Skip degenerate triangles (zero 3D area).
                    let ab = (b.0 - a.0, b.1 - a.1, b.2 - a.2)
                    let ac = (c.0 - a.0, c.1 - a.1, c.2 - a.2)
                    let nx = ab.1 * ac.2 - ab.2 * ac.1
                    let ny = ab.2 * ac.0 - ab.0 * ac.2
                    let nz = ab.0 * ac.1 - ab.1 * ac.0
                    if abs(nx) + abs(ny) + abs(nz) > 1e-12 {
                        triangles.append(STLHeightfieldImporter.Triangle(a, b, c))
                    }
                }

            default:
                continue // ignore vt/vn/o/g/s/usemtl/mtllib/…
            }
        }
        guard !verts.isEmpty else {
            throw OBJHeightfieldError.notOBJ("no vertex records found")
        }
        guard !triangles.isEmpty else {
            throw OBJHeightfieldError.noFaces("\(faceCount) faces parsed")
        }
        return ParseResult(triangles: triangles, vertexCount: verts.count, faceCount: faceCount)
    }
}
