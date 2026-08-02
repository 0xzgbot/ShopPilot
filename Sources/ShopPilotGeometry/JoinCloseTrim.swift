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
        var points = [start, end]
        
        let edges: [(minOrMax: Bool, axis: Int)] = [
            (false, 0), (true, 0), (false, 1), (true, 1)
        ]
        
        for edge in edges {
            var newPoints: [VectorPoint] = []
            
            for i in 0..<points.count {
                let current = points[i]
                let next = points[(i + 1) % points.count]
                
                let currentInside = edge.axis == 0
                    ? (edge.minOrMax ? current.x <= rect.maxX : current.x >= rect.minX)
                    : (edge.minOrMax ? current.y <= rect.maxY : current.y >= rect.minY)
                
                let nextInside = edge.axis == 0
                    ? (edge.minOrMax ? next.x <= rect.maxX : next.x >= rect.minX)
                    : (edge.minOrMax ? next.y <= rect.maxY : next.y >= rect.minY)
                
                if currentInside {
                    newPoints.append(current)
                }
                
                if currentInside != nextInside {
                    let t = computeIntersectionT(start: current, end: next, edge: edge, rect: rect)
                    if t >= 0 && t <= 1 {
                        let intersect = VectorPoint(
                            x: current.x + t * (next.x - current.x),
                            y: current.y + t * (next.y - current.y)
                        )
                        newPoints.append(intersect)
                    }
                }
            }
            
            points = newPoints
            if points.isEmpty { return [] }
        }
        
        return Array(points.prefix(2))
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
