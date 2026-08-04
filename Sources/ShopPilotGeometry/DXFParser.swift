import Foundation

// MARK: - DXF Importer (SPK-1101g)

/// Minimal ASCII DXF importer: reads the ENTITIES section and converts
/// LINE / LWPOLYLINE / CIRCLE / ARC entities into `VectorShape` values.
///
/// Contract:
/// - Tolerant by design (mirrors SVGImporter): unsupported entities
///   (TEXT, INSERT, SPLINE, POLYLINE-with-VERTEX, …) are skipped, and
///   malformed group pairs are collected as errors — never fatal.
/// - Angles are converted from DXF degrees to radians to match
///   `VectorShape.arc` semantics.
/// - LWPOLYLINE vertices are read in order; the 70-group bit 1 (closed)
///   closes the polyline (first point re-appended, like the canvas's
///   closed-freehand convention).
public enum DXFParser {

    public struct Result: Sendable {
        public let shapes: [VectorShape]
        public let errors: [String]

        /// True when no entity failed to parse (skips are not errors).
        public var success: Bool { errors.isEmpty }
    }

    public static func parse(_ dxf: String) -> Result {
        var shapes: [VectorShape] = []
        var errors: [String] = []

        let lines = dxf
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !lines.isEmpty else {
            return Result(shapes: [], errors: ["DXF input is empty"])
        }

        var section = ""
        var i = 0
        while i + 1 < lines.count {
            let code = lines[i]
            let value = lines[i + 1]
            i += 2

            if code != "0" { continue }

            switch value {
            case "SECTION":
                // The next pair names the section (2 ENTITIES / 2 HEADER / …).
                if i + 1 < lines.count, lines[i] == "2" {
                    section = lines[i + 1]
                    i += 2
                }
            case "ENDSEC":
                section = ""
            case "EOF":
                i = lines.count
            default:
                guard section == "ENTITIES" else { continue }
                switch value {
                case "LINE":
                    i = parseLine(lines, at: i, shapes: &shapes, errors: &errors)
                case "LWPOLYLINE":
                    i = parseLWPolyline(lines, at: i, shapes: &shapes, errors: &errors)
                case "CIRCLE":
                    i = parseCircle(lines, at: i, shapes: &shapes, errors: &errors)
                case "ARC":
                    i = parseArc(lines, at: i, shapes: &shapes, errors: &errors)
                default:
                    i = skipEntity(lines, at: i)
                }
            }
        }

        return Result(shapes: shapes, errors: errors)
    }

    // MARK: - Entity parsers (consume pairs up to the next 0-group)

    private static func parseLine(
        _ lines: [String],
        at i: Int,
        shapes: inout [VectorShape],
        errors: inout [String]
    ) -> Int {
        var x1: Double?
        var y1: Double?
        var x2: Double?
        var y2: Double?
        let j = collect(lines, at: i) { code, value in
            guard let d = Double(value) else { return }
            switch code {
            case "10": x1 = d
            case "20": y1 = d
            case "11": x2 = d
            case "21": y2 = d
            default: break
            }
        }
        if let x1, let y1, let x2, let y2 {
            shapes.append(.line(start: VectorPoint(x: x1, y: y1), end: VectorPoint(x: x2, y: y2)))
        } else {
            errors.append("LINE: missing start/end coordinates")
        }
        return j
    }

    private static func parseLWPolyline(
        _ lines: [String],
        at i: Int,
        shapes: inout [VectorShape],
        errors: inout [String]
    ) -> Int {
        var vertices: [VectorPoint] = []
        var closed = false
        var pendingX: Double?
        let j = collect(lines, at: i) { code, value in
            guard let d = Double(value) else { return }
            switch code {
            case "10":
                pendingX = d
            case "20":
                if let px = pendingX {
                    vertices.append(VectorPoint(x: px, y: d))
                    pendingX = nil
                }
            case "70":
                closed = Int(d) & 1 != 0
            default:
                break
            }
        }
        if vertices.count >= 2 {
            var points = vertices
            if closed, let first = points.first, points.last != first {
                points.append(first)
            }
            shapes.append(.freehand(points: points))
        } else {
            errors.append("LWPOLYLINE: fewer than 2 vertices")
        }
        return j
    }

    private static func parseCircle(
        _ lines: [String],
        at i: Int,
        shapes: inout [VectorShape],
        errors: inout [String]
    ) -> Int {
        var cx: Double?
        var cy: Double?
        var radius: Double?
        let j = collect(lines, at: i) { code, value in
            guard let d = Double(value) else { return }
            switch code {
            case "10": cx = d
            case "20": cy = d
            case "40": radius = d
            default: break
            }
        }
        if let cx, let cy, let radius {
            shapes.append(.circle(center: VectorPoint(x: cx, y: cy), radius: radius))
        } else {
            errors.append("CIRCLE: missing center/radius")
        }
        return j
    }

    private static func parseArc(
        _ lines: [String],
        at i: Int,
        shapes: inout [VectorShape],
        errors: inout [String]
    ) -> Int {
        var cx: Double?
        var cy: Double?
        var radius: Double?
        var startDegrees: Double?
        var endDegrees: Double?
        let j = collect(lines, at: i) { code, value in
            guard let d = Double(value) else { return }
            switch code {
            case "10": cx = d
            case "20": cy = d
            case "40": radius = d
            case "50": startDegrees = d
            case "51": endDegrees = d
            default: break
            }
        }
        if let cx, let cy, let radius, let startDegrees, let endDegrees {
            shapes.append(.arc(
                center: VectorPoint(x: cx, y: cy),
                radius: radius,
                startAngle: startDegrees * .pi / 180.0,
                endAngle: endDegrees * .pi / 180.0
            ))
        } else {
            errors.append("ARC: missing center/radius/angles")
        }
        return j
    }

    /// Consume an unsupported entity's pairs (up to the next 0-group).
    private static func skipEntity(_ lines: [String], at i: Int) -> Int {
        var j = i
        while j + 1 < lines.count {
            if lines[j] == "0" { break }
            j += 2
        }
        return j
    }

    /// Walk pairs until the next 0-group, handing each (code, value) to the
    /// closure. Returns the index after the terminator (points at the 0).
    private static func collect(
        _ lines: [String],
        at i: Int,
        _ visit: (String, String) -> Void
    ) -> Int {
        var j = i
        while j + 1 < lines.count {
            let code = lines[j]
            if code == "0" { break }
            let value = lines[j + 1]
            visit(code, value)
            j += 2
        }
        return j
    }
}
