import Foundation

// MARK: - SVG ViewBox Transform

/// Affine transform derived from an SVG `viewBox` (scale + translate).
/// Applies `x' = x * scaleX + offsetX`, `y' = y * scaleY + offsetY`.
public struct SVGTransform: Equatable {
    public let scaleX: Double
    public let scaleY: Double
    public let offsetX: Double
    public let offsetY: Double

    public static let identity = SVGTransform(scaleX: 1, scaleY: 1, offsetX: 0, offsetY: 0)

    public init(scaleX: Double = 1, scaleY: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// Whether this transform is the identity (no-op).
    public var isIdentity: Bool {
        abs(scaleX - 1) < 1e-9 && abs(scaleY - 1) < 1e-9 && abs(offsetX) < 1e-9 && abs(offsetY) < 1e-9
    }

    public func apply(_ point: VectorPoint) -> VectorPoint {
        VectorPoint(x: point.x * scaleX + offsetX, y: point.y * scaleY + offsetY)
    }

    /// Average scale factor, used for radii when scaling is (near-)uniform.
    var radiusScale: Double { (abs(scaleX) + abs(scaleY)) / 2 }

    public func apply(_ shape: VectorShape) -> VectorShape {
        switch shape {
        case .line(let start, let end):
            return .line(start: apply(start), end: apply(end))
        case .rectangle(let origin, let width, let height):
            return .rectangle(origin: apply(origin), width: width * scaleX, height: height * scaleY)
        case .circle(let center, let radius):
            return .circle(center: apply(center), radius: radius * radiusScale)
        case .ellipse(let center, let radiusX, let radiusY, let rotation):
            return .ellipse(center: apply(center), radiusX: radiusX * abs(scaleX), radiusY: radiusY * abs(scaleY), rotation: rotation)
        case .arc(let center, let radius, let startAngle, let endAngle):
            return .arc(center: apply(center), radius: radius * radiusScale, startAngle: startAngle, endAngle: endAngle)
        case .polygon(let center, let radius, let sides, let rotation):
            return .polygon(center: apply(center), radius: radius * radiusScale, sides: sides, rotation: rotation)
        case .star(let center, let outerRadius, let innerRadius, let points, let rotation):
            return .star(center: apply(center), outerRadius: outerRadius * radiusScale, innerRadius: innerRadius * radiusScale, points: points, rotation: rotation)
        case .freehand(let points):
            return .freehand(points: points.map(apply))
        }
    }
}

// MARK: - SVG Document Size

/// The document size reported by an SVG (width/height attrs, or viewBox when absent).
public struct SVGDocumentSize: Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

// MARK: - SVG Import Result

/// Result of importing an SVG string.
public struct SVGImportResult {
    /// The parsed shapes from the SVG.
    public let shapes: [VectorShape]

    /// Any errors encountered during parsing.
    public let errors: [String]

    /// Document size (width/height attributes, or viewBox when width/height are missing).
    public let documentSize: SVGDocumentSize?

    /// Whether import succeeded (no critical errors).
    public var success: Bool { !errors.contains(where: { $0.hasPrefix("FATAL") }) }

    public init(shapes: [VectorShape], errors: [String], documentSize: SVGDocumentSize? = nil) {
        self.shapes = shapes
        self.errors = errors
        self.documentSize = documentSize
    }
}

// MARK: - SVG Importer

/// Parses SVG path data and primitive elements, converting them to `VectorShape` objects.
///
/// Supported commands: `M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z` with implicit
/// repeated coordinate pairs (`M 0 0 10 0 10 10` ⇒ moveto + implicit lineto).
/// Supported elements: `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`.
/// The document `viewBox` is honored (scale + translate) so imports land correctly.
public final class SVGImporter {

    /// Parse an SVG string and return shapes.
    public static func parse(_ svgString: String) -> SVGImportResult {
        var errors: [String] = []
        var shapes: [VectorShape] = []

        let (transform, documentSize) = parseViewBox(from: svgString)

        // Path elements (d attributes).
        let paths = extractPaths(from: svgString, errors: &errors)
        for pathD in paths {
            do {
                let parsedShapes = try parsePathData(pathD, transform: transform)
                shapes.append(contentsOf: parsedShapes)
            } catch {
                errors.append("FATAL: Failed to parse path: \(error.localizedDescription)")
            }
        }

        // Primitive elements.
        shapes.append(contentsOf: parsePrimitives(from: svgString, transform: transform))

        return SVGImportResult(shapes: shapes, errors: errors, documentSize: documentSize)
    }

    /// Parse a single SVG path `d` attribute string (no viewBox transform applied).
    public static func parsePathData(_ dAttribute: String) throws -> [VectorShape] {
        try parsePathData(dAttribute, transform: .identity)
    }

    /// Parse a single SVG path `d` attribute string, applying the given transform.
    public static func parsePathData(_ dAttribute: String, transform: SVGTransform) throws -> [VectorShape] {
        let commands = try tokenize(dAttribute)
        let shapes = execute(commands)
        return transform.isIdentity ? shapes : shapes.map { transform.apply($0) }
    }

    // MARK: - Command execution

    private static func execute(_ commands: [SVGPathCommand]) -> [VectorShape] {
        var shapes: [VectorShape] = []
        var currentPath: [VectorPoint] = []
        var currentPosition = VectorPoint()

        /// Last cubic control point (cp2 of the most recent C/S) for S reflection.
        var lastCubicControl: VectorPoint?
        /// Last quadratic control point (cp of the most recent Q/T) for T reflection.
        var lastQuadControl: VectorPoint?

        func flushCurrentPath() {
            if !currentPath.isEmpty && currentPath.count >= 2 {
                shapes.append(createShape(from: &currentPath))
            }
            currentPath = []
        }

        for command in commands {
            let type = command.type
            let values = command.values ?? []
            var index = 0

            switch type {
            case "M", "m":
                let relative = type == "m"
                flushCurrentPath()
                if values.count >= 2 {
                    currentPosition = relative
                        ? VectorPoint(x: currentPosition.x + values[0], y: currentPosition.y + values[1])
                        : VectorPoint(x: values[0], y: values[1])
                    currentPath = [currentPosition]
                    index = 2
                }
                // Remaining pairs are implicit lineto.
                while index + 1 < values.count {
                    currentPosition = relative
                        ? VectorPoint(x: currentPosition.x + values[index], y: currentPosition.y + values[index + 1])
                        : VectorPoint(x: values[index], y: values[index + 1])
                    currentPath.append(currentPosition)
                    index += 2
                }
                lastCubicControl = nil
                lastQuadControl = nil

            case "L", "l":
                let relative = type == "l"
                while index + 1 < values.count {
                    currentPosition = relative
                        ? VectorPoint(x: currentPosition.x + values[index], y: currentPosition.y + values[index + 1])
                        : VectorPoint(x: values[index], y: values[index + 1])
                    currentPath.append(currentPosition)
                    index += 2
                }
                lastCubicControl = nil
                lastQuadControl = nil

            case "H", "h":
                let relative = type == "h"
                while index < values.count {
                    currentPosition = relative
                        ? VectorPoint(x: currentPosition.x + values[index], y: currentPosition.y)
                        : VectorPoint(x: values[index], y: currentPosition.y)
                    currentPath.append(currentPosition)
                    index += 1
                }
                lastCubicControl = nil
                lastQuadControl = nil

            case "V", "v":
                let relative = type == "v"
                while index < values.count {
                    currentPosition = relative
                        ? VectorPoint(x: currentPosition.x, y: currentPosition.y + values[index])
                        : VectorPoint(x: currentPosition.x, y: values[index])
                    currentPath.append(currentPosition)
                    index += 1
                }
                lastCubicControl = nil
                lastQuadControl = nil

            case "C", "c":
                let relative = type == "c"
                while index + 5 < values.count {
                    let cp1 = point(relative: relative, base: currentPosition, values: values, index: index)
                    let cp2 = point(relative: relative, base: currentPosition, values: values, index: index + 2)
                    let end = point(relative: relative, base: currentPosition, values: values, index: index + 4)
                    currentPath.append(contentsOf: approximateCubicBezier(
                        from: currentPosition, cp1: cp1, cp2: cp2, to: end, segments: 8
                    ).dropFirst())
                    currentPosition = end
                    lastCubicControl = cp2
                    lastQuadControl = nil
                    index += 6
                }

            case "S", "s":
                let relative = type == "s"
                while index + 3 < values.count {
                    let cp2 = point(relative: relative, base: currentPosition, values: values, index: index)
                    let end = point(relative: relative, base: currentPosition, values: values, index: index + 2)
                    // cp1 reflects the previous cubic control point about the current position.
                    let cp1: VectorPoint
                    if let last = lastCubicControl {
                        cp1 = VectorPoint(x: 2 * currentPosition.x - last.x, y: 2 * currentPosition.y - last.y)
                    } else {
                        cp1 = currentPosition
                    }
                    currentPath.append(contentsOf: approximateCubicBezier(
                        from: currentPosition, cp1: cp1, cp2: cp2, to: end, segments: 8
                    ).dropFirst())
                    currentPosition = end
                    lastCubicControl = cp2
                    lastQuadControl = nil
                    index += 4
                }

            case "Q", "q":
                let relative = type == "q"
                while index + 3 < values.count {
                    let cp = point(relative: relative, base: currentPosition, values: values, index: index)
                    let end = point(relative: relative, base: currentPosition, values: values, index: index + 2)
                    currentPath.append(contentsOf: approximateQuadraticBezier(
                        from: currentPosition, cp: cp, to: end, segments: 8
                    ).dropFirst())
                    currentPosition = end
                    lastQuadControl = cp
                    lastCubicControl = nil
                    index += 4
                }

            case "T", "t":
                let relative = type == "t"
                while index + 1 < values.count {
                    let end = point(relative: relative, base: currentPosition, values: values, index: index)
                    // cp reflects the previous quadratic control point about the current position.
                    let cp: VectorPoint
                    if let last = lastQuadControl {
                        cp = VectorPoint(x: 2 * currentPosition.x - last.x, y: 2 * currentPosition.y - last.y)
                    } else {
                        cp = currentPosition
                    }
                    currentPath.append(contentsOf: approximateQuadraticBezier(
                        from: currentPosition, cp: cp, to: end, segments: 8
                    ).dropFirst())
                    currentPosition = end
                    lastQuadControl = cp
                    lastCubicControl = nil
                    index += 2
                }

            case "A", "a":
                let relative = type == "a"
                while index + 6 < values.count {
                    let rx = abs(values[index])
                    let ry = abs(values[index + 1])
                    let xAxisRotation = values[index + 2]
                    let largeArc = values[index + 3] > 0.5
                    let sweep = values[index + 4] > 0.5
                    let end = relative
                        ? VectorPoint(x: currentPosition.x + values[index + 5], y: currentPosition.y + values[index + 6])
                        : VectorPoint(x: values[index + 5], y: values[index + 6])

                    let approximated = approximateArc(
                        from: currentPosition, to: end,
                        radiusX: rx, radiusY: ry, xAxisRotation: xAxisRotation,
                        largeArc: largeArc, sweep: sweep, segments: 16
                    )
                    currentPath.append(contentsOf: approximated.dropFirst())
                    currentPosition = end
                    lastCubicControl = nil
                    lastQuadControl = nil
                    index += 7
                }

            case "Z", "z":
                if !currentPath.isEmpty {
                    let startPoint = currentPath[0]
                    if abs(startPoint.x - currentPosition.x) > 1e-6 || abs(startPoint.y - currentPosition.y) > 1e-6 {
                        currentPath.append(startPoint)
                    }
                    // Per SVG spec, Z sets the current point back to the subpath start.
                    currentPosition = startPoint
                }
                lastCubicControl = nil
                lastQuadControl = nil

            default:
                break
            }
        }

        flushCurrentPath()
        return shapes
    }

    private static func point(relative: Bool, base: VectorPoint, values: [Double], index: Int) -> VectorPoint {
        relative
            ? VectorPoint(x: base.x + values[index], y: base.y + values[index + 1])
            : VectorPoint(x: values[index], y: values[index + 1])
    }

    // MARK: - Shape creation

    /// Create a VectorShape from an array of points.
    private static func createShape(from pathPoints: inout [VectorPoint]) -> VectorShape {
        guard !pathPoints.isEmpty else { return .freehand(points: []) }

        let first = pathPoints[0]
        let last = pathPoints[pathPoints.count - 1]
        let isClosed = abs(first.x - last.x) < 1e-6 && abs(first.y - last.y) < 1e-6

        if isClosed && pathPoints.count >= 5 {
            // Check if it looks like an axis-aligned rectangle: every consecutive
            // triple has perpendicular, non-degenerate segments (right-angle corners).
            var isRect = true
            for i in 1..<(pathPoints.count - 2) {
                let prev = pathPoints[i - 1]
                let curr = pathPoints[i]
                let next = pathPoints[i + 1]

                let dx1 = curr.x - prev.x, dy1 = curr.y - prev.y
                let dx2 = next.x - curr.x, dy2 = next.y - curr.y

                let dot = dx1 * dx2 + dy1 * dy2
                let degenerate = (abs(dx1) < 1e-9 && abs(dy1) < 1e-9)
                    || (abs(dx2) < 1e-9 && abs(dy2) < 1e-9)
                if abs(dot) > 1e-3 || degenerate {
                    isRect = false
                    break
                }
            }

            if isRect {
                // Robust to any starting corner: use the path bounds.
                let xs = pathPoints.map(\.x)
                let ys = pathPoints.map(\.y)
                let minX = xs.min()!
                let minY = ys.min()!
                return .rectangle(
                    origin: VectorPoint(x: minX, y: minY),
                    width: xs.max()! - minX,
                    height: ys.max()! - minY
                )
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

    // MARK: - Curve approximation

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

    // MARK: - Element extraction

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

    /// Parse the root `<svg>` viewBox (and width/height) into a transform + document size.
    private static func parseViewBox(from svgString: String) -> (transform: SVGTransform, size: SVGDocumentSize?) {
        guard let rootRegex = try? NSRegularExpression(pattern: #"<svg\b([^>]*)>"#, options: [.caseInsensitive]),
              let match = rootRegex.firstMatch(in: svgString, options: [], range: NSRange(svgString.startIndex..., in: svgString)),
              let attrsRange = Range(match.range(at: 1), in: svgString) else {
            return (.identity, nil)
        }

        let attrs = String(svgString[attrsRange])
        let width = numberAttr("width", in: attrs)
        let height = numberAttr("height", in: attrs)

        var size: SVGDocumentSize?
        if let width, let height {
            size = SVGDocumentSize(width: width, height: height)
        }

        guard let viewBoxString = stringAttr("viewBox", in: attrs) else {
            return (.identity, size)
        }

        let numbers = numbers(in: viewBoxString)
        guard numbers.count >= 4, numbers[2] > 1e-9, numbers[3] > 1e-9 else {
            return (.identity, size)
        }

        let minX = numbers[0], minY = numbers[1]
        let viewBoxWidth = numbers[2], viewBoxHeight = numbers[3]
        let scaleX = (width ?? viewBoxWidth) / viewBoxWidth
        let scaleY = (height ?? viewBoxHeight) / viewBoxHeight
        let transform = SVGTransform(
            scaleX: scaleX, scaleY: scaleY,
            offsetX: -minX * scaleX, offsetY: -minY * scaleY
        )
        return (transform, size ?? SVGDocumentSize(width: viewBoxWidth, height: viewBoxHeight))
    }

    /// Extract primitive elements (rect/circle/ellipse/line/polyline/polygon) into shapes.
    private static func parsePrimitives(from svgString: String, transform: SVGTransform) -> [VectorShape] {
        var shapes: [VectorShape] = []

        // <rect x y width height (rx ry)>
        for attrs in elementAttributes(named: "rect", in: svgString) {
            guard let width = numberAttr("width", in: attrs), let height = numberAttr("height", in: attrs) else { continue }
            let x = numberAttr("x", in: attrs) ?? 0
            let y = numberAttr("y", in: attrs) ?? 0
            let origin = transform.apply(VectorPoint(x: x, y: y))
            let scaledWidth = width * transform.scaleX
            let scaledHeight = height * transform.scaleY
            let minX = min(origin.x, origin.x + scaledWidth)
            let minY = min(origin.y, origin.y + scaledHeight)
            shapes.append(.rectangle(
                origin: VectorPoint(x: minX, y: minY),
                width: abs(scaledWidth), height: abs(scaledHeight)
            ))
        }

        // <circle cx cy r>
        for attrs in elementAttributes(named: "circle", in: svgString) {
            guard let radius = numberAttr("r", in: attrs) else { continue }
            let center = transform.apply(pointAttr(cx: "cx", cy: "cy", in: attrs))
            shapes.append(.circle(center: center, radius: radius * transform.radiusScale))
        }

        // <ellipse cx cy rx ry>
        for attrs in elementAttributes(named: "ellipse", in: svgString) {
            guard let radiusX = numberAttr("rx", in: attrs), let radiusY = numberAttr("ry", in: attrs) else { continue }
            let center = transform.apply(pointAttr(cx: "cx", cy: "cy", in: attrs))
            shapes.append(.ellipse(center: center, radiusX: radiusX * abs(transform.scaleX), radiusY: radiusY * abs(transform.scaleY)))
        }

        // <line x1 y1 x2 y2>
        for attrs in elementAttributes(named: "line", in: svgString) {
            guard let x1 = numberAttr("x1", in: attrs), let y1 = numberAttr("y1", in: attrs),
                  let x2 = numberAttr("x2", in: attrs), let y2 = numberAttr("y2", in: attrs) else { continue }
            let start = transform.apply(VectorPoint(x: x1, y: y1))
            let end = transform.apply(VectorPoint(x: x2, y: y2))
            shapes.append(.line(start: start, end: end))
        }

        // <polyline points="x,y x,y ...">
        for attrs in elementAttributes(named: "polyline", in: svgString) {
            guard let pointsString = stringAttr("points", in: attrs) else { continue }
            let pairs = numberPairs(in: pointsString)
            guard pairs.count >= 2 else { continue }
            shapes.append(.freehand(points: pairs.map { transform.apply($0) }))
        }

        // <polygon points="x,y x,y ..."> — closed
        for attrs in elementAttributes(named: "polygon", in: svgString) {
            guard let pointsString = stringAttr("points", in: attrs) else { continue }
            let pairs = numberPairs(in: pointsString)
            guard pairs.count >= 3 else { continue }
            var points = pairs.map { transform.apply($0) }
            if abs(points.first!.x - points.last!.x) > 1e-6 || abs(points.first!.y - points.last!.y) > 1e-6 {
                points.append(points[0])
            }
            shapes.append(.freehand(points: points))
        }

        return shapes
    }

    /// Capture the attribute string of every occurrence of the given element.
    private static func elementAttributes(named element: String, in svgString: String) -> [String] {
        let pattern = "<\(element)\\b([^>]*)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(svgString.startIndex..., in: svgString)
        var results: [String] = []
        for match in regex.matches(in: svgString, options: [], range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: svgString) else { continue }
            results.append(String(svgString[attrsRange]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return results
    }

    private static func stringAttr(_ name: String, in attrs: String) -> String? {
        let pattern = "\(name)\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: attrs, options: [], range: NSRange(attrs.startIndex..., in: attrs)),
              let valueRange = Range(match.range(at: 1), in: attrs) else { return nil }
        return String(attrs[valueRange])
    }

    private static func numberAttr(_ name: String, in attrs: String) -> Double? {
        stringAttr(name, in: attrs).flatMap { Double($0) }
    }

    private static func pointAttr(cx: String, cy: String, in attrs: String) -> VectorPoint {
        VectorPoint(
            x: numberAttr(cx, in: attrs) ?? 0,
            y: numberAttr(cy, in: attrs) ?? 0
        )
    }

    /// Parse a whitespace/comma-separated number list into pairs of points.
    private static func numberPairs(in string: String) -> [VectorPoint] {
        let values = numbers(in: string)
        var points: [VectorPoint] = []
        var index = 0
        while index + 1 < values.count {
            points.append(VectorPoint(x: values[index], y: values[index + 1]))
            index += 2
        }
        return points
    }

    /// Parse a whitespace/comma-separated number list.
    private static func numbers(in string: String) -> [Double] {
        let pattern = #"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, options: [], range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 0), in: string) else { return nil }
            return Double(String(string[valueRange]))
        }
    }

    // MARK: - Tokenization

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

            commands.append(SVGPathCommand(type: commandType, values: values))
        }

        return commands
    }
}

// MARK: - SVG Path Command

/// A single tokenized SVG path command.
struct SVGPathCommand {
    let type: String  // M, L, H, V, C, S, Q, T, A, Z (or lowercase variants)
    let values: [Double]
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
