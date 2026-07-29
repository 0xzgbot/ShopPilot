import Foundation

// MARK: - Types

public enum PreflightIssueType: String, Codable {
    case openPath
    case selfIntersection
    case gap
    case degenerate
    case overlap
}

public enum PreflightSeverity: String, Codable, Comparable {
    case info
    case warning
    case error

    public static func < (lhs: PreflightSeverity, rhs: PreflightSeverity) -> Bool {
        let order: [PreflightSeverity] = [.info, .warning, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public struct PreflightResult: Identifiable, Codable {
    public let id: UUID
    public let issue: PreflightIssueType
    public let severity: PreflightSeverity
    public var message: String
    public var affectedShapeIds: [UUID]
    public var suggestedFix: String?

    public init(
        id: UUID = UUID(),
        issue: PreflightIssueType,
        severity: PreflightSeverity,
        message: String,
        affectedShapeIds: [UUID] = [],
        suggestedFix: String? = nil
    ) {
        self.id = id
        self.issue = issue
        self.severity = severity
        self.message = message
        self.affectedShapeIds = affectedShapeIds
        self.suggestedFix = suggestedFix
    }
}

public struct PreflightReport: Identifiable, Codable {
    public let id: UUID
    public var issues: [PreflightResult]
    public var isClean: Bool { issues.isEmpty }
    public var worstSeverity: PreflightSeverity { issues.map(\.severity).min() ?? .info }

    public init(id: UUID = UUID(), issues: [PreflightResult] = []) {
        self.id = id
        self.issues = issues
    }
}

// MARK: - Vector Preflight Doctor

public final class VectorPreflight {

    public static let defaultTolerance: Double = 1e-4

    public static func check(
        shapes: [VectorShape],
        tolerance: Double = defaultTolerance
    ) -> PreflightReport {
        var issues: [PreflightResult] = []
        let shapeIds = shapes.enumerated().map { index, _ in UUID() }

        for (index, shape) in shapes.enumerated() {
            if isDegenerate(shape, tolerance: tolerance) {
                issues.append(PreflightResult(
                    issue: .degenerate,
                    severity: .warning,
                    message: descriptionForDegenerate(shape),
                    affectedShapeIds: [shapeIds[index]],
                    suggestedFix: "Remove or repair shape."
                ))
            }

            if !isClosedShape(shape) {
                issues.append(PreflightResult(
                    issue: .openPath,
                    severity: .error,
                    message: "Open vector detected.",
                    affectedShapeIds: [shapeIds[index]],
                    suggestedFix: "Join endpoints or close before cutting."
                ))
            }

            if let pts = freehandPoints(shape), pts.count >= 3, intersectsSelf(points: pts) {
                issues.append(PreflightResult(
                    issue: .selfIntersection,
                    severity: .warning,
                    message: "Path intersects itself.",
                    affectedShapeIds: [shapeIds[index]],
                    suggestedFix: "Edit control points to remove crossings."
                ))
            }
        }

        for i in 0..<shapes.count {
            for j in (i + 1)..<shapes.count {
                if shapes[i].boundingRect.abuts(shapes[j].boundingRect, tolerance: tolerance) { continue }
                issues.append(PreflightResult(
                    issue: .gap,
                    severity: .info,
                    message: "Gap detected between shapes.",
                    affectedShapeIds: [shapeIds[i], shapeIds[j]],
                    suggestedFix: "Join endpoints if they are meant to be continuous."
                ))
            }
        }

        return PreflightReport(issues: issues)
    }

    // MARK: - Private helpers

    private static func isDegenerate(_ shape: VectorShape, tolerance: Double) -> Bool {
        if isDegenerateFreehand(shape, tolerance: tolerance) { return true }

        switch shape {
        case .line(let start, let end):
            return hypot(start.x - end.x, start.y - end.y) <= tolerance
        case .circle(_, let radius):
            return radius <= tolerance
        case .rectangle(_, let width, let height):
            return abs(width) <= tolerance || abs(height) <= tolerance
        case .arc(_, let radius, _, _):
            return radius <= tolerance
        case .ellipse(_, let rx, let ry, _):
            return rx <= tolerance || ry <= tolerance
        case .polygon(_, let radius, _, _):
            return radius <= tolerance
        case .star(_, let outerRadius, let innerRadius, _, _):
            return outerRadius <= tolerance || innerRadius <= tolerance
        case .freehand(let pts):
            return pts.count < 2
        }
    }

    private static func isDegenerateFreehand(_ shape: VectorShape, tolerance: Double) -> Bool {
        guard case .freehand(let pts) = shape else { return false }
        return pts.count < 2
    }

    private static func freehandPoints(_ shape: VectorShape) -> [VectorPoint]? {
        if case .freehand(let pts) = shape { return pts }
        return nil
    }

    private static func descriptionForDegenerate(_ shape: VectorShape) -> String {
        switch shape {
        case .line: return "Zero-length line detected."
        case .circle: return "Zero-radius circle detected."
        case .rectangle: return "Zero-area rectangle detected."
        case .arc: return "Zero-radius arc detected."
        case .ellipse: return "Zero-radius ellipse detected."
        case .polygon: return "Zero-radius polygon detected."
        case .star: return "Degenerate star detected."
        case .freehand: return "Insufficient points for freehand path."
        }
    }

    private static func isClosedShape(_ shape: VectorShape) -> Bool {
        switch shape {
        case .circle, .rectangle, .ellipse, .polygon, .star:
            return true
        case .arc, .line, .freehand:
            return false
        }
    }

    private static func intersectsSelf(points: [VectorPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        for i in 0..<(points.count - 1) {
            for j in (i + 1)..<(points.count - 1) {
                if j == i || j == i + 1 || j + 1 == i { continue }
                let a = (points[i], points[i + 1])
                let b = (points[j], points[j + 1])
                if segmentsIntersect(a, b) { return true }
            }
        }
        return false
    }

    private static func segmentsIntersect(
        _ a: (VectorPoint, VectorPoint),
        _ b: (VectorPoint, VectorPoint)
    ) -> Bool {
        let (a1, a2) = a
        let (b1, b2) = b

        let d1 = direction(b1, b2, a1)
        let d2 = direction(b1, b2, a2)
        let d3 = direction(a1, a2, b1)
        let d4 = direction(a1, a2, b2)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
            ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        if d1 == 0 && onSegment(b1, b2, a1) { return true }
        if d2 == 0 && onSegment(b1, b2, a2) { return true }
        if d3 == 0 && onSegment(a1, a2, b1) { return true }
        if d4 == 0 && onSegment(a1, a2, b2) { return true }

        return false
    }

    private static func direction(_ from: VectorPoint, _ to: VectorPoint, _ p: VectorPoint) -> Double {
        (to.x - from.x) * (p.y - from.y) - (to.y - from.y) * (p.x - from.x)
    }

    private static func onSegment(_ a: VectorPoint, _ b: VectorPoint, _ p: VectorPoint) -> Bool {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x)
        let minY = min(a.y, b.y), maxY = max(a.y, b.y)
        return p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }
}

private extension Rect {
    func abuts(_ other: Rect, tolerance: Double) -> Bool {
        let a = Rect(
            minX: minX - tolerance, minY: minY - tolerance,
            maxX: maxX + tolerance, maxY: maxY + tolerance
        )
        return a.minX <= other.maxX && a.maxX >= other.minX && a.minY <= other.maxY && a.maxY >= other.minY
    }
}
