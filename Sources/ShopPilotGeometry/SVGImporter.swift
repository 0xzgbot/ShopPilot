import Foundation

// MARK: - SVG Importer

/// Parses SVG path data and converts to VectorShape objects.
public struct SVGImporter {
    
    /// Parse an SVG `<path>` element's `d` attribute into an array of VectorShapes.
    public static func parsePath(_ d: String) -> [VectorShape] {
        let commands = tokenize(d)
        var shapes: [VectorShape] = []
        var currentPoint = VectorPoint()
        var startPoint = VectorPoint()
        var isClosed = false
        
        for command in commands {
            switch command.type {
            case "M":
                if !shapes.isEmpty, let last = shapes.last {
                    // Start a new subpath — close the previous one first
                    shapes.append(.freehand(points: extractPoints([last])))
                }
                currentPoint = command.target
                startPoint = command.target
                isClosed = false
                
            case "L":
                let line = VectorShape.line(start: currentPoint, end: command.target)
                shapes.append(line)
                currentPoint = command.target
                
            case "H":
                let newPoint = VectorPoint(x: command.target.x, y: currentPoint.y)
                let line = VectorShape.line(start: currentPoint, end: newPoint)
                shapes.append(line)
                currentPoint = newPoint
                
            case "V":
                let newPoint = VectorPoint(x: currentPoint.x, y: command.target.y)
                let line = VectorShape.line(start: currentPoint, end: newPoint)
                shapes.append(line)
                currentPoint = newPoint
                
            case "C":
                // Cubic bezier → approximate with lines
                let approximated = approximateCubicBezier(
                    from: currentPoint,
                    cp1: command.cp1 ?? currentPoint,
                    cp2: command.cp2 ?? currentPoint,
                    to: command.target
                )
                shapes.append(contentsOf: approximated)
                currentPoint = command.target
                
            case "Q":
                // Quadratic bezier → approximate with lines
                let approximated = approximateQuadraticBezier(
                    from: currentPoint,
                    cp: command.cp1 ?? currentPoint,
                    to: command.target
                )
                shapes.append(contentsOf: approximated)
                currentPoint = command.target
                
            case "A":
                // Arc → approximate with lines
                let approximated = approximateArc(
                    from: currentPoint,
                    radiusX: command.rx ?? 10,
                    radiusY: command.ry ?? 10,
                    rotation: command.rotation ?? 0,
                    largeArc: command.largeArc ?? false,
                    sweep: command.sweep ?? true,
                    to: command.target
                )
                shapes.append(contentsOf: approximated)
                currentPoint = command.target
                
            case "Z":
                // Close path — add line back to start if not already there
                if !isClosed && startPoint != currentPoint {
                    let closeLine = VectorShape.line(start: currentPoint, end: startPoint)
                    shapes.append(closeLine)
                }
                isClosed = true
                
            default:
                break
            }
        }
        
        // If we have shapes and weren't closed, add the freehand wrapper
        if !shapes.isEmpty && !isClosed {
            let allPoints = extractPoints(shapes)
            return [.freehand(points: allPoints)]
        }
        
        return shapes
    }
    
    /// Parse a full SVG string and extract all path elements.
    public static func parseSVG(_ svgString: String) -> [VectorShape] {
        let paths = extractPathElements(svgString)
        var allShapes: [VectorShape] = []
        
        for pathData in paths {
            let shapes = parsePath(pathData)
            allShapes.append(contentsOf: shapes)
        }
        
        return allShapes
    }
    
    // MARK: - Tokenization
    
    /// Tokenize an SVG path `d` string into individual commands.
    private static func tokenize(_ d: String) -> [SVGCommand] {
        var commands: [SVGCommand] = []
        let trimmed = d.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Regex to match command letters and their parameters
        let pattern = "([MmLlHhVvCcQqAaZz])([^MmLlHhVvCcQqAaZz]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return commands
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, options: [], range: range)
        
        for match in matches {
            guard let typeRange = Range(match.range(at: 1), in: trimmed),
                  let paramsRange = Range(match.range(at: 2), in: trimmed) else { continue }
            
            let type = String(trimmed[typeRange])
            let paramsStr = String(trimmed[paramsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parameters = parseParameters(paramsStr)
            
            commands.append(SVGCommand(type: type, parameters: parameters))
        }
        
        return commands
    }
    
    /// Parse parameter values from a command's parameter string.
    private static func parseParameters(_ str: String) -> [Double] {
        var params: [Double] = []
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return params }
        
        // Split on whitespace or commas, filter empty
        let separatorSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ","))
        let parts = trimmed.components(separatedBy: separatorSet).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        for part in parts {
            if let value = Double(part.trimmingCharacters(in: .whitespacesAndNewlines)) {
                params.append(value)
            }
        }
        
        return params
    }
    
    // MARK: - Bezier Approximation
    
    /// Approximate a cubic bezier curve with line segments.
    private static func approximateCubicBezier(
        from start: VectorPoint,
        cp1: VectorPoint,
        cp2: VectorPoint,
        to end: VectorPoint,
        segments: Int = 8
    ) -> [VectorShape] {
        var shapes: [VectorShape] = []
        
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            let t1 = Double(i + 1) / Double(segments)
            
            let p0 = cubicBezierPoint(t: t0, start: start, cp1: cp1, cp2: cp2, end: end)
            let p1 = cubicBezierPoint(t: t1, start: start, cp1: cp1, cp2: cp2, end: end)
            
            shapes.append(.line(start: p0, end: p1))
        }
        
        return shapes
    }
    
    /// Approximate a quadratic bezier curve with line segments.
    private static func approximateQuadraticBezier(
        from start: VectorPoint,
        cp: VectorPoint,
        to end: VectorPoint,
        segments: Int = 8
    ) -> [VectorShape] {
        var shapes: [VectorShape] = []
        
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            let t1 = Double(i + 1) / Double(segments)
            
            let p0 = quadraticBezierPoint(t: t0, start: start, cp: cp, end: end)
            let p1 = quadraticBezierPoint(t: t1, start: start, cp: cp, end: end)
            
            shapes.append(.line(start: p0, end: p1))
        }
        
        return shapes
    }
    
    /// Approximate an SVG arc with line segments.
    private static func approximateArc(
        from start: VectorPoint,
        radiusX: Double,
        radiusY: Double,
        rotation: Double,
        largeArc: Bool,
        sweep: Bool,
        to end: VectorPoint,
        segments: Int = 16
    ) -> [VectorShape] {
        var shapes: [VectorShape] = []
        
        // Calculate center of arc
        guard let center = calculateArcCenter(
            start: start, end: end,
            radiusX: abs(radiusX), radiusY: abs(radiusY),
            largeArc: largeArc, sweep: sweep, rotation: rotation
        ) else { return shapes }
        
        // Calculate start and end angles
        let rotRad = rotation * .pi / 180.0
        let dx = (start.x - center.x) * cos(rotRad) + (start.y - center.y) * sin(rotRad)
        let dy = -(start.x - center.x) * sin(rotRad) + (start.y - center.y) * cos(rotRad)
        let startAngle = atan2(dy, dx)
        
        let ex = (end.x - center.x) * cos(rotRad) + (end.y - center.y) * sin(rotRad)
        let ey = -(end.x - center.x) * sin(rotRad) + (end.y - center.y) * cos(rotRad)
        var endAngle = atan2(ey, ex)
        
        // Adjust for sweep and large arc flags
        if sweep && endAngle <= startAngle {
            endAngle += 2 * .pi
        } else if !sweep && endAngle > startAngle {
            endAngle -= 2 * .pi
        }
        
        let totalSweep = endAngle - startAngle
        
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            let t1 = Double(i + 1) / Double(segments)
            
            let angle0 = startAngle + totalSweep * t0
            let angle1 = startAngle + totalSweep * t1
            
            let p0 = VectorPoint(
                x: center.x + radiusX * cos(angle0) * cos(rotRad) - radiusY * sin(angle0) * sin(rotRad),
                y: center.y + radiusX * cos(angle0) * sin(rotRad) + radiusY * sin(angle0) * cos(rotRad)
            )
            
            let p1 = VectorPoint(
                x: center.x + radiusX * cos(angle1) * cos(rotRad) - radiusY * sin(angle1) * sin(rotRad),
                y: center.y + radiusX * cos(angle1) * sin(rotRad) + radiusY * sin(angle1) * cos(rotRad)
            )
            
            shapes.append(.line(start: p0, end: p1))
        }
        
        return shapes
    }
    
    /// Calculate the center of an SVG arc.
    private static func calculateArcCenter(
        start: VectorPoint,
        end: VectorPoint,
        radiusX: Double,
        radiusY: Double,
        largeArc: Bool,
        sweep: Bool,
        rotation: Double
    ) -> VectorPoint? {
        let rotRad = rotation * .pi / 180.0
        
        // Transform to unit circle space
        let dx = (start.x - end.x) / 2.0
        let dy = (start.y - end.y) / 2.0
        
        let x1 = dx * cos(rotRad) + dy * sin(rotRad)
        let y1 = -dx * sin(rotRad) + dy * cos(rotRad)
        
        let rxSq = radiusX * radiusX
        let rySq = radiusY * radiusY
        let x1Sq = x1 * x1
        let y1Sq = y1 * y1
        
        // Check if radii are valid
        guard rxSq > 0, rySq > 0 else { return nil }
        
        let lambda = (x1Sq / rxSq) + (y1Sq / rySq)
        var scaleFactor: Double = 1.0
        
        if lambda > 1.0 {
            scaleFactor = sqrt(lambda)
        }
        
        let rx = radiusX * scaleFactor
        let ry = radiusY * scaleFactor
        
        let sign = largeArc == sweep ? -1.0 : 1.0
        let sq = (rx * rx * rySq - rxSq * rySq * y1Sq) / (rxSq * rySq + x1Sq * y1Sq)
        
        guard sq >= 0 else { return nil }
        
        let coef = sign * sqrt(sq)
        let cx1 = coef * (rx * y1 / ry)
        let cy1 = coef * -(ry * x1 / rx)
        
        // Transform back
        let centerX = (start.x + end.x) / 2.0 + cx1 * cos(rotRad) - cy1 * sin(rotRad)
        let centerY = (start.y + end.y) / 2.0 + cx1 * sin(rotRad) + cy1 * cos(rotRad)
        
        return VectorPoint(x: centerX, y: centerY)
    }
    
    // MARK: - Bezier Evaluation
    
    private static func cubicBezierPoint(
        t: Double, start: VectorPoint, cp1: VectorPoint, cp2: VectorPoint, end: VectorPoint
    ) -> VectorPoint {
        let u = 1.0 - t
        return VectorPoint(
            x: u*u*u*start.x + 3*u*t*cp1.x + 3*u*t*t*cp2.x + t*t*t*end.x,
            y: u*u*u*start.y + 3*u*t*cp1.y + 3*u*t*t*cp2.y + t*t*t*end.y
        )
    }
    
    private static func quadraticBezierPoint(
        t: Double, start: VectorPoint, cp: VectorPoint, end: VectorPoint
    ) -> VectorPoint {
        let u = 1.0 - t
        return VectorPoint(
            x: u*u*start.x + 2*u*t*cp.x + t*t*end.x,
            y: u*u*start.y + 2*u*t*cp.y + t*t*end.y
        )
    }
    
    // MARK: - Helpers
    
    /// Extract all VectorPoints from an array of shapes.
    private static func extractPoints(_ shapes: [VectorShape]) -> [VectorPoint] {
        var points: [VectorPoint] = []
        
        for shape in shapes {
            switch shape {
            case .line(let s, let e):
                if points.isEmpty || points.last != s {
                    points.append(s)
                }
                points.append(e)
            case .freehand(let pts):
                points.append(contentsOf: pts)
            default:
                // For non-line shapes, skip (they're already VectorShapes)
                break
            }
        }
        
        return points
    }
    
    /// Extract path `d` attributes from an SVG string.
    private static func extractPathElements(_ svgString: String) -> [String] {
        var paths: [String] = []
        let trimmed = svgString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Simple regex to find <path ... d="..." /> or <path ...>...</path>
        let pattern = #"d=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return paths
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, options: [], range: range)
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: trimmed) {
                paths.append(String(trimmed[range]))
            }
        }
        
        return paths
    }
}

// MARK: - SVG Command

/// Represents a single command from an SVG path `d` attribute.
struct SVGCommand {
    let type: String           // M, L, H, V, C, Q, A, Z (or lowercase)
    let target: VectorPoint    // End point of the command
    let cp1: VectorPoint?      // First control point (for C/Q/A)
    let cp2: VectorPoint?      // Second control point (for C only)
    let rx: Double?            // X radius (for A)
    let ry: Double?            // Y radius (for A)
    let rotation: Double?      // Arc rotation in degrees
    let largeArc: Bool?        // Large arc flag
    let sweep: Bool?           // Sweep flag
    
    init(type: String, parameters: [Double]) {
        self.type = type
        
        switch type.uppercased() {
        case "M", "L":
            self.target = VectorPoint(x: parameters.count > 0 ? parameters[0] : 0,
                                      y: parameters.count > 1 ? parameters[1] : 0)
            self.cp1 = nil
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        case "H":
            self.target = VectorPoint(x: parameters.first ?? 0, y: 0)
            self.cp1 = nil
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        case "V":
            self.target = VectorPoint(x: 0, y: parameters.first ?? 0)
            self.cp1 = nil
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        case "C":
            if parameters.count >= 6 {
                self.target = VectorPoint(x: parameters[4], y: parameters[5])
                self.cp1 = VectorPoint(x: parameters[0], y: parameters[1])
                self.cp2 = VectorPoint(x: parameters[2], y: parameters[3])
            } else {
                self.target = VectorPoint()
                self.cp1 = nil
                self.cp2 = nil
            }
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        case "Q":
            if parameters.count >= 4 {
                self.target = VectorPoint(x: parameters[2], y: parameters[3])
                self.cp1 = VectorPoint(x: parameters[0], y: parameters[1])
            } else {
                self.target = VectorPoint()
                self.cp1 = nil
            }
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        case "A":
            if parameters.count >= 7 {
                self.target = VectorPoint(x: parameters[5], y: parameters[6])
                self.rx = parameters[0]
                self.ry = parameters[1]
                self.rotation = parameters[2]
                self.largeArc = parameters[3] != 0
                self.sweep = parameters[4] != 0
            } else {
                self.target = VectorPoint()
                self.rx = nil
                self.ry = nil
                self.rotation = nil
                self.largeArc = nil
                self.sweep = nil
            }
            self.cp1 = nil
            self.cp2 = nil
            
        case "Z":
            self.target = VectorPoint()
            self.cp1 = nil
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
            
        default:
            self.target = VectorPoint()
            self.cp1 = nil
            self.cp2 = nil
            self.rx = nil
            self.ry = nil
            self.rotation = nil
            self.largeArc = nil
            self.sweep = nil
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct SVGImporter_Previews: PreviewProvider {
    static var previews: some View {
        Text("SVG importer is a non-visual component")
    }
}
#endif
