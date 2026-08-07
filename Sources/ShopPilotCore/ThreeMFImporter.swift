import Foundation

// MARK: - 3MF Heightfield Importer

public struct ThreeMFImportResult: Sendable {
    public let heightfield: HeightfieldData?
    public let triangleCount: Int
    public let vertexCount: Int
    public let fileSizeBytes: Int64
    public let success: Bool
    public let errorMessage: String?
}

public enum ThreeMFImportError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case notAZip(String)
    case missingModel(String)
    case xmlParseError(String)
    case noTriangles(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "3MF file not found: \(p)"
        case .unreadable(let m): return "3MF unreadable: \(m)"
        case .notAZip(let m): return "Not a valid 3MF archive (ZIP): \(m)"
        case .missingModel(let m): return "3MF archive has no 3D/3dmodel.model entry: \(m)"
        case .xmlParseError(let m): return "3MF model XML could not be parsed: \(m)"
        case .noTriangles(let m): return "3MF model contains no valid triangles: \(m)"
        }
    }
}

/// SPK-3D-spine — 3MF (ZIP + XML) importer that rasterizes the mesh onto a
/// heightfield grid (top surface). Mirrors STLHeightfieldImporter: the archive
/// is extracted with /usr/bin/unzip into a temp dir, the model XML is parsed
/// with Foundation's XMLParser, and the triangle soup is rasterized with the
/// exact same grid math (STLHeightfieldImporter.rasterize).
public enum ThreeMFImporter {

    /// Triangle shape identical to the STL importer's — reused directly by
    /// `STLHeightfieldImporter.rasterize` so both importers share grid math.
    public typealias Triangle = STLHeightfieldImporter.Triangle

    // MARK: - Public entry

    public static func import3MF(
        at path: String,
        cellSizeMm: Double = 1.0,
        scale: Double = 1.0
    ) -> ThreeMFImportResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return ThreeMFImportResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, fileSizeBytes: 0,
                success: false, errorMessage: ThreeMFImportError.fileNotFound(path).localizedDescription
            )
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        do {
            let xml = try extractModelXML(from: path)
            let parsed = try parseModel(xml: xml)
            let triangles = buildTriangles(vertices: parsed.vertices, triangleRefs: parsed.triangleRefs)
            guard !triangles.isEmpty else {
                return ThreeMFImportResult(
                    heightfield: nil, triangleCount: 0, vertexCount: parsed.vertices.count, fileSizeBytes: fileSize,
                    success: false,
                    errorMessage: ThreeMFImportError.noTriangles(
                        "\(parsed.triangleRefs.count) triangle refs over \(parsed.vertices.count) vertices"
                    ).localizedDescription
                )
            }
            let grid = STLHeightfieldImporter.rasterize(triangles: triangles, cellSizeMm: cellSizeMm, scale: scale)
            return ThreeMFImportResult(
                heightfield: grid, triangleCount: triangles.count, vertexCount: parsed.vertices.count,
                fileSizeBytes: fileSize, success: true, errorMessage: nil
            )
        } catch let e as ThreeMFImportError {
            return ThreeMFImportResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, fileSizeBytes: fileSize,
                success: false, errorMessage: e.localizedDescription
            )
        } catch {
            return ThreeMFImportResult(
                heightfield: nil, triangleCount: 0, vertexCount: 0, fileSizeBytes: fileSize,
                success: false, errorMessage: ThreeMFImportError.unreadable(error.localizedDescription).localizedDescription
            )
        }
    }

    // MARK: - ZIP extraction (Process + /usr/bin/unzip)

    /// Extract the archive into a fresh temp dir and return the text of the
    /// model XML (`3D/3dmodel.model`, or any entry named `3dmodel.model`).
    /// Throws instead of crashing on every failure mode.
    private static func extractModelXML(from path: String) throws -> String {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-3mf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", "-q", path, "-d", tmpRoot.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            throw ThreeMFImportError.notAZip(
                msg.isEmpty ? "unzip exited \(proc.terminationStatus)" : msg
            )
        }

        guard let modelURL = findModelFile(in: tmpRoot) else {
            throw ThreeMFImportError.missingModel("no entry named 3D/3dmodel.model found")
        }
        guard let xml = try? String(contentsOf: modelURL, encoding: .utf8) else {
            throw ThreeMFImportError.unreadable("model XML is not valid UTF-8 text")
        }
        return xml
    }

    /// Locate `3dmodel.model` anywhere in the extracted tree (the spec path is
    /// `3D/3dmodel.model`; tolerant of writers that vary the casing/layout).
    private static func findModelFile(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent.lowercased() == "3dmodel.model" {
                return url
            }
        }
        return nil
    }

    // MARK: - XML parsing (XMLParser + delegate)

    private static func parseModel(
        xml: String
    ) throws -> (vertices: [(Double, Double, Double)], triangleRefs: [(Int, Int, Int)]) {
        let delegate = ThreeMFXMLDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        let ok = parser.parse()
        guard ok, !delegate.parseFailed else {
            throw ThreeMFImportError.xmlParseError("malformed or non-3MF XML")
        }
        return (delegate.vertices, delegate.triangleRefs)
    }

    /// Resolve triangle index refs against the parsed vertex list, skipping
    /// out-of-range refs (defensive — never crashes on a hostile model).
    private static func buildTriangles(
        vertices: [(Double, Double, Double)],
        triangleRefs: [(Int, Int, Int)]
    ) -> [Triangle] {
        var out: [Triangle] = []
        out.reserveCapacity(triangleRefs.count)
        for r in triangleRefs {
            guard r.0 >= 0, r.1 >= 0, r.2 >= 0,
                  r.0 < vertices.count, r.1 < vertices.count, r.2 < vertices.count else { continue }
            out.append(Triangle(vertices[r.0], vertices[r.1], vertices[r.2]))
        }
        return out
    }
}

// MARK: - XMLParser delegate

/// Collects `<vertex x y z>` records (indexed in document order — the 3MF
/// vertex id) and `<triangle v1 v2 v3>` index refs. `parseFailed` flips on any
/// malformed record or parser error so the importer can fail gracefully.
private final class ThreeMFXMLDelegate: NSObject, XMLParserDelegate {
    var vertices: [(Double, Double, Double)] = []
    var triangleRefs: [(Int, Int, Int)] = []
    var parseFailed = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "vertex":
            guard let x = attributeDict["x"].flatMap(Double.init),
                  let y = attributeDict["y"].flatMap(Double.init),
                  let z = attributeDict["z"].flatMap(Double.init) else {
                parseFailed = true
                parser.abortParsing()
                return
            }
            vertices.append((x, y, z))
        case "triangle":
            guard let v1 = attributeDict["v1"].flatMap(Int.init),
                  let v2 = attributeDict["v2"].flatMap(Int.init),
                  let v3 = attributeDict["v3"].flatMap(Int.init) else {
                parseFailed = true
                parser.abortParsing()
                return
            }
            triangleRefs.append((v1, v2, v3))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        parseFailed = true
    }
}
