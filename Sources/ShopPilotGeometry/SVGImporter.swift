import Foundation

// MARK: - SVG Import Result

/// Result of importing an SVG path.
public struct SVGImportResult {
    /// The parsed shapes from the SVG.
    public let shapes: [VectorShape]
    
    /// Any errors encountered during parsing.
    public let errors: [String]
    
    /// Whether import succeeded (no critical errors).
    public var success: Bool { !errors.contains(where: { $0.hasPrefix("FATAL") }) }
}

// MARK: - SVG Importer

/// Parses SVG path data and converts it to VectorShape objects.
public final class SVGImporter {
    
    /// Parse an SVG string and return shapes.
    public static func parse(_ svgString: String) -> SVGImportResult {
        var shapes: [VectorShape] = []
        var errors: [String] = []
        
        // Extract path d attributes from the SVG
        let paths = extractPaths(from: svgString, errors: &errors)
        
        for pathD in paths {
            do {
                let parsedShapes = try parsePathData(pathD)
                shapes.append(contentsOf: parsedShapes)
            } catch {
                errors.append("FATAL: Failed to parse path: \(error.localizedDescription)")
            }
        }
        
        return SVGImportResult(shapes: shapes, errors: errors)
    }
    
    /// Parse a single SVG path d attribute string.
    public static func parsePathData(_ dAttribute: String) throws -> [VectorShape] {
        let commands = try tokenize(dAttribute)
        var shapes: [VectorShape] = []
        var currentPath: [VectorPoint] = []
        var currentPosition = VectorPoint()
        
        for command in commands {
            switch command.type {
            case "M":
                if !currentPath.isEmpty && currentPath.count >= 2 {
                    shapes.append(createShape(from: &currentPath))
                }
                currentPosition = command.target ?? currentPosition
                currentPath = [currentPosition]
                
            case "m":
                if !currentPath.isEmpty && currentPath.count >= 2 {
                    shapes.append(createShape(from: &currentPath))
                }
                let tx = command.target?.x ?? 0
                let ty = command.target?.y ?? 0
                currentPosition = VectorPoint(x: currentPosition.x + tx, y: currentPosition.y + ty)
                currentPath = [currentPosition]
                
            case "L":
                if let target = command.target {
                    currentPath.append(target)
                    currentPosition = target
                }
                
            case "l":
                if let target = command.target {
                    currentPosition = VectorPoint(x: currentPosition.x + target.x, y: currentPosition.y + target.y)
                    currentPath.append(currentPosition)
                }
                
            case "H":
                if let vals = command.values, let x = vals.first {
                    currentPosition = VectorPoint(x: x, y: currentPosition.y)
                    currentPath.append(currentPosition)
                }
                
            case "h":
                if let vals = command.values, let dx = vals.first {
                    currentPosition = VectorPoint(x: currentPosition.x + dx, y: currentPosition.y)
                    currentPath.append(currentPosition)
                }
                
            case "V":
                if let vals = command.values, let y = vals.first {
                    currentPosition = VectorPoint(x: currentPosition.x, y: y)
                    currentPath.append(currentPosition)
                }
                
            case "v":
                if let vals = command.values, let dy = vals.first {
                    currentPosition = VectorPoint(x: currentPosition.x, y: currentPosition.y + dy)
                    currentPath.append(currentPosition)
                }
                
            case "C":
                if let vals = command.values, vals.count >= 6 {
                    let cp1 = VectorPoint(x: vals[0], y: vals[1])
                    let cp2 = VectorPoint(x: vals[2], y: vals[3])
                    let end = VectorPoint(x: vals[4], y: vals[5])
                    
                    let approximated = approximateCubicBezier(from: currentPosition, cp1: cp1, cp2: cp2, to: end, segments: 8)
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = end
                }
                
            case "c":
                if let vals = command.values, vals.count >= 6 {
                    let cp1 = VectorPoint(x: currentPosition.x + vals[0], y: currentPosition.y + vals[1])
                    let cp2 = VectorPoint(x: currentPosition.x + vals[2], y: currentPosition.y + vals[3])
                    let end = VectorPoint(x: currentPosition.x + vals[4], y: currentPosition.y + vals[5])
                    
                    let approximated = approximateCubicBezier(from: currentPosition, cp1: cp1, cp2: cp2, to: end, segments: 8)
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = end
                }
                
            case "Q":
                if let vals = command.values, vals.count >= 4 {
                    let cp = VectorPoint(x: vals[0], y: vals[1])
                    let end = VectorPoint(x: vals[2], y: vals[3])
                    
                    let approximated = approximateQuadraticBezier(from: currentPosition, cp: cp, to: end, segments: 8)
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = end
                }
                
            case "q":
                if let vals = command.values, vals.count >= 4 {
                    let cp = VectorPoint(x: currentPosition.x + vals[0], y: currentPosition.y + vals[1])
                    let end = VectorPoint(x: currentPosition.x + vals[2], y: currentPosition.y + vals[3])
                    
                    let approximated = approximateQuadraticBezier(from: currentPosition, cp: cp, to: end, segments: 8)
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = end
                }
                
            case "A":
                if let vals = command.values, vals.count >= 7 {
                    let rx = abs(vals[0])
                    let ry = abs(vals[1])
                    let xAxisRotation = vals[2]
                    let largeArc = vals[3] > 0.5
                    let sweep = vals[4] > 0.5
                    let endX = vals[5]
                    let endY = vals[6]
                    
                    let approximated = approximateArc(
                        from: currentPosition, to: VectorPoint(x: endX, y: endY),
                        radiusX: rx, radiusY: ry, xAxisRotation: xAxisRotation,
                        largeArc: largeArc, sweep: sweep, segments: 16
                    )
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = VectorPoint(x: endX, y: endY)
                }
                
            case "a":
                if let vals = command.values, vals.count >= 7 {
                    let rx = abs(vals[0])
                    let ry = abs(vals[1])
                    let xAxisRotation = vals[2]
                    let largeArc = vals[3] > 0.5
                    let sweep = vals[4] > 0.5
                    let endX = currentPosition.x + vals[5]
                    let endY = currentPosition.y + vals[6]
                    
                    let approximated = approximateArc(
                        from: currentPosition, to: VectorPoint(x: endX, y: endY),
                        radiusX: rx, radiusY: ry, xAxisRotation: xAxisRotation,
                        largeArc: largeArc, sweep: sweep, segments: 16
                    )
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = VectorPoint(x: endX, y: endY)
                }
                
            case "Z", "z":
                if !currentPath.isEmpty {
                    let startPoint = currentPath[0]
                    if abs(startPoint.x - currentPosition.x) > 1e-6 || abs(startPoint.y - currentPosition.y) > 1e-6 {
                        currentPath.append(startPoint)
                    }
                }
                
            default:
                break
            }
        }
        
        // Finalize remaining path
        if !currentPath.isEmpty && currentPath.count >= 2 {
            shapes.append(createShape(from: &currentPath))
        }
        
        return shapes
    }
    
    /// Create a VectorShape from an array of points.
    private static func createShape(from pathPoints: inout [VectorPoint]) -> VectorShape {
        guard !pathPoints.isEmpty else { return .freehand(points: []) }
        
        let first = pathPoints[0]
        let last = pathPoints[pathPoints.count - 1]
        let isClosed = abs(first.x - last.x) < 1e-6 && abs(first.y - last.y) < 1e-6
        
        if isClosed && pathPoints.count >= 5 {
            // Check if it looks like a rectangle (axis-aligned corners)
            var isRect = true
            for i in 1..<(pathPoints.count - 2) {
                let prev = pathPoints[i - 1]
                let curr = pathPoints[i]
                let next = pathPoints[i + 1]
                
                let dx1 = curr.x - prev.x, dy1 = curr.y - prev.y
                let dx2 = next.x - curr.x, dy2 = next.y - curr.y
                
                if abs(dx1 * dy2 - dy1 * dx2) > 1e-3 {
                    isRect = false
                    break
                }
            }
            
            if isRect {
                let origin = pathPoints[0]
                let width = pathPoints[1].x - origin.x
                let height = pathPoints[2].y - origin.y
                return .rectangle(origin: origin, width: width, height: height)
            }
        }
        
        if isClosed && pathPoints.count >= 4 {
            var points = pathPoints
            points.removeLast()
            return .freehand(points: points)
        }
        
        if pathPoints.count == 2 {
            return .line(start: pathPoints[0], end: pathPoints[1])
        }
        
        return .freehand(points: pathPoints)
    }
    
    /// Approximate a cubic Bezier curve with line segments.
    private static func approximateCubicBezier(
        from start: VectorPoint, cp1: VectorPoint, cp2: VectorPoint, to end: VectorPoint,
        segments: Int = 8
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
    
    /// Approximate a quadratic Bezier curve with line segments.
    private static func approximateQuadraticBezier(
        from start: VectorPoint, cp: VectorPoint, to end: VectorPoint,
        segments: Int = 8
    ) -> [VectorPoint] {
        var points: [VectorPoint] = [start]
        
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let mt = 1.0 - t
            
            let x = mt * mt * start.x + 2 * mt * t * cp.x + t * t * end.x
            let y = mt * mt * start.y + 2 * mt * t * cp.y + t * t * end.y
            
            points.append(VectorPoint(x: x, y: y))
        }
        
        return points
    }
    
    /// Approximate an SVG arc with line segments.
    private static func approximateArc(
        from start: VectorPoint, to end: VectorPoint,
        radiusX: Double, radiusY: Double,
        xAxisRotation: Double, largeArc: Bool, sweep: Bool,
        segments: Int = 16
    ) -> [VectorPoint] {
        guard radiusX > 1e-6 && radiusY > 1e-6 else {
            return [start, end]
        }
        
        let midX = (start.x + end.x) / 2.0
        let midY = (start.y + end.y) / 2.0
        
        let dx = (start.x - end.x) / 2.0
        let dy = (start.y - end.y) / 2.0
        
        let xAngle = xAxisRotation * .pi / 180.0
        let cosX = cos(xAngle), sinX = sin(xAngle)
        
        let x1p = cosX * dx + sinX * dy
        let y1p = -sinX * dx + cosX * dy
        
        // Use mutable local copies for potential scaling
        var localRx = radiusX
        var localRy = radiusY
        
        let rxSq = localRx * localRx
        let rySq = localRy * localRy
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p
        
        let lambda = x1pSq / rxSq + y1pSq / rySq
        if lambda > 1.0 {
            let scaleFactor = sqrt(lambda)
            localRx *= scaleFactor
            localRy *= scaleFactor
        }
        
        // Recompute squares after potential scaling
        let srxSq = localRx * localRx
        let srySq = localRy * localRy
        
        let sign = largeArc == sweep ? -1.0 : 1.0
        let sq = (srxSq * srySq - srxSq * y1pSq - srySq * x1pSq) / (srxSq * y1pSq + srySq * x1pSq)
        let coef = sign * sqrt(max(0, sq))
        let cxp = coef * (localRy * x1p / localRx)
        let cyp = -coef * (localRx * y1p / localRy)
        
        let cx = cosX * cxp - sinX * cyp + midX
        let cy = sinX * cxp + cosX * cyp + midY
        
        let ux = (x1p - cxp) / localRx
        let uy = (y1p - cyp) / localRy
        let vx = (-x1p - cxp) / localRx
        let vy = (-y1p - cyp) / localRy
        
        let startAngle = atan2(uy, ux)
        var endAngle = atan2(vy, vx)
        
        if sweep && startAngle > endAngle {
            endAngle -= 2 * .pi
        } else if !sweep && endAngle > startAngle {
            endAngle += 2 * .pi
        }
        
        // Generate points along the arc
        var points: [VectorPoint] = [start]
        let angleDiff = endAngle - startAngle
        
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let angle = startAngle + angleDiff * t
            
            let x = cx + localRx * cos(angle) * cosX - localRy * sin(angle) * sinX
            let y = cy + localRx * cos(angle) * sinX + localRy * sin(angle) * cosX
            
            points.append(VectorPoint(x: x, y: y))
        }
        
        return points
    }
    
    /// Extract path d attributes from an SVG string.
    private static func extractPaths(from svgString: String, errors: inout [String]) -> [String] {
        var paths: [String] = []
        
        let pattern = #"d\s*=\s*"([^"]*)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(svgString.startIndex..., in: svgString)
            for match in regex.matches(in: svgString, options: [], range: range) {
                if let dRange = Range(match.range(at: 1), in: svgString) {
                    paths.append(String(svgString[dRange]))
                }
            }
        } else {
            errors.append("FATAL: Could not compile SVG path regex")
        }
        
        return paths
    }
    
    /// Tokenize an SVG path d attribute into commands.
    private static func tokenize(_ dAttribute: String) throws -> [SVGPathCommand] {
        var commands: [SVGPathCommand] = []
        let trimmed = dAttribute.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let pattern = #"([MmZzLlHhVvCcSsQqTtAa])([^MmZzLlHhVvCcSsQqTtAa]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw SVGImportError.invalidPathData("Could not compile tokenization regex")
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for match in regex.matches(in: trimmed, options: [], range: range) {
            guard let typeRange = Range(match.range(at: 1), in: trimmed),
                  let argsRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }
            
            let commandType = String(trimmed[typeRange])
            let argsString = String(trimmed[argsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            var values: [Double] = []
            if !argsString.isEmpty {
                let numberPattern = #"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#
                guard let numRegex = try? NSRegularExpression(pattern: numberPattern, options: []) else {
                    throw SVGImportError.invalidPathData("Could not compile number regex")
                }
                
                let numRange = NSRange(argsString.startIndex..., in: argsString)
                for numMatch in numRegex.matches(in: argsString, options: [], range: numRange) {
                    if let valRange = Range(numMatch.range(at: 0), in: argsString) {
                        if let value = Double(String(argsString[valRange])) {
                            values.append(value)
                        }
                    }
                }
            }
            
            var targetPoint: VectorPoint?
            switch commandType {
            case "M", "L", "T", "C":
                if values.count >= 2 {
                    targetPoint = VectorPoint(x: values[0], y: values[1])
                }
            case "m", "l", "t", "c":
                if values.count >= 2 {
                    targetPoint = VectorPoint(x: values[0], y: values[1])
                }
            default:
                break
            }
            
            commands.append(SVGPathCommand(type: commandType, values: values, target: targetPoint))
        }
        
        return commands
    }
}

// MARK: - SVG Path Command

/// A single tokenized SVG path command.
struct SVGPathCommand {
    let type: String  // M, L, H, V, C, Q, A, Z (or lowercase variants)
    let values: [Double]?
    let target: VectorPoint?
}

// MARK: - Errors

enum SVGImportError: LocalizedError {
    case invalidPathData(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPathData(let msg): return "Invalid path data: \(msg)"
        }
    }
}
