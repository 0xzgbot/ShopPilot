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
    /// SPK-0211+0212 — real indices into the session's `shapes` array, so the
    /// UI can select the offending shapes (the fabricated UUIDs above are kept
    /// for backward compatibility but are not usable for selection).
    public var affectedShapeIndices: [Int]
    public var suggestedFix: String?

    public init(
        id: UUID = UUID(),
        issue: PreflightIssueType,
        severity: PreflightSeverity,
        message: String,
        affectedShapeIds: [UUID] = [],
        affectedShapeIndices: [Int] = [],
        suggestedFix: String? = nil
    ) {
        self.id = id
        self.issue = issue
        self.severity = severity
        self.message = message
        self.affectedShapeIds = affectedShapeIds
        self.affectedShapeIndices = affectedShapeIndices
        self.suggestedFix = suggestedFix
    }
}

public struct PreflightReport: Identifiable, Codable {
    public let id: UUID
    public var issues: [PreflightResult]
    public var isClean: Bool { issues.isEmpty }
    public var worstSeverity: PreflightSeverity { issues.map(\.severity).max() ?? .info }

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
        // SPK-0211+0212: real indices into the caller's shapes array — the UI
        // selects offending shapes from these. The id-bearing Shape IDs are
        // unavailable here (VectorShape is a value enum), so indices are the
        // honest identity.
        for (index, shape) in shapes.enumerated() {
            if isDegenerate(shape, tolerance: tolerance) {
                issues.append(PreflightResult(
                    issue: .degenerate,
                    severity: .warning,
                    message: descriptionForDegenerate(shape),
                    affectedShapeIndices: [index],
                    suggestedFix: "Remove or repair shape."
                ))
            }

            if !isClosedShape(shape, tolerance: tolerance) {
                issues.append(PreflightResult(
                    issue: .openPath,
                    severity: .error,
                    message: "Open vector detected.",
                    affectedShapeIndices: [index],
                    suggestedFix: "Join endpoints or close before cutting."
                ))
            }

            if let pts = freehandPoints(shape), pts.count >= 3, intersectsSelf(points: pts) {
                issues.append(PreflightResult(
                    issue: .selfIntersection,
                    severity: .warning,
                    message: "Path intersects itself.",
                    affectedShapeIndices: [index],
                    suggestedFix: "Edit control points to remove crossings."
                ))
            }
        }

        // Gap probe: flag only shapes that are NEAR each other but not
        // touching (within `gapProbeDistance`) — a real "meant to be joined
        // but not quite" gap. Shapes that are far apart are separate design
        // elements, not gaps.
        let gapProbeDistance: Double = max(tolerance * 100, 1.0)
        for i in 0..<shapes.count {
            for j in (i + 1)..<shapes.count {
                let a = shapes[i].boundingRect
                let b = shapes[j].boundingRect
                if a.abuts(b, tolerance: tolerance) { continue }  // touching/overlapping: fine
                if !a.near(b, distance: gapProbeDistance) { continue }  // far apart: not a gap
                issues.append(PreflightResult(
                    issue: .gap,
                    severity: .info,
                    message: "Gap detected between shapes \(i + 1) and \(j + 1).",
                    affectedShapeIndices: [i, j],
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

    private static func isClosedShape(_ shape: VectorShape, tolerance: Double) -> Bool {
        switch shape {
        case .circle, .rectangle, .ellipse, .polygon, .star:
            return true
        case .arc, .line:
            return false
        case .freehand(let pts):
            // A freehand path whose first and last points coincide is closed
            // (e.g. a hand-drawn rectangle) and must not be flagged open.
            guard let first = pts.first, let last = pts.last, pts.count >= 3 else { return false }
            return hypot(first.x - last.x, first.y - last.y) <= tolerance
        }
    }

    private static func intersectsSelf(points: [VectorPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        for i in 0..<(points.count - 1) {
            for j in (i + 1)..<(points.count - 1) {
                // Skip pairs sharing an endpoint — covers adjacent segments
                // AND the closing segment of a closed path (whose end touches
                // the first segment's start at the closure vertex). Touching
                // at a vertex is not a crossing.
                if segmentsShareEndpoint((points[i], points[i + 1]), (points[j], points[j + 1])) { continue }
                let a = (points[i], points[i + 1])
                let b = (points[j], points[j + 1])
                if segmentsIntersect(a, b) { return true }
            }
        }
        return false
    }

    private static func segmentsShareEndpoint(
        _ a: (VectorPoint, VectorPoint),
        _ b: (VectorPoint, VectorPoint)
    ) -> Bool {
        let (a1, a2) = a
        let (b1, b2) = b
        let coincident = { (p: VectorPoint, q: VectorPoint) in
            hypot(p.x - q.x, p.y - q.y) <= 1e-9
        }
        return coincident(a1, b1) || coincident(a1, b2) || coincident(a2, b1) || coincident(a2, b2)
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

    /// True when the gap between the two rects is within `distance` (i.e. they
    /// are near enough to plausibly be meant as one continuous contour).
    func near(_ other: Rect, distance: Double) -> Bool {
        let dx = max(0, max(minX, other.minX) - min(maxX, other.maxX))
        let dy = max(0, max(minY, other.minY) - min(maxY, other.maxY))
        return hypot(dx, dy) <= distance
    }
}

// MARK: - Plain-English Fix Actions

public extension VectorPreflight {

    /// SPK-0604 — V-Carve preflight gate. V-Carve needs closed vectors; open
    /// vectors would engrave a dangling path. Returns the blocking report
    /// (nil = safe to carve): any open-vector issue is a hard block with a
    /// plain-English fix CTA ("Close open vector"). Non-open issues
    /// (degenerate/gap/self-intersection) are surfaced as warnings but do not
    /// block the carve.
    static func vCarveGate(shapes: [VectorShape], tolerance: Double = defaultTolerance) -> PreflightReport? {
        let report = check(shapes: shapes, tolerance: tolerance)
        let openIssues = report.issues.filter { $0.issue == .openPath }
        guard !openIssues.isEmpty else { return nil }
        // Keep the full report so the fix CTA list shows everything, but the
        // gate decision is driven by open vectors.
        return report
    }

    /// Generate plain-English fix actions from a `PreflightReport`.
    /// Suitable for `List` / `ForEach` in SwiftUI.
    static func fixActions(for report: PreflightReport) -> [FixAction] {
        report.issues.map { issue in
            FixAction(
                title: title(for: issue),
                body: body(for: issue),
                severity: issue.severity,
                affectedShapeIds: issue.affectedShapeIds,
                affectedShapeIndices: issue.affectedShapeIndices,
                suggestedFix: issue.suggestedFix
            )
        }
    }

    static func title(for issue: PreflightResult) -> String {
        switch issue.issue {
        case .openPath:
            return "Close open vector"
        case .selfIntersection:
            return "Remove self-intersection"
        case .gap:
            return "Bridge gap"
        case .degenerate:
            return "Remove degenerate shape"
        case .overlap:
            return "Review overlapping shapes"
        }
    }

    static func body(for issue: PreflightResult) -> String {
        issue.message.isEmpty ? issue.suggestedFix ?? "Review and fix." : issue.message
    }
}

public struct FixAction: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var body: String
    public let severity: PreflightSeverity
    public var affectedShapeIds: [UUID]
    public var affectedShapeIndices: [Int]
    public var suggestedFix: String?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        severity: PreflightSeverity,
        affectedShapeIds: [UUID] = [],
        affectedShapeIndices: [Int] = [],
        suggestedFix: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.severity = severity
        self.affectedShapeIds = affectedShapeIds
        self.affectedShapeIndices = affectedShapeIndices
        self.suggestedFix = suggestedFix
    }
}
