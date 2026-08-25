import Foundation

// MARK: - Join Result

public struct JoinResult: Identifiable, Codable {
    public let id: UUID
    public let operation: String
    public private(set) var outputShapes: [VectorShape]
    public let timestamp: Date

    public init(id: UUID = UUID(), operation: String, outputShapes: [VectorShape]) {
        self.id = id
        self.operation = operation
        self.outputShapes = outputShapes
        self.timestamp = Date()
    }
}

// MARK: - Apply Result (SPK-2020a0)

/// Counts returned by `ShapeJoinEngine.applyJoinAndCleanup(_:tolerance:)`.
public struct JoinApplyResult: Equatable {
    /// Number of polyline merge operations performed (each reduces the shape
    /// count by one).
    public let joinedCount: Int
    /// Number of resulting polylines whose start/end lie within tolerance,
    /// i.e. chains that now form a closed loop (first ≈ last).
    public let closedCount: Int
    /// Number of zero-span/degenerate shapes deleted.
    public let removedCount: Int
    /// Shape count after the mutation (`shapes.count` post-call).
    public let remaining: Int

    public init(joinedCount: Int, closedCount: Int, removedCount: Int, remaining: Int) {
        self.joinedCount = joinedCount
        self.closedCount = closedCount
        self.removedCount = removedCount
        self.remaining = remaining
    }
}

// MARK: - Join/Close Engine

public final class ShapeJoinEngine {
    
    public static func joinLines(_ a: VectorShape, _ b: VectorShape) -> [VectorShape]? {
        guard case .line(let aStart, let aEnd) = a else { return nil }
        guard case .line(let bStart, let bEnd) = b else { return nil }
        
        let tolerance: Double = 1e-6
        
        if hypot(aEnd.x - bStart.x, aEnd.y - bStart.y) <= tolerance {
            return [.line(start: aStart, end: bEnd)]
        } else if hypot(aEnd.x - bEnd.x, aEnd.y - bEnd.y) <= tolerance {
            return [.line(start: aStart, end: bStart)]
        } else if hypot(aStart.x - bStart.x, aStart.y - bStart.y) <= tolerance {
            return [.line(start: bEnd, end: aEnd)]
        } else if hypot(aStart.x - bEnd.x, aStart.y - bEnd.y) <= tolerance {
            return [.line(start: bEnd, end: aEnd)]
        }
        
        return nil
    }
    
    // MARK: - Polyline helpers

    /// Extract the two endpoints of a polyline (freehand with 2+ points).
    /// Returns (start, end) where start = points[0] and end = points.last.
    private static func polylineEndpoints(_ shape: VectorShape) -> (VectorPoint, VectorPoint)? {
        guard case .freehand(let points) = shape, points.count >= 2 else { return nil }
        return (points[0], points[points.count - 1])
    }

    /// Join two polylines (freehand with 2+ points) if one endpoint of *a*
    /// coincides with one endpoint of *b* within tolerance.  Returns a single
    /// freehand polyline whose points are the concatenation of the two inputs
    /// (with the coincident endpoint removed).  Returns nil if no join is
    /// possible.
    public static func joinPolylines(_ a: VectorShape, _ b: VectorShape) -> VectorShape? {
        guard case .freehand(let aPts) = a, aPts.count >= 2 else { return nil }
        guard case .freehand(let bPts) = b, bPts.count >= 2 else { return nil }

        let aStart = aPts[0]
        let aEnd = aPts[aPts.count - 1]
        let bStart = bPts[0]
        let bEnd = bPts[bPts.count - 1]
        let tolerance: Double = 1e-6

        // a-end connects to b-start  →  aPts + bPts[1...]
        if hypot(aEnd.x - bStart.x, aEnd.y - bStart.y) <= tolerance {
            var merged = aPts
            merged.append(contentsOf: bPts.dropFirst())
            return .freehand(points: merged)
        }
        // a-end connects to b-end  →  aPts + reversed(bPts)
        if hypot(aEnd.x - bEnd.x, aEnd.y - bEnd.y) <= tolerance {
            var merged = aPts
            merged.append(contentsOf: bPts.reversed().dropFirst())
            return .freehand(points: merged)
        }
        // a-start connects to b-start  →  reversed(aPts) + bPts
        if hypot(aStart.x - bStart.x, aStart.y - bStart.y) <= tolerance {
            var merged = Array(aPts.reversed().dropLast())
            merged.append(contentsOf: bPts)
            return .freehand(points: merged)
        }
        // a-start connects to b-end  →  reversed(aPts) + reversed(bPts)
        if hypot(aStart.x - bEnd.x, aStart.y - bEnd.y) <= tolerance {
            var merged = Array(aPts.reversed().dropLast())
            merged.append(contentsOf: bPts.reversed())
            return .freehand(points: merged)
        }

        return nil
    }

    // MARK: - Gap-tolerance join + zero-span delete (SPK-2020a0)

    /// Legacy exact-coincidence epsilon used by `joinLines`/`joinPolylines`.
    /// `tolerance = 0` clamps up to this so zero-tolerance calls reproduce
    /// today's behaviour bit-for-bit.
    private static let legacyEpsilon: Double = 1e-6

    /// Epsilon below which a shape is considered degenerate (zero span).
    private static let zeroSpanEpsilon: Double = 1e-9

    private static func near(_ a: VectorPoint, _ b: VectorPoint, _ eps: Double) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= eps
    }

    /// Chain freehand polylines whose endpoints lie within `tolerance`
    /// (default 0.1 mm) into single polylines. Non-freehand shapes and
    /// unattached polylines pass through untouched, in original order.
    ///
    /// `tolerance = 0` reproduces today's behaviour exactly (clamped to the
    /// legacy 1e-6 exact-coincidence epsilon used by `joinPolylines`).
    ///
    /// Returns `(joined, remaining)` — merged chains first, then everything
    /// that was not part of a chain — mirroring `joinLines(_:)`'s shape.
    @discardableResult
    public static func joinAll(shapes: [VectorShape], tolerance: Double = 0.1)
        -> ([VectorShape], [VectorShape])
    {
        let detailed = joinAllDetailed(shapes: shapes, tolerance: tolerance)
        return (detailed.chains, detailed.remaining)
    }

    /// Internal worker that also reports how many merge operations occurred.
    private static func joinAllDetailed(shapes: [VectorShape], tolerance: Double)
        -> (chains: [VectorShape], remaining: [VectorShape], mergeCount: Int)
    {
        guard !shapes.isEmpty else { return ([], [], 0) }
        let eps = Swift.max(tolerance, legacyEpsilon)

        struct PolyInfo {
            let points: [VectorPoint]
            let sourceIndex: Int
        }

        var polys: [PolyInfo] = []
        for (index, shape) in shapes.enumerated() {
            if case .freehand(let p) = shape, p.count >= 2 {
                polys.append(PolyInfo(points: p, sourceIndex: index))
            }
        }

        var chains: [VectorShape] = []
        var remaining: [VectorShape] = []
        var usedSource: Set<Int> = []
        var mergedSource: Set<Int> = []   // sources absorbed into a multi-shape chain
        var totalMerges = 0

        for i in polys.indices where !usedSource.contains(polys[i].sourceIndex) {
            var chain = polys[i].points
            var chainMerges = 0
            var chainSources: Set<Int> = [polys[i].sourceIndex]
            usedSource.insert(polys[i].sourceIndex)

            var changed = true
            while changed {
                changed = false
                for j in polys.indices where !usedSource.contains(polys[j].sourceIndex) {
                    let cStart = chain[0]
                    let cEnd = chain[chain.count - 1]
                    let pStart = polys[j].points[0]
                    let pEnd = polys[j].points[polys[j].points.count - 1]

                    if near(cEnd, pStart, eps) {
                        // chain-end → candidate-start: plain concatenation,
                        // dropping the coincident duplicate.
                        chain.append(contentsOf: polys[j].points.dropFirst())
                        usedSource.insert(polys[j].sourceIndex)
                        chainSources.insert(polys[j].sourceIndex)
                        chainMerges += 1
                        changed = true
                    } else if near(cEnd, pEnd, eps) {
                        // chain-end → candidate-end: append candidate reversed.
                        chain.append(contentsOf: polys[j].points.reversed().dropFirst())
                        usedSource.insert(polys[j].sourceIndex)
                        chainSources.insert(polys[j].sourceIndex)
                        chainMerges += 1
                        changed = true
                    } else if near(cStart, pStart, eps) {
                        // chain-start → candidate-start: prepend reversed chain.
                        var merged = Array(chain.reversed().dropLast())
                        merged.append(contentsOf: polys[j].points)
                        chain = merged
                        usedSource.insert(polys[j].sourceIndex)
                        chainSources.insert(polys[j].sourceIndex)
                        chainMerges += 1
                        changed = true
                    } else if near(cStart, pEnd, eps) {
                        // chain-start → candidate-end: run from candidate start
                        // through the coincident pair to chain end.
                        var merged = Array(polys[j].points.reversed().dropLast())
                        merged.append(contentsOf: chain)
                        chain = merged
                        usedSource.insert(polys[j].sourceIndex)
                        chainSources.insert(polys[j].sourceIndex)
                        chainMerges += 1
                        changed = true
                    }
                }
            }

            // A chain that absorbed nothing is NOT a join result — it passes
            // through untouched (mirrors joinLines' semantics).
            if chainMerges > 0 {
                chains.append(.freehand(points: chain))
                mergedSource.formUnion(chainSources)
                totalMerges += chainMerges
            }
        }

        // Non-polyline shapes and unattached/unmerged polylines pass through
        // untouched, in original input order.
        for (index, shape) in shapes.enumerated() where !mergedSource.contains(index) {
            remaining.append(shape)
        }

        return (chains, remaining, totalMerges)
    }

    /// True when `shape` is degenerate: zero length/area footprint, fewer
    /// than two usable points, or non-positive radii/dimensions.
    public static func isZeroSpan(_ shape: VectorShape) -> Bool {
        let eps = zeroSpanEpsilon
        switch shape {
        case .line(let s, let e):
            return hypot(s.x - e.x, s.y - e.y) <= eps
        case .circle(_, let radius):
            return radius <= eps
        case .rectangle(_, let width, let height):
            return width <= eps || height <= eps
        case .arc(_, let radius, _, _):
            return radius <= eps
        case .ellipse(_, let radiusX, let radiusY, _):
            return radiusX <= eps || radiusY <= eps
        case .polygon(_, let radius, let sides, _):
            return radius <= eps || sides < 3
        case .star(_, let outerRadius, let innerRadius, let points, _):
            return outerRadius <= eps || innerRadius <= eps || points < 3
        case .freehand(let points):
            guard points.count >= 2, let first = points.first else { return true }
            for p in points where hypot(p.x - first.x, p.y - first.y) > eps {
                return false
            }
            return true
        }
    }

    /// Partition `shapes` into non-degenerate and degenerate (zero-span)
    /// shapes. Returns `(kept, removed)` with both lists in input order.
    public static func deleteZeroSpan(_ shapes: [VectorShape])
        -> (kept: [VectorShape], removed: [VectorShape])
    {
        var kept: [VectorShape] = []
        var removed: [VectorShape] = []
        kept.reserveCapacity(shapes.count)
        for shape in shapes {
            if isZeroSpan(shape) {
                removed.append(shape)
            } else {
                kept.append(shape)
            }
        }
        return (kept, removed)
    }

    /// Session-facing APPLY entry point (SPK-2020a0): joins gap-tolerant
    /// freehand polylines, deletes zero-span shapes, mutates `shapes` in
    /// place, and reports what happened so callers never apply a
    /// suggestedFix copy themselves.
    ///
    /// - Parameters:
    ///   - shapes: The session's live shape array; replaced with the cleaned result.
    ///   - tolerance: Endpoint gap tolerance in mm (`0` = legacy exact match).
    /// - Returns: `(joinedCount, closedCount, removedCount, remaining)` counts.
    @discardableResult
    public static func applyJoinAndCleanup(_ shapes: inout [VectorShape], tolerance: Double = 0.1)
        -> JoinApplyResult
    {
        let eps = Swift.max(tolerance, legacyEpsilon)

        let detail = joinAllDetailed(shapes: shapes, tolerance: tolerance)
        var output = detail.chains + detail.remaining

        // Count chains whose endpoints now meet within tolerance → closed loops.
        var closedCount = 0
        for shape in output {
            guard case .freehand(let p) = shape, p.count >= 2 else { continue }
            if near(p[0], p[p.count - 1], eps) { closedCount += 1 }
        }

        let (kept, removed) = deleteZeroSpan(output)
        output = kept
        shapes = output

        return JoinApplyResult(
            joinedCount: detail.mergeCount,
            closedCount: closedCount,
            removedCount: removed.count,
            remaining: output.count
        )
    }

    /// Close an open polyline (freehand with 2+ points) by appending a
    /// segment from the last point back to the first.  The original points
    /// are preserved; the closing segment is NOT added as a separate shape —
    /// instead the polyline is returned as-is (the caller may inspect
    /// `first == last` to know it is closed).  If the polyline is already
    /// closed (first point ≈ last point) the input is returned unchanged.
    public static func closePolyline(_ shape: VectorShape) -> [VectorShape] {
        guard case .freehand(let points) = shape, points.count >= 2 else {
            return [shape]
        }

        let first = points[0]
        let last = points[points.count - 1]

        if hypot(first.x - last.x, first.y - last.y) > 1e-6 {
            // Not yet closed — append the first point to the end.
            var closed = points
            closed.append(first)
            return [.freehand(points: closed)]
        }
        return [shape]
    }

    public static func joinLines(_ shapes: [VectorShape]) -> ([VectorShape], [VectorShape]) {
        guard !shapes.isEmpty else { return ([], []) }

        struct LineInfo {
            let shape: VectorShape
            let start: VectorPoint
            let end: VectorPoint
            let sourceIndex: Int
        }

        var lines: [LineInfo] = []
        for (index, shape) in shapes.enumerated() {
            if case .line(let s, let e) = shape {
                lines.append(LineInfo(shape: shape, start: s, end: e, sourceIndex: index))
            }
        }

        var result: [VectorShape] = []
        var remaining: [VectorShape] = []
        var usedSource: Set<Int> = []   // indices into the ORIGINAL shapes array

        for i in lines.indices where !usedSource.contains(lines[i].sourceIndex) {
            var chainStart = lines[i].start
            var chainEnd = lines[i].end
            usedSource.insert(lines[i].sourceIndex)

            var changed = true
            while changed {
                changed = false
                for j in lines.indices where !usedSource.contains(lines[j].sourceIndex) {
                    let distToStartA = hypot(chainStart.x - lines[j].start.x, chainStart.y - lines[j].start.y)
                    let distToEndA = hypot(chainStart.x - lines[j].end.x, chainStart.y - lines[j].end.y)
                    let distToStartB = hypot(chainEnd.x - lines[j].start.x, chainEnd.y - lines[j].start.y)
                    let distToEndB = hypot(chainEnd.x - lines[j].end.x, chainEnd.y - lines[j].end.y)

                    // When a candidate's endpoint coincides with the chain head,
                    // the chain must extend AWAY from that coincident point —
                    // i.e. the new head is the candidate's OTHER endpoint.
                    // (Previously the coincident point was assigned, so the chain
                    // never grew and segments were silently dropped. SPK review pass.)
                    if distToStartA <= 1e-6 {
                        chainStart = lines[j].end
                        usedSource.insert(lines[j].sourceIndex)
                        changed = true
                    } else if distToEndA <= 1e-6 {
                        chainStart = lines[j].start
                        usedSource.insert(lines[j].sourceIndex)
                        changed = true
                    } else if distToStartB <= 1e-6 {
                        chainEnd = lines[j].end
                        usedSource.insert(lines[j].sourceIndex)
                        changed = true
                    } else if distToEndB <= 1e-6 {
                        chainEnd = lines[j].start
                        usedSource.insert(lines[j].sourceIndex)
                        changed = true
                    }
                }
            }

            result.append(.line(start: chainStart, end: chainEnd))
        }

        // Non-line shapes and unattached lines pass through untouched.
        for (index, shape) in shapes.enumerated() where !usedSource.contains(index) {
            remaining.append(shape)
        }

        return (result, remaining)
    }
    
    public static func close(_ shape: VectorShape) -> [VectorShape] {
        switch shape {
        case .line(let start, let end):
            if hypot(start.x - end.x, start.y - end.y) > 1e-6 {
                return [.line(start: start, end: end), .line(start: end, end: start)]
            }
            return [shape]
        case .rectangle(let origin, let width, let height):
            return [shape]
        default:
            return [shape]
        }
    }
    
    public static func closeAll(_ shapes: [VectorShape]) -> ([VectorShape], [VectorShape]) {
        var closed: [VectorShape] = []
        var unclosed: [VectorShape] = []
        
        for shape in shapes {
            let result = close(shape)
            if result.count > 1 {
                closed.append(contentsOf: result)
            } else {
                unclosed.append(shape)
            }
        }
        
        return (closed, unclosed)
    }
    
    public static func trimToBox(_ shape: VectorShape, in box: Rect) -> [VectorShape] {
        let bounds = shape.boundingRect
        
        guard rectsOverlap(bounds, box) else { return [] }
        
        switch shape {
        case .rectangle(let origin, let width, let height):
            let minX = max(origin.x, box.minX)
            let minY = max(origin.y, box.minY)
            let maxX = min(origin.x + width, box.maxX)
            let maxY = min(origin.y + height, box.maxY)
            
            if minX < maxX && minY < maxY {
                return [.rectangle(origin: VectorPoint(x: minX, y: minY), width: maxX - minX, height: maxY - minY)]
            }
            return []
            
        case .line(let start, let end):
            var points = clipLineToRect(start, end, rect: box)
            if points.count >= 2 {
                return [.line(start: points[0], end: points[1])]
            }
            return []
            
        case .freehand(let points):
            // Closed polyline: Sutherland–Hodgman polygon clip against the box.
            if points.count >= 3, points.first == points.last {
                var clipped = clipPolygonToRect(points, rect: box)
                guard clipped.count >= 3 else { return [] }
                // The clip drops the duplicate closing vertex; restore the
                // closed-loop invariant (first == last).
                if clipped.first != clipped.last {
                    clipped.append(clipped[0])
                }
                return [.freehand(points: clipped)]
            }
            // Open polyline: clip each segment; keep maximal contiguous runs
            // (segments fully outside the box split the output into pieces).
            var kept: [VectorPoint] = []
            var output: [VectorShape] = []
            func flushRun() {
                if kept.count >= 2 {
                    output.append(.freehand(points: kept))
                }
                kept = []
            }
            for i in 0..<(points.count - 1) {
                let seg = clipLineToRect(points[i], points[i + 1], rect: box)
                if seg.count >= 2 {
                    if kept.isEmpty {
                        kept = seg
                    } else if seg.first == kept.last {
                        kept.append(contentsOf: seg.dropFirst())
                    } else {
                        flushRun()
                        kept = seg
                    }
                } else {
                    flushRun()
                }
            }
            flushRun()
            return output
            
        default:
            return [shape]
        }
    }
    
    public static func trimByLine(_ shape: VectorShape, cutStart: VectorPoint, cutEnd: VectorPoint) -> [VectorShape] {
        switch shape {
        case .rectangle(let origin, let width, let height):
            let corners: [VectorPoint] = [
                origin,
                VectorPoint(x: origin.x + width, y: origin.y),
                VectorPoint(x: origin.x + width, y: origin.y + height),
                VectorPoint(x: origin.x, y: origin.y + height)
            ]
            
            let kept = corners.filter { point in
                crossProduct(cutStart, cutEnd, point) >= 0
            }
            
            if kept.count >= 3 {
                let minX = kept.map(\.x).min() ?? origin.x
                let minY = kept.map(\.y).min() ?? origin.y
                let maxX = kept.map(\.x).max() ?? (origin.x + width)
                let maxY = kept.map(\.y).max() ?? (origin.y + height)
                
                if minX < maxX && minY < maxY {
                    return [.rectangle(origin: VectorPoint(x: minX, y: minY), width: maxX - minX, height: maxY - minY)]
                }
            }
            
            return kept.isEmpty ? [] : [shape]
            
        default:
            return [shape]
        }
    }
    
    private static func crossProduct(_ a: VectorPoint, _ b: VectorPoint, _ p: VectorPoint) -> Double {
        return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }
    
    private static func clipLineToRect(_ start: VectorPoint, _ end: VectorPoint, rect: Rect) -> [VectorPoint] {
        Array(clipPolygonToRect([start, end], rect: rect).prefix(2))
    }

    /// Sutherland–Hodgman polygon clip: keeps every vertex of `points` inside
    /// `rect`, inserting boundary intersections. Handles both closed loops
    /// (first == last) and open polylines; open inputs keep their endpoint
    /// structure unless the result is a single degenerate point.
    private static func clipPolygonToRect(_ points: [VectorPoint], rect: Rect) -> [VectorPoint] {
        var current = points
        guard !current.isEmpty else { return [] }

        let edges: [(minOrMax: Bool, axis: Int)] = [
            (false, 0), (true, 0), (false, 1), (true, 1)
        ]

        for edge in edges {
            guard !current.isEmpty else { return [] }
            var newPoints: [VectorPoint] = []

            for i in 0..<current.count {
                let currentPoint = current[i]
                let next = current[(i + 1) % current.count]

                let currentInside = edge.axis == 0
                    ? (edge.minOrMax ? currentPoint.x <= rect.maxX : currentPoint.x >= rect.minX)
                    : (edge.minOrMax ? currentPoint.y <= rect.maxY : currentPoint.y >= rect.minY)

                let nextInside = edge.axis == 0
                    ? (edge.minOrMax ? next.x <= rect.maxX : next.x >= rect.minX)
                    : (edge.minOrMax ? next.y <= rect.maxY : next.y >= rect.minY)

                if currentInside {
                    newPoints.append(currentPoint)
                }

                if currentInside != nextInside {
                    let t = computeIntersectionT(start: currentPoint, end: next, edge: edge, rect: rect)
                    if t >= 0 && t <= 1 {
                        let intersect = VectorPoint(
                            x: currentPoint.x + t * (next.x - currentPoint.x),
                            y: currentPoint.y + t * (next.y - currentPoint.y)
                        )
                        newPoints.append(intersect)
                    }
                }
            }

            current = newPoints
        }

        return current
    }
    
    private static func computeIntersectionT(start: VectorPoint, end: VectorPoint, edge: (minOrMax: Bool, axis: Int), rect: Rect) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        
        if dx == 0 && dy == 0 { return 0 }
        
        var t: Double = 0
        
        if edge.axis == 0 {
            let value = edge.minOrMax ? rect.maxX : rect.minX
            if abs(dx) > 1e-10 {
                t = (value - start.x) / dx
            } else {
                return -1
            }
        } else {
            let value = edge.minOrMax ? rect.maxY : rect.minY
            if abs(dy) > 1e-10 {
                t = (value - start.y) / dy
            } else {
                return -1
            }
        }
        
        return t
    }
}

private func rectsOverlap(_ a: Rect, _ b: Rect) -> Bool {
    return a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
}
