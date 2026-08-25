import Foundation

// MARK: - Discrete medial axis (skeleton), SPK-2010a
//
// Independent Swift implementation of the discrete clearance-field skeleton
// semantics shared with our Windows sibling: rasterise the interior of a
// closed outline, record each interior cell's clearance (distance to the
// nearest boundary edge), keep the ridge cells (local maxima of clearance
// along X, Y, or either diagonal), and chain them 8-connected into
// polylines, longest first. Depth for V-carving then comes from the
// clearance at each ridge point, which is the local half-width of the
// valley. No continuous Voronoi — grid-based by design (lean scope).

public enum MedialAxis {

    /// One point on the skeleton.
    public struct RidgePoint: Sendable {
        /// Position in mm (sheet coordinates).
        public let position: VectorPoint
        /// Distance to the nearest boundary — the local half-width.
        public let clearanceMm: Double

        public init(position: VectorPoint, clearanceMm: Double) {
            self.position = position
            self.clearanceMm = clearanceMm
        }
    }

    public struct Result: Sendable {
        /// Ridge polylines, longest first.
        public let paths: [[RidgePoint]]
        /// Largest clearance seen anywhere inside the outline.
        public let maxClearanceMm: Double

        public var isEmpty: Bool { paths.isEmpty }
    }

    /// Hard cap on grid size; coarsen the cell rather than explode memory.
    private static let maxCells = 4_000_000

    /// Compute the skeleton of a closed outline. Outlines with fewer than
    /// three points have no interior and yield an empty result.
    public static func compute(outline: [VectorPoint], cellMm: Double = 1.0) -> Result {
        guard outline.count >= 3 else { return Result(paths: [], maxClearanceMm: 0) }

        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for p in outline {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        var cell = max(0.05, cellMm)
        var nx = Int(ceil((maxX - minX) / cell)) + 1
        var ny = Int(ceil((maxY - minY) / cell)) + 1

        if Double(nx) * Double(ny) > Double(maxCells) {
            let scale = sqrt(Double(nx) * Double(ny) / Double(maxCells))
            cell *= scale
            nx = Int(ceil((maxX - minX) / cell)) + 1
            ny = Int(ceil((maxY - minY) / cell)) + 1
        }

        // Clearance field: distance to the nearest boundary edge, 0 outside.
        var clearance = [Double](repeating: 0, count: nx * ny)
        var maxClear = 0.0

        for ix in 0..<nx {
            let x = minX + Double(ix) * cell
            for iy in 0..<ny {
                let y = minY + Double(iy) * cell
                let p = VectorPoint(x: x, y: y)
                guard pointInPolygon(p, outline) else { continue }
                let d = distanceToBoundary(p, outline)
                clearance[ix * ny + iy] = d
                if d > maxClear { maxClear = d }
            }
        }

        guard maxClear > 0 else { return Result(paths: [], maxClearanceMm: 0) }

        // Ridge cells: clearance is a local maximum along at least one axis
        // (X, Y, or either diagonal) and at least one full cell in from the
        // wall. Requiring BOTH axes would drop the spine of a long channel.
        let floorValue = cell
        var ridge: [(x: Int, y: Int, c: Double)] = []

        func c(_ ix: Int, _ iy: Int) -> Double { clearance[ix * ny + iy] }

        for ix in 1..<(nx - 1) {
            for iy in 1..<(ny - 1) {
                let v = c(ix, iy)
                if v <= floorValue { continue }
                let ridgeX = v >= c(ix - 1, iy) && v >= c(ix + 1, iy)
                let ridgeY = v >= c(ix, iy - 1) && v >= c(ix, iy + 1)
                let ridgeD1 = v >= c(ix - 1, iy - 1) && v >= c(ix + 1, iy + 1)
                let ridgeD2 = v >= c(ix - 1, iy + 1) && v >= c(ix + 1, iy - 1)
                if ridgeX || ridgeY || ridgeD1 || ridgeD2 {
                    ridge.append((ix, iy, v))
                }
            }
        }

        guard !ridge.isEmpty else {
            return Result(paths: [], maxClearanceMm: maxClear)
        }

        let paths = chainRidge(ridge, minX: minX, minY: minY, cell: cell)
            .sorted { $0.count > $1.count }

        return Result(paths: paths, maxClearanceMm: maxClear)
    }

    /// Greedy nearest-neighbour chaining of ridge cells into polylines,
    /// seeded from the widest cells first (the deepest part of the carve).
    private static func chainRidge(
        _ ridge: [(x: Int, y: Int, c: Double)],
        minX: Double, minY: Double, cell: Double
    ) -> [[RidgePoint]] {
        var remaining = Set(ridge.map { Vector2($0.x, $0.y) })
        var lookup: [Vector2: Double] = [:]
        for r in ridge { lookup[Vector2(r.x, r.y)] = r.c }

        var paths: [[RidgePoint]] = []
        // Seed order: deepest clearance first.
        let orderedSeeds = ridge.sorted { $0.c > $1.c }

        for seed in orderedSeeds {
            let seedKey = Vector2(seed.x, seed.y)
            guard remaining.contains(seedKey) else { continue }

            var path: [RidgePoint] = []
            var current = seedKey

            while true {
                remaining.remove(current)
                path.append(RidgePoint(
                    position: VectorPoint(x: minX + Double(current.x) * cell,
                                          y: minY + Double(current.y) * cell),
                    clearanceMm: lookup[current] ?? 0
                ))

                // Walk to an 8-connected neighbour still on the ridge.
                var next: Vector2?
                for dx in -1...1 where next == nil {
                    for dy in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let cand = Vector2(current.x + dx, current.y + dy)
                        if remaining.contains(cand) { next = cand; break }
                    }
                }

                guard let n = next else { break }
                current = n
            }

            // A single cell is noise, not a path.
            if path.count >= 2 { paths.append(path) }
        }

        return paths
    }

    private struct Vector2: Hashable {
        let x: Int
        let y: Int
        init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    }

    /// Shortest distance from a point to any edge of the polygon.
    public static func distanceToBoundary(_ p: VectorPoint, _ poly: [VectorPoint]) -> Double {
        var best = Double.infinity
        guard !poly.isEmpty else { return 0 }
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            best = min(best, distanceToSegment(p, a, b))
        }
        return best.isFinite ? best : 0
    }

    static func distanceToSegment(_ p: VectorPoint, _ a: VectorPoint, _ b: VectorPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        let cx = a.x + t * dx, cy = a.y + t * dy
        return hypot(p.x - cx, p.y - cy)
    }

    /// Even-odd containment test.
    public static func pointInPolygon(_ p: VectorPoint, _ poly: [VectorPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if (pi.y > p.y) != (pj.y > p.y),
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
