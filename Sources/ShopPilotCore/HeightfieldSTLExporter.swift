import Foundation

// MARK: - STL export (E38 lean slice)

/// Exports a `HeightfieldData` relief as an ASCII STL mesh (top surface +
/// z=0 bottom + side walls). The top surface is bilinearly smoothed at grid
/// points (each vertex height = mean of adjacent cell heights), so the mesh
/// matches the surface the 3D finish toolpath follows.
public enum HeightfieldSTLExporter {

    public struct MeshVertex {
        public let x: Double
        public let y: Double
        public let z: Double
        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// Build the triangle mesh for a heightfield. Bottom plane at z = 0.
    public static func mesh(from hf: HeightfieldData) -> (vertices: [MeshVertex], triangles: [(Int, Int, Int)]) {
        let w = hf.width
        let h = hf.height
        // Grid-point heights: mean of adjacent cell heights (bilinear-ish).
        var gz = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for gy in 0...h {
            for gx in 0...w {
                var acc = 0.0
                var n = 0
                for cy in [gy - 1, gy] where cy >= 0 && cy < h {
                    for cx in [gx - 1, gx] where cx >= 0 && cx < w {
                        acc += hf.heights[cy * w + cx]
                        n += 1
                    }
                }
                gz[gy * (w + 1) + gx] = n > 0 ? acc / Double(n) : 0
            }
        }
        func vx(_ gx: Int, _ gy: Int, _ z: Double) -> MeshVertex {
            MeshVertex(
                x: hf.minX + Double(gx) * hf.cellSizeMm,
                y: hf.minY + Double(gy) * hf.cellSizeMm,
                z: z
            )
        }
        var vertices: [MeshVertex] = []
        var triangles: [(Int, Int, Int)] = []
        func add(_ a: MeshVertex, _ b: MeshVertex, _ c: MeshVertex) {
            let ia = vertices.count
            vertices.append(a)
            let ib = vertices.count
            vertices.append(b)
            let ic = vertices.count
            vertices.append(c)
            triangles.append((ia, ib, ic))
        }
        // Top surface (upward winding).
        for gy in 0..<h {
            for gx in 0..<w {
                let v00 = vx(gx, gy, gz[gy * (w + 1) + gx])
                let v10 = vx(gx + 1, gy, gz[gy * (w + 1) + gx + 1])
                let v11 = vx(gx + 1, gy + 1, gz[(gy + 1) * (w + 1) + gx + 1])
                let v01 = vx(gx, gy + 1, gz[(gy + 1) * (w + 1) + gx])
                add(v00, v10, v11)
                add(v00, v11, v01)
            }
        }
        // Side walls: for each boundary grid edge, quad from top vertex down
        // to z = 0 (two triangles, outward winding).
        let minX = hf.minX
        let minY = hf.minY
        let maxX = hf.minX + Double(w) * hf.cellSizeMm
        let maxY = hf.minY + Double(h) * hf.cellSizeMm
        func wall(_ a: MeshVertex, _ b: MeshVertex) {
            let a0 = MeshVertex(x: a.x, y: a.y, z: 0)
            let b0 = MeshVertex(x: b.x, y: b.y, z: 0)
            add(a, b, b0)
            add(a, b0, a0)
        }
        for gx in 0..<w {
            wall(vx(gx, 0, gz[gx]), vx(gx + 1, 0, gz[gx + 1]))                        // front
            wall(vx(gx + 1, h, gz[h * (w + 1) + gx + 1]), vx(gx, h, gz[h * (w + 1) + gx]))  // back
        }
        for gy in 0..<h {
            wall(vx(w, gy, gz[gy * (w + 1) + w]), vx(w, gy + 1, gz[(gy + 1) * (w + 1) + w]))  // right
            wall(vx(0, gy + 1, gz[(gy + 1) * (w + 1)]), vx(0, gy, gz[gy * (w + 1)]))        // left
        }
        // Bottom plane at z = 0 (single quad, downward winding).
        let b00 = MeshVertex(x: minX, y: minY, z: 0)
        let b10 = MeshVertex(x: maxX, y: minY, z: 0)
        let b11 = MeshVertex(x: maxX, y: maxY, z: 0)
        let b01 = MeshVertex(x: minX, y: maxY, z: 0)
        add(b00, b11, b10)
        add(b00, b01, b11)
        return (vertices, triangles)
    }

    /// ASCII STL text for a heightfield (mm units, triangulated top + sides +
    /// bottom). Returns nil for degenerate grids.
    public static func stlString(from hf: HeightfieldData) -> String? {
        guard hf.width >= 1, hf.height >= 1, hf.heights.count == hf.width * hf.height else { return nil }
        let (vertices, triangles) = mesh(from: hf)
        guard !triangles.isEmpty else { return nil }
        var out = "solid shoppilot_relief\n"
        for (ia, ib, ic) in triangles {
            let a = vertices[ia], b = vertices[ib], c = vertices[ic]
            // Face normal via cross product (b−a)×(c−a).
            let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z
            let vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z
            let nx = uy * vz - uz * vy
            let ny = uz * vx - ux * vz
            let nz = ux * vy - uy * vx
            let len = (nx * nx + ny * ny + nz * nz).squareRoot()
            let (px, py, pz) = len > 1e-12 ? (nx / len, ny / len, nz / len) : (0.0, 0.0, 1.0)
            out += "  facet normal \(String(format: "%.6f", px)) \(String(format: "%.6f", py)) \(String(format: "%.6f", pz))\n"
            out += "    outer loop\n"
            for v in [a, b, c] {
                out += "      vertex \(String(format: "%.4f", v.x)) \(String(format: "%.4f", v.y)) \(String(format: "%.4f", v.z))\n"
            }
            out += "    endloop\n"
            out += "  endfacet\n"
        }
        out += "endsolid shoppilot_relief\n"
        return out
    }
}
