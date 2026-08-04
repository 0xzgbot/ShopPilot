import Foundation

// MARK: - Heightfield Data

/// SPK-3D-spine-a — a 2.5D relief grid (heightfield) that persists in the
/// document. Row-major heights, world-origin at (minX, minY), each cell
/// `cellSizeMm` square; height values are mm above the stock bottom (Z).
public struct HeightfieldData: Codable, Sendable {
    public let width: Int      // cells along X
    public let height: Int     // cells along Y
    public let cellSizeMm: Double
    public let minX: Double
    public let minY: Double
    /// Row-major, count == width * height. Z in mm.
    public let heights: [Double]

    public init(width: Int, height: Int, cellSizeMm: Double, minX: Double, minY: Double, heights: [Double]) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.cellSizeMm = cellSizeMm
        self.minX = minX
        self.minY = minY
        self.heights = heights
    }

    /// Height at a world coordinate (nearest cell), or nil outside the grid.
    public func height(atX x: Double, y: Double) -> Double? {
        guard cellSizeMm > 1e-9 else { return nil }
        // Bounds-check in world space FIRST: Int() truncates toward zero, so
        // negative coordinates would otherwise wrap into cell (0, 0).
        guard x >= minX, y >= minY,
              x < minX + Double(width) * cellSizeMm,
              y < minY + Double(height) * cellSizeMm else { return nil }
        let gx = Int((x - minX) / cellSizeMm)
        let gy = Int((y - minY) / cellSizeMm)
        return heights[gy * width + gx]
    }

    public var maxHeight: Double {
        heights.max() ?? 0
    }

    /// World-space extent of the grid (minX, minY, maxX, maxY).
    public var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (minX, minY, minX + Double(width) * cellSizeMm, minY + Double(height) * cellSizeMm)
    }
}

// MARK: - STL Heightfield Importer

public struct STLHeightfieldResult: Sendable {
    public let heightfield: HeightfieldData?
    public let triangleCount: Int
    public let fileSizeBytes: Int64
    public let success: Bool
    public let errorMessage: String?
}

public enum STLHeightfieldError: Error, LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case notSTL
    case binaryNotSupported
    case noTriangles(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "STL file not found: \(p)"
        case .unreadable(let m): return "STL unreadable: \(m)"
        case .notSTL: return "Not a recognized ASCII STL file (no 'vertex' records found)"
        case .binaryNotSupported: return "Binary STL is not supported yet — export ASCII STL"
        case .noTriangles(let m): return "STL contains no valid triangles: \(m)"
        }
    }
}

/// SPK-3D-spine-a — real ASCII STL importer that rasterizes the mesh onto a
/// heightfield grid (top surface). Replaces the estimator-only path.
public enum STLHeightfieldImporter {

    /// A single triangle with 3D vertices.
    public struct Triangle: Sendable {
        public let a: (x: Double, y: Double, z: Double)
        public let b: (x: Double, y: Double, z: Double)
        public let c: (x: Double, y: Double, z: Double)

        public init(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ c: (Double, Double, Double)) {
            self.a = (a.0, a.1, a.2)
            self.b = (b.0, b.1, b.2)
            self.c = (c.0, c.1, c.2)
        }
    }

    // MARK: - Public entry

    public static func importSTL(
        at path: String,
        cellSizeMm: Double = 1.0,
        scale: Double = 1.0
    ) -> STLHeightfieldResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return STLHeightfieldResult(
                heightfield: nil, triangleCount: 0, fileSizeBytes: 0,
                success: false, errorMessage: STLHeightfieldError.fileNotFound(path).localizedDescription
            )
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let triangles = try parseASCII(text: text)
            guard !triangles.isEmpty else {
                return STLHeightfieldResult(
                    heightfield: nil, triangleCount: 0, fileSizeBytes: fileSize,
                    success: false,
                    errorMessage: STLHeightfieldError.noTriangles("0 triangles parsed").localizedDescription
                )
            }
            let grid = rasterize(triangles: triangles, cellSizeMm: cellSizeMm, scale: scale)
            return STLHeightfieldResult(
                heightfield: grid, triangleCount: triangles.count, fileSizeBytes: fileSize,
                success: true, errorMessage: nil
            )
        } catch let e as STLHeightfieldError {
            return STLHeightfieldResult(
                heightfield: nil, triangleCount: 0, fileSizeBytes: fileSize,
                success: false, errorMessage: e.localizedDescription
            )
        } catch {
            return STLHeightfieldResult(
                heightfield: nil, triangleCount: 0, fileSizeBytes: fileSize,
                success: false, errorMessage: STLHeightfieldError.unreadable(error.localizedDescription).localizedDescription
            )
        }
    }

    // MARK: - ASCII parsing

    /// Parse ASCII STL: reads every `vertex x y z` record and groups them in
    /// threes. Tolerant of CRLF, whitespace variants, and missing facet blocks.
    public static func parseASCII(text: String) throws -> [Triangle] {
        // Binary STL heuristic: starts with "solid" but the 80-byte header +
        // uint32 count is followed by binary records, not "facet"/"vertex" text.
        let looksBinary = text.hasPrefix("solid")
            && !text.contains("facet")
            && !text.contains("vertex")
        if looksBinary {
            throw STLHeightfieldError.binaryNotSupported
        }
        if !text.contains("vertex") {
            throw STLHeightfieldError.notSTL
        }

        var verts: [(Double, Double, Double)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count == 4, tokens[0] == "vertex",
                  let x = Double(tokens[1]), let y = Double(tokens[2]), let z = Double(tokens[3]) else {
                continue
            }
            verts.append((x, y, z))
        }
        guard verts.count >= 3 else {
            throw STLHeightfieldError.noTriangles("\(verts.count) vertices parsed")
        }
        var triangles: [Triangle] = []
        var i = 0
        while i + 2 < verts.count {
            let a = verts[i], b = verts[i + 1], c = verts[i + 2]
            // Skip degenerate triangles (zero area in XY projection is fine for
            // vertical walls, but zero-length edges are garbage).
            let ab = (b.0 - a.0, b.1 - a.1, b.2 - a.2)
            let ac = (c.0 - a.0, c.1 - a.1, c.2 - a.2)
            let nx = ab.1 * ac.2 - ab.2 * ac.1
            let ny = ab.2 * ac.0 - ab.0 * ac.2
            let nz = ab.0 * ac.1 - ab.1 * ac.0
            if abs(nx) + abs(ny) + abs(nz) > 1e-12 {
                triangles.append(Triangle(a, b, c))
            }
            i += 3
        }
        return triangles
    }

    // MARK: - Rasterization

    /// Rasterize the triangle soup onto a heightfield grid. Each cell takes the
    /// MAX Z of every triangle whose XY projection covers the cell center (the
    /// top surface). Z is scaled; XY coordinates are scaled too.
    public static func rasterize(
        triangles: [Triangle],
        cellSizeMm: Double,
        scale: Double
    ) -> HeightfieldData {
        guard !triangles.isEmpty, cellSizeMm > 1e-9 else {
            return HeightfieldData(width: 1, height: 1, cellSizeMm: cellSizeMm, minX: 0, minY: 0, heights: [0])
        }
        let s = scale > 0 ? scale : 1.0
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for t in triangles {
            for v in [t.a, t.b, t.c] {
                minX = min(minX, v.x * s); maxX = max(maxX, v.x * s)
                minY = min(minY, v.y * s); maxY = max(maxY, v.y * s)
            }
        }
        guard maxX > minX, maxY > minY else {
            return HeightfieldData(width: 1, height: 1, cellSizeMm: cellSizeMm, minX: minX, minY: minY, heights: [0])
        }
        let width = max(1, Int(ceil((maxX - minX) / cellSizeMm)))
        let height = max(1, Int(ceil((maxY - minY) / cellSizeMm)))

        // Clamp grid size: a pathological STL at 0.01mm cells could blow up.
        let maxCells = 600
        let cellX = width > maxCells ? (maxX - minX) / Double(maxCells) : cellSizeMm
        let cellY = height > maxCells ? (maxY - minY) / Double(maxCells) : cellSizeMm
        let gx = width > maxCells ? maxCells : width
        let gy = height > maxCells ? maxCells : height

        var heights = [Double](repeating: 0, count: gx * gy)
        for t in triangles {
            let a = (t.a.0 * s, t.a.1 * s, t.a.2 * s)
            let b = (t.b.0 * s, t.b.1 * s, t.b.2 * s)
            let c = (t.c.0 * s, t.c.1 * s, t.c.2 * s)
            let triMinX = min(a.0, min(b.0, c.0))
            let triMaxX = max(a.0, max(b.0, c.0))
            let triMinY = min(a.1, min(b.1, c.1))
            let triMaxY = max(a.1, max(b.1, c.1))

            // Plane coefficients: n·(p - a) = 0  →  z = (n.x*(a.x-x) + n.y*(a.y-y)) / n.z + a.z
            let ab = (b.0 - a.0, b.1 - a.1, b.2 - a.2)
            let ac = (c.0 - a.0, c.1 - a.1, c.2 - a.2)
            let nx = ab.1 * ac.2 - ab.2 * ac.1
            let ny = ab.2 * ac.0 - ab.0 * ac.2
            let nz = ab.0 * ac.1 - ab.1 * ac.0
            let nzAbs = abs(nz)

            let startX = max(0, Int((triMinX - minX) / cellX) - 1)
            let endX = min(gx - 1, Int((triMaxX - minX) / cellX) + 1)
            let startY = max(0, Int((triMinY - minY) / cellY) - 1)
            let endY = min(gy - 1, Int((triMaxY - minY) / cellY) + 1)

            for row in startY...endY {
                let cy = minY + (Double(row) + 0.5) * cellY
                for col in startX...endX {
                    let cx = minX + (Double(col) + 0.5) * cellX
                    guard pointInTriangle(px: cx, py: cy, a: a, b: b, c: c) else { continue }
                    var z: Double
                    if nzAbs > 1e-12 {
                        z = a.2 - (nx * (cx - a.0) + ny * (cy - a.1)) / nz
                    } else {
                        // Vertical wall: use the max vertex Z.
                        z = max(a.2, max(b.2, c.2))
                    }
                    if z > heights[row * gx + col] {
                        heights[row * gx + col] = z
                    }
                }
            }
        }
        return HeightfieldData(
            width: gx, height: gy,
            cellSizeMm: min(cellX, cellY),
            minX: minX, minY: minY,
            heights: heights
        )
    }

    /// Half-plane point-in-triangle test (CCW or CW agnostic — sign-consistent).
    static func pointInTriangle(
        px: Double, py: Double,
        a: (Double, Double, Double), b: (Double, Double, Double), c: (Double, Double, Double)
    ) -> Bool {
        func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
            ax * by - ay * bx
        }
        let d1 = cross(b.0 - a.0, b.1 - a.1, px - a.0, py - a.1)
        let d2 = cross(c.0 - b.0, c.1 - b.1, px - b.0, py - b.1)
        let d3 = cross(a.0 - c.0, a.1 - c.1, px - c.0, py - c.1)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }
}
