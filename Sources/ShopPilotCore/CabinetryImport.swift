import Foundation

// MARK: - Cabinetry import (SPK-2000b — cross-platform parity)
//
// Parses cut-list / part-list CSV exports from the six cabinet design
// packages VectorPilot supports (Mozaik, KCD, CabinetSense, CabinetPartsPro,
// Polyboard, SmartWOP). Every vendor writes a different header vocabulary,
// so the parser is vocabulary-driven: a table of accepted header synonyms
// per field, tolerant of comma/tab separators, quoted cells, BOM, CRLF,
// extra columns, and trailing junk rows.
//
// Output: one closed rectangle per part, placed in a shelf layout on the
// sheet, sized in mm. Failures are honest (`success=false` + `errorMessage`),
// never throws.

public struct CabinetryPart: Codable, Sendable, Equatable {
    public let name: String
    public let widthMm: Double   // X extent
    public let heightMm: Double  // Y extent
    public let thicknessMm: Double?
    public let quantity: Int

    public init(name: String, widthMm: Double, heightMm: Double,
                thicknessMm: Double?, quantity: Int) {
        self.name = name
        self.widthMm = widthMm
        self.heightMm = heightMm
        self.thicknessMm = thicknessMm
        self.quantity = quantity
    }
}

public struct CabinetryImportResult: Codable, Sendable {
    public let parts: [CabinetryPart]
    public let vendorDialect: String
    public let rectangles: [[VectorPoint]] // one closed loop per expanded part
    public let sheetWidthMm: Double
    public let sheetHeightMm: Double
    public let success: Bool
    public let errorMessage: String?

    public static func ok(parts: [CabinetryPart], dialect: String,
                          rectangles: [[VectorPoint]],
                          sheetWidthMm: Double, sheetHeightMm: Double) -> CabinetryImportResult {
        CabinetryImportResult(parts: parts, vendorDialect: dialect, rectangles: rectangles,
                              sheetWidthMm: sheetWidthMm, sheetHeightMm: sheetHeightMm,
                              success: true, errorMessage: nil)
    }

    public static func fail(_ message: String) -> CabinetryImportResult {
        CabinetryImportResult(parts: [], vendorDialect: "unknown", rectangles: [],
                              sheetWidthMm: 0, sheetHeightMm: 0,
                              success: false, errorMessage: message)
    }
}

public enum CabinetryImporter {

    /// Header synonyms per logical field, per dialect family. Matching is
    /// case-insensitive substring containment so "Part Name", "partName",
    /// "PART", and "Description" all resolve.
    private static let vocabularies: [(dialect: String, headers: [Field: [String]])] = [
        ("Mozaik", [
            .name: ["part name", "description", "piece"],
            .width: ["width", "length"],
            .height: ["height"],
            .thickness: ["thickness", "thk"],
            .quantity: ["qty", "quantity"],
        ]),
        ("KCD", [
            .name: ["part", "name", "description"],
            .width: ["dim a", "width", "w"],
            .height: ["dim b", "height", "h"],
            .thickness: ["material thickness", "thickness"],
            .quantity: ["qty", "count"],
        ]),
        ("CabinetSense", [
            .name: ["component", "part description", "name"],
            .width: ["finished size w", "width"],
            .height: ["finished size h", "height"],
            .thickness: ["material", "thickness"],
            .quantity: ["qty"],
        ]),
        ("CabinetPartsPro", [
            .name: ["part name", "part", "item"],
            .width: ["grain direction length", "length", "width"],
            .height: ["width across grain", "width", "height"],
            .thickness: ["thickness"],
            .quantity: ["quantity", "qty"],
        ]),
        ("Polyboard", [
            .name: ["label", "part", "reference"],
            .width: ["l (length)", "length", "width"],
            .height: ["h (height)", "height"],
            .thickness: ["t (thickness)", "thickness"],
            .quantity: ["number", "qty", "quantity"],
        ]),
        ("SmartWOP", [
            .name: ["bezeichnung", "name", "part"],
            .width: ["lange", "length", "breite", "width"],
            .height: ["breite", "width", "hoehe", "height"],
            .thickness: ["staerke", "thickness"],
            .quantity: ["anzahl", "qty", "quantity"],
        ]),
    ]

    private enum Field { case name, width, height, thickness, quantity }

    /// Import a cabinetry CSV/text file from its raw bytes.
    /// `sheetWidthMm`/`sheetHeightMm`: target stock for the shelf layout.
    public static func importCSV(_ data: Data,
                                 sheetWidthMm: Double = 2440,
                                 sheetHeightMm: Double = 1220) -> CabinetryImportResult {
        guard !data.isEmpty else { return .fail("File is empty") }

        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() } // BOM

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count >= 2 else {
            return .fail("Need a header row plus at least one part row")
        }

        let separator = detectSeparator(lines[0])
        let headerCells = parseRow(lines[0], separator: separator)

        // Detect the dialect by best header-vocabulary overlap.
        var bestDialect = ""
        var bestMapping: [Field: Int] = [:]
        var bestScore = 0
        for vocab in vocabularies {
            let (mapping, score) = mapHeaders(headerCells, headers: vocab.headers)
            if score > bestScore {
                bestScore = score
                bestDialect = vocab.dialect
                bestMapping = mapping
            }
        }

        guard bestScore >= 3, bestMapping[.width] != nil, bestMapping[.height] != nil else {
            return .fail("Unrecognized cabinetry CSV — no vendor header vocabulary matched " +
                         "(need at least name/width/height columns)")
        }

        // Parse part rows.
        var parts: [CabinetryPart] = []
        for (index, line) in lines.dropFirst().enumerated() {
            let cells = parseRow(line, separator: separator)
            func cell(_ field: Field) -> String? {
                guard let col = bestMapping[field], col < cells.count else { return nil }
                return cells[col].trimmingCharactersInWhitespacesAndQuotes
            }
            guard let w = cell(.width)?.toDouble(), let h = cell(.height)?.toDouble(),
                  w > 0, h > 0 else {
                // Skip junk rows silently only when they carry no numbers at
                // all; rows with partial numbers are reported honestly.
                if cell(.width)?.isEmpty == false || cell(.height)?.isEmpty == false {
                    return .fail("Row \(index + 2): unreadable dimensions " +
                                 "(width='\(cell(.width) ?? "")', height='\(cell(.height) ?? "")')")
                }
                continue
            }
            let qty = max(1, Int(cell(.quantity)?.toDouble() ?? 1))
            let name = cell(.name) ?? "Part \(parts.count + 1)"
            let thickness = cell(.thickness)?.toDouble()
            parts.append(CabinetryPart(name: name, widthMm: min(w, h), heightMm: max(w, h),
                                       thicknessMm: thickness, quantity: qty))
        }

        guard !parts.isEmpty else { return .fail("No parsable part rows found") }

        // Expand quantities into placed rectangles (shelf packing).
        var rectangles: [[VectorPoint]] = []
        var cursorX = 10.0, cursorY = 10.0
        var rowHeight = 0.0
        for part in parts {
            for _ in 0..<part.quantity {
                if cursorX + part.widthMm > sheetWidthMm - 10 {
                    cursorX = 10
                    cursorY += rowHeight + 15
                    rowHeight = 0
                }
                guard cursorY + part.heightMm <= sheetHeightMm - 10 else {
                    return .fail("Parts do not fit on a \(Int(sheetWidthMm))×\(Int(sheetHeightMm)) mm sheet — " +
                                 "\(rectangles.count) placed before running out of room")
                }
                let x0 = cursorX, y0 = cursorY
                let x1 = cursorX + part.widthMm, y1 = cursorY + part.heightMm
                rectangles.append([
                    VectorPoint(x: x0, y: y0), VectorPoint(x: x1, y: y0),
                    VectorPoint(x: x1, y: y1), VectorPoint(x: x0, y: y1),
                    VectorPoint(x: x0, y: y0),
                ])
                cursorX += part.widthMm + 15
                rowHeight = max(rowHeight, part.heightMm)
            }
        }

        return .ok(parts: parts, dialect: bestDialect, rectangles: rectangles,
                   sheetWidthMm: sheetWidthMm, sheetHeightMm: sheetHeightMm)
    }

    /// Convenience: turn the result into named, closed VectorPaths ready to
    /// land on a layer (one path per placed rectangle, quantity-suffixed).
    public static func vectorPaths(from result: CabinetryImportResult, layerId: UUID) -> [VectorPath] {
        guard result.success else { return [] }
        var paths: [VectorPath] = []
        var index = 0
        for part in result.parts {
            for copy in 0..<part.quantity where index < result.rectangles.count {
                index += 1
                paths.append(VectorPath(
                    name: part.quantity > 1 ? "\(part.name) \(copy + 1)" : part.name,
                    points: result.rectangles[index - 1],
                    isClosed: true,
                    layerId: layerId
                ))
            }
        }
        return paths
    }

    // MARK: - Parsing internals

    private static func detectSeparator(_ line: String) -> Character {
        // Tab wins if the first line carries any; then semicolon (European
        // CSV convention, Polyboard/SmartWOP); otherwise comma.
        let counts: [(Character, Int)] = [("\t", line.filter { $0 == "\t" }.count),
                                          (";", line.filter { $0 == ";" }.count),
                                          (",", line.filter { $0 == "," }.count)]
        return counts.max { $0.1 < $1.1 }?.0 ?? ","
    }

    /// Split one CSV row honoring double-quoted cells (embedded commas/tabs).
    private static func parseRow(_ line: String, separator: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == separator && !inQuotes {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current)
        return cells
    }

    /// Best-overlap header mapping for one vocabulary; returns column indexes
    /// per field and a match score (fields matched).
    private static func mapHeaders(_ headerCells: [String],
                                   headers: [Field: [String]]) -> ([Field: Int], Int) {
        var mapping: [Field: Int] = [:]
        var score = 0
        let lowered = headerCells.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        for (field, synonyms) in headers {
            outer: for synonym in synonyms {
                for (col, header) in lowered.enumerated() where header.contains(synonym) {
                    mapping[field] = col
                    score += 1
                    break outer
                }
            }
        }
        return (mapping, score)
    }
}

private extension String {
    /// Trim whitespace AND wrapping quote characters from both ends.
    var trimmingCharactersInWhitespacesAndQuotes: String {
        var s = self.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("\"") || s.hasSuffix("\"") {
            if s.hasPrefix("\"") { s.removeFirst() }
            if s.hasSuffix("\"") { s.removeLast() }
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return s
    }
}
