import Foundation

// MARK: - Shaded relief mesh (SPK-2000d — cross-platform parity)
//
// VectorPilot renders a true shaded 3D heightfield mesh (WPF Viewport3D).
// ShopPilot's Model stage is a 2.5D heightmap image; this engine supplies
// the missing piece as pure data: a triangulated mesh over the heightfield
// grid with per-vertex normals and lambert shading against a directional
// light, plus an amber-on-graphite material ramp matching the brand.
//
// The renderer (SwiftUI Canvas / future Metal view) consumes `vertices`,
// `triangleIndices`, and `shades`; the math here is fully CLT-provable.

public struct ReliefMesh: Codable, Sendable {
    public struct Vertex: Codable, Sendable {
        public let x: Double   // world mm
        public let y: Double
        public let z: Double
        public let nx: Double  // unit normal
        public let ny: Double
        public let nz: Double
    }

    public let vertices: [Vertex]
    /// Triangle list — every 3 consecutive indices form one triangle.
    public let triangleIndices: [Int]
    /// Per-triangle lambert shade 0…1 (same length as triangleIndices / 3).
    public let shades: [Double]
    public let success: Bool
    public let errorMessage: String?
}

public enum ReliefMeshEngine {

    /// Directional light in world space (normalized inside).
    /// Defaults match the amber/graphite look: light from upper-left-front.
    public static func build(
        _ hf: HeightfieldData,
        lightX: Double = -0.4,
        lightY: Double = -0.5,
        lightZ: Double = 0.77,
        zScale: Double = 1.0,
        maxGridDimension: Int = 128
    ) -> ReliefMesh {
        guard hf.width >= 2, hf.height >= 2 else {
            return ReliefMesh(vertices: [], triangleIndices: [], shades: [],
                              success: false, errorMessage: "Heightfield too small to mesh")
        }
        // Downsample so a huge relief can't explode the index count.
        let stepX = max(1, Int((Double(hf.width) / Double(maxGridDimension)).rounded(.up)))
        let stepY = max(1, Int((Double(hf.height) / Double(maxGridDimension)).rounded(.up)))
        let gw = (hf.width + stepX - 1) / stepX
        let gh = (hf.height + stepY - 1) / stepY

        // Sample heights into the reduced grid.
        var heights = [Double](repeating: 0, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                let sx = min(gx * stepX, hf.width - 1)
                let sy = min(gy * stepY, hf.height - 1)
                heights[gy * gw + gx] = hf.heights[sy * hf.width + sx] * zScale
            }
        }

        // Vertices with central-difference normals.
        let cell = hf.cellSizeMm
        var vertices: [ReliefMesh.Vertex] = []
        vertices.reserveCapacity(gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                let hL = heights[gy * gw + max(0, gx - 1)]
                let hR = heights[gy * gw + min(gw - 1, gx + 1)]
                let hD = heights[max(0, gy - 1) * gw + gx]
                let hU = heights[min(gh - 1, gy + 1) * gw + gx]
                // Central differences → surface normal.
                var nx = (hL - hR) / (2 * cell)
                var ny = (hD - hU) / (2 * cell)
                var nz = 1.0
                let len = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= len; ny /= len; nz /= len
                vertices.append(ReliefMesh.Vertex(
                    x: Double(gx) * cell * Double(stepX),
                    y: Double(gy) * cell * Double(stepY),
                    z: heights[gy * gw + gx],
                    nx: nx, ny: ny, nz: nz
                ))
            }
        }

        // Normalize the light once.
        let ll = (lightX * lightX + lightY * lightY + lightZ * lightZ).squareRoot()
        let lx = lightX / ll, ly = lightY / ll, lz = lightZ / ll

        // Two triangles per quad, CCW when viewed from above.
        var indices: [Int] = []
        var shades: [Double] = []
        indices.reserveCapacity((gw - 1) * (gh - 1) * 6)
        shades.reserveCapacity((gw - 1) * (gh - 1) * 2)
        for gy in 0..<(gh - 1) {
            for gx in 0..<(gw - 1) {
                let v0 = gy * gw + gx
                let v1 = v0 + 1
                let v2 = v0 + gw
                let v3 = v2 + 1
                indices.append(contentsOf: [v0, v2, v1, v1, v2, v3])
                // Shade each triangle from its average normal.
                for tri in [[v0, v2, v1], [v1, v2, v3]] {
                    let nSum = tri.reduce((0.0, 0.0, 0.0)) { acc, i in
                        (acc.0 + vertices[i].nx, acc.1 + vertices[i].ny, acc.2 + vertices[i].nz)
                    }
                    let dot = abs(nSum.0 * lx + nSum.1 * ly + nSum.2 * lz)
                    shades.append(min(1.0, max(0.15, 0.25 + 0.75 * dot)))
                }
            }
        }

        return ReliefMesh(vertices: vertices, triangleIndices: indices,
                          shades: shades, success: true, errorMessage: nil)
    }
}
