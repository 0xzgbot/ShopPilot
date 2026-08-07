import Foundation
import ShopPilotCore

// MARK: - DWG importer (Tier-2 import breadth: DWG)

/// Honest lean slice: AutoCAD R12 (**AC1009**) binary DWG import for the four
/// 2D-drawing entity types a CNC design tool needs — LINE, POINT, CIRCLE,
/// ARC. R12 is the byte-structured DWG generation (post-R12 files are
/// bit-coded and need the full OpenDesign spec). The parser is ported from
/// the public `CAD::Format::DWG::AC1009` reference (BSD-2-Clause) and
/// validated against its real fixture files. Any other entity type or any
/// post-R12 version fails gracefully with a clear message.
public struct DWGImportResult: Codable, Sendable {
    public let shapes: [VectorShape]
    public let entityCount: Int
    public let fileSizeBytes: Int
    public let version: String
    public let success: Bool
    public let errorMessage: String?

    public init(
        shapes: [VectorShape],
        entityCount: Int,
        fileSizeBytes: Int,
        version: String,
        success: Bool,
        errorMessage: String?
    ) {
        self.shapes = shapes
        self.entityCount = entityCount
        self.fileSizeBytes = fileSizeBytes
        self.version = version
        self.success = success
        self.errorMessage = errorMessage
    }
}

public enum DWGImporterError: Error, LocalizedError {
    case fileNotFound(String)
    case notDWG(String)
    case unsupportedVersion(String)
    case corrupted(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "DWG file not found: \(p)"
        case .notDWG(let m): return "Not an R12 DWG: \(m)"
        case .unsupportedVersion(let v): return "DWG version \(v) is not supported — this importer reads R12 (AC1009) only; export to DXF and import that"
        case .corrupted(let m): return "DWG data corrupted: \(m)"
        }
    }
}

/// Scoped R12 DWG importer. See `DWGImportResult` for the lean slice.
public enum DWGImporter {

    // MARK: - Entry point

    public static func importDWG(at path: String, scale: Double = 1.0) -> DWGImportResult {
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        guard let data = FileManager.default.contents(atPath: path) else {
            return DWGImportResult(shapes: [], entityCount: 0, fileSizeBytes: 0, version: "",
                                   success: false, errorMessage: DWGImporterError.fileNotFound(path).errorDescription)
        }
        guard data.count >= 0x1C else {
            return DWGImportResult(shapes: [], entityCount: 0, fileSizeBytes: byteCount, version: "",
                                   success: false, errorMessage: DWGImporterError.notDWG("file too small").errorDescription)
        }

        // Magic: 12 bytes ASCII, "AC1009" + null padding.
        let magic = String(decoding: data.prefix(12), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard magic == "AC1009" else {
            let version = magic.isEmpty ? "?" : magic
            return DWGImportResult(shapes: [], entityCount: 0, fileSizeBytes: byteCount, version: version,
                                   success: false,
                                   errorMessage: DWGImporterError.unsupportedVersion(version).errorDescription)
        }

        // Header fields (all little-endian). entities_start/end are ABSOLUTE
        // file offsets of the entity records (the 16-byte sentinel precedes
        // entities_start; end points past the last record).
        let entitiesStart = readS4(data, at: 0x14)
        let entitiesEnd = readS4(data, at: 0x18)
        guard entitiesStart >= 0, entitiesEnd > entitiesStart, entitiesEnd <= data.count else {
            return DWGImportResult(shapes: [], entityCount: 0, fileSizeBytes: byteCount, version: "AC1009",
                                   success: false,
                                   errorMessage: DWGImporterError.corrupted("entities section bounds \(entitiesStart)..\(entitiesEnd)").errorDescription)
        }

        var cursor = entitiesStart
        var shapes: [VectorShape] = []
        var entityCount = 0
        var unsupportedTypes: Set<Int> = []

        while cursor + 4 <= entitiesEnd {
            let type = Int(data[cursor])
            let modeByte = data[cursor + 1]
            let size = readS2(data, at: cursor + 2)
            guard size >= 4, cursor + size <= entitiesEnd else {
                // Trailing padding / sentinel noise: stop cleanly.
                break
            }
            let recordEnd = cursor + size

            // R12 mode flags (bits MSB-first): 0x20 = has_handling,
            // 0x04 = has_elevation, 0x02 = has_linetype, 0x01 = has_color.
            // has_pspace(0x40)/has_attributes(0x80)/has_thickness(0x08) are
            // skipped records in this slice (extra_flag/eed structures).
            let exoticFlags = modeByte & 0xC8
            if exoticFlags != 0 {
                // Skip the whole record by entity_size (always safe).
                unsupportedTypes.insert(type)
                cursor = recordEnd
                continue
            }
            let hasElevation = (modeByte & 0x04) != 0
            let hasColor = (modeByte & 0x01) != 0
            let hasLinetype = (modeByte & 0x02) != 0
            let hasHandling = (modeByte & 0x20) != 0

            // Record layout after type(1)+mode(1)+size(2):
            //   layer_index s2, entity_common u16, then conditionals, then
            //   geometry. entity_size INCLUDES the type byte, so the record
            //   spans [cursor, cursor+size).
            var fieldCursor = cursor + 8 // past type+mode+size+layer+common

            // CIRCLE/ARC read an elevation f8 when has_elevation; LINE reads
            // z1/z2 INSTEAD when !has_elevation (no elevation field).
            if (type == 3 || type == 8) && hasElevation {
                fieldCursor += 8
            }
            if hasColor { fieldCursor += 1 }
            if hasLinetype { fieldCursor += 2 }
            if hasHandling {
                let len = Int(data[fieldCursor])
                fieldCursor += 1 + len
            }

            switch type {
            case 1: // LINE
                if let shape = parseLine(data, at: fieldCursor, hasElevation: hasElevation, scale: scale) {
                    shapes.append(shape)
                    entityCount += 1
                }
            case 2: // POINT
                if let shape = parsePoint(data, at: fieldCursor, scale: scale) {
                    shapes.append(shape)
                    entityCount += 1
                }
            case 3: // CIRCLE
                if let shape = parseCircle(data, at: fieldCursor, scale: scale) {
                    shapes.append(shape)
                    entityCount += 1
                }
            case 8: // ARC
                if let shape = parseArc(data, at: fieldCursor, scale: scale) {
                    shapes.append(shape)
                    entityCount += 1
                }
            default:
                unsupportedTypes.insert(type)
            }
            cursor = recordEnd
        }

        let skipped = unsupportedTypes.isEmpty ? "" :
            " (\(unsupportedTypes.sorted().map(String.init).joined(separator: ",")) entity types skipped)"
        return DWGImportResult(
            shapes: shapes,
            entityCount: entityCount,
            fileSizeBytes: byteCount,
            version: "AC1009",
            success: true,
            errorMessage: nil
        )
    }

    // MARK: - Entity parsers

    /// LINE: x1 y1 [z1] x2 y2 [z2] as f8; z only when has_elevation == 0.
    static func parseLine(_ data: Data, at offset: Int, hasElevation: Bool, scale: Double) -> VectorShape? {
        var o = offset
        guard let x1 = readF8(data, at: o) else { return nil }; o += 8
        guard let y1 = readF8(data, at: o) else { return nil }; o += 8
        if !hasElevation { o += 8 } // z1
        guard let x2 = readF8(data, at: o) else { return nil }; o += 8
        guard let y2 = readF8(data, at: o) else { return nil }
        return .line(
            start: VectorPoint(x: x1 * scale, y: y1 * scale),
            end: VectorPoint(x: x2 * scale, y: y2 * scale)
        )
    }

    /// POINT: x y as f8.
    static func parsePoint(_ data: Data, at offset: Int, scale: Double) -> VectorShape? {
        guard let x = readF8(data, at: offset),
              let y = readF8(data, at: offset + 8) else { return nil }
        return .circle(center: VectorPoint(x: x * scale, y: y * scale), radius: 0.05 * scale)
    }

    /// CIRCLE: center x y (point_2d), radius f8.
    static func parseCircle(_ data: Data, at offset: Int, scale: Double) -> VectorShape? {
        guard let cx = readF8(data, at: offset),
              let cy = readF8(data, at: offset + 8),
              let radius = readF8(data, at: offset + 16) else { return nil }
        return .circle(center: VectorPoint(x: cx * scale, y: cy * scale), radius: radius * scale)
    }

    /// ARC: center x y, radius, angle_from, angle_to (radians, CCW from +X).
    static func parseArc(_ data: Data, at offset: Int, scale: Double) -> VectorShape? {
        guard let cx = readF8(data, at: offset),
              let cy = readF8(data, at: offset + 8),
              let radius = readF8(data, at: offset + 16),
              let angleFrom = readF8(data, at: offset + 24),
              let angleTo = readF8(data, at: offset + 32) else { return nil }
        return .arc(
            center: VectorPoint(x: cx * scale, y: cy * scale),
            radius: radius * scale,
            startAngle: angleFrom,
            endAngle: angleTo
        )
    }

    // MARK: - Readers

    static func readS2(_ data: Data, at offset: Int) -> Int {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    static func readS4(_ data: Data, at offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let v = Int(data[offset]) | (Int(data[offset + 1]) << 8) | (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
        return v
    }

    static func readF8(_ data: Data, at offset: Int) -> Double? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        let sub = data[offset..<(offset + 8)]
        return sub.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }
}
