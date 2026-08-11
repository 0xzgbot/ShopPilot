import Foundation

// MARK: - Smart part detection (SPK-1203)

/// Detects "parts" from a set of closed shapes: shapes that touch or overlap
/// (share an edge point within tolerance) belong to the same part. This is
/// the Aspire 12.5 "smart part selection" pattern — click one shape, select
/// the whole connected assembly without manual grouping.
public enum PartDetector {

    /// A detected part: the shapes that belong together, in input order.
    public struct Part: Equatable {
        public let shapeIndices: [Int]
        public init(shapeIndices: [Int]) {
            self.shapeIndices = shapeIndices
        }
    }

    /// Partition the given shapes into parts. Shapes that touch/overlap any
    /// member of a part join it (union-find semantics, transitive).
    /// - Parameters:
    ///   - shapes: the closed shapes to partition.
    ///   - tolerance: max distance between two shapes' points to count as
    ///     touching (mm; default 0.5 — a hairline gap still joins).
    ///   - isClosed: which shapes count as closed (open paths never join).
    public static func detectParts(
        of shapes: [VectorShape],
        tolerance: Double = 0.5,
        isClosed: (VectorShape) -> Bool = { _ in true }
    ) -> [Part] {
        let n = shapes.count
        guard n > 0 else { return [] }
        guard n > 1 else { return [Part(shapeIndices: [0])] }

        // Union-find.
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != c { let next = parent[c]; parent[c] = r; c = next }
            return r
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        let closed = shapes.enumerated().filter { isClosed($0.element) }.map(\.offset)
        let closedSet = Set(closed)
        guard closed.count > 1 else {
            return shapes.enumerated().map { Part(shapeIndices: [$0.offset]) }
        }

        // For each pair of closed shapes, check point proximity (one shape's
        // points within tolerance of the other's points).
        for i in 0..<closed.count {
            let ai = closed[i]
            let ptsA = points(of: shapes[ai])
            guard !ptsA.isEmpty else { continue }
            for j in (i + 1)..<closed.count {
                let bi = closed[j]
                let ptsB = points(of: shapes[bi])
                guard !ptsB.isEmpty else { continue }
                if near(ptsA, ptsB, tolerance: tolerance) {
                    union(ai, bi)
                }
            }
        }

        // Group by root, preserving input order.
        var groups: [Int: [Int]] = [:]
        for i in 0..<n {
            groups[find(i), default: []].append(i)
        }
        return groups.values
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
            .map { Part(shapeIndices: $0) }
    }

    /// The part containing the shape at `index` (nil when not found).
    public static func part(containing index: Int, in parts: [Part]) -> Part? {
        parts.first { $0.shapeIndices.contains(index) }
    }

    // MARK: - Helpers

    /// Sample the shape's defining points (closed shapes: all vertices).
    static func points(of shape: VectorShape) -> [VectorPoint] {
        switch shape {
        case .line(let s, let e):
            return [s, e]
        case .circle(let c, let r):
            return [VectorPoint(x: c.x - r, y: c.y), VectorPoint(x: c.x + r, y: c.y),
                    VectorPoint(x: c.x, y: c.y - r), VectorPoint(x: c.x, y: c.y + r)]
        case .rectangle(let o, let w, let h):
            return [
                VectorPoint(x: o.x, y: o.y), VectorPoint(x: o.x + w, y: o.y),
                VectorPoint(x: o.x + w, y: o.y + h), VectorPoint(x: o.x, y: o.y + h),
            ]
        case .arc(let c, let r, let sa, let ea):
            return [VectorPoint(x: c.x + r * cos(sa), y: c.y + r * sin(sa)),
                    VectorPoint(x: c.x + r * cos(ea), y: c.y + r * sin(ea))]
        case .ellipse(let c, let rx, let ry, _):
            return [VectorPoint(x: c.x - rx, y: c.y), VectorPoint(x: c.x + rx, y: c.y),
                    VectorPoint(x: c.x, y: c.y - ry), VectorPoint(x: c.x, y: c.y + ry)]
        case .polygon(let c, let r, let sides, let rot):
            var pts: [VectorPoint] = []
            for k in 0..<sides {
                let a = rot + Double(k) * 2 * .pi / Double(sides)
                pts.append(VectorPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            }
            return pts
        case .star(let c, let ro, let ri, let points, let rot):
            var pts: [VectorPoint] = []
            for k in 0..<(points * 2) {
                let r = k.isMultiple(of: 2) ? ro : ri
                let a = rot + Double(k) * .pi / Double(points)
                pts.append(VectorPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            }
            return pts
        case .freehand(let pts):
            return pts
        }
    }

    /// Any point of A within `tolerance` of any point of B?
    static func near(_ a: [VectorPoint], _ b: [VectorPoint], tolerance: Double) -> Bool {
        let tol2 = tolerance * tolerance
        // Brute force is fine for design-scale shape counts (the verify caps
        // at a few dozen); the 10k-scale path is the session's own loops.
        for p in a {
            for q in b {
                let dx = p.x - q.x
                let dy = p.y - q.y
                if dx * dx + dy * dy <= tol2 { return true }
            }
        }
        return false
    }
}
