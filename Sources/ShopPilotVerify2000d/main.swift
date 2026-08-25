import Foundation
import ShopPilotCore

/// SPK-2000d verify — shaded relief mesh generation.
///
/// Covers: vertex/index counts for a known grid, unit normals, lambert shade
/// bounds and light-direction response, downsampling of a large grid, honest
/// failure on degenerate input.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 5×4 grid at 1mm cells with a simple ramp: z = x + y.
var heights: [Double] = []
for gy in 0..<4 {
    for gx in 0..<5 {
        heights.append(Double(gx + gy))
    }
}
let hf = HeightfieldData(width: 5, height: 4, cellSizeMm: 1.0,
                         minX: 0, minY: 0, heights: heights)

func verify() throws {
    let mesh = ReliefMeshEngine.build(hf)
    try expect(mesh.success, "mesh builds")

    // Counts: (5−1)×(4−1) quads × 2 triangles × 3 indices = 72; 20 vertices.
    try expect(mesh.vertices.count == 20, "vertex count (got \(mesh.vertices.count))")
    try expect(mesh.triangleIndices.count == 24 * 3, "index count (got \(mesh.triangleIndices.count))")
    try expect(mesh.shades.count == 24, "shade-per-triangle count")

    // Indices reference valid vertices.
    for i in mesh.triangleIndices {
        try expect(i >= 0 && i < mesh.vertices.count, "index in range")
    }

    // Normals are unit length (flat region → (0,0,±1) interior).
    let center = mesh.vertices[1 * 5 + 2] // interior vertex on the ramp
    let nLen = (center.nx * center.nx + center.ny * center.ny + center.nz * center.nz).squareRoot()
    try expect(abs(nLen - 1.0) < 1e-9, "normal is unit length (\(nLen))")
    // Ramp z = x+y has slope −1 in each direction → normal tilted equally.
    try expect(center.nz < 1.0 && center.nz > 0.3, "interior normal tilted by slope")

    // Flat heightfield → normals all straight up → shades uniform.
    var flat = heights
    for i in flat.indices { flat[i] = 5 }
    let flatHf = HeightfieldData(width: 5, height: 4, cellSizeMm: 1.0,
                                 minX: 0, minY: 0, heights: flat)
    let flatMesh = ReliefMeshEngine.build(flatHf)
    try expect(Set(flatMesh.shades.map { ($0 * 10000).rounded() / 10000 }).count == 1,
               "flat surface shades uniformly")
    // Light from upper-left-front vs default: dot ≈ lz/|l| → shade = 0.25+0.75·dot.

    // Shade responds to light direction: flipping light X flips the gradient.
    let litLeft = ReliefMeshEngine.build(hf, lightX: -0.6)
    let litRight = ReliefMeshEngine.build(hf, lightX: 0.6)
    try expect(litLeft.shades.first != nil && litRight.shades.first != nil
               && litLeft.shades != litRight.shades,
               "light direction changes shading")

    // Shades stay within [0.15, 1].
    for s in mesh.shades {
        try expect(s >= 0.15 && s <= 1.0, "shade in range")
    }

    // Downsampling a big grid caps the vertex count.
    var bigHeights = [Double](repeating: 1, count: 500 * 500)
    for i in bigHeights.indices { bigHeights[i] = Double(i % 97) }
    let bigHf = HeightfieldData(width: 500, height: 500, cellSizeMm: 0.5,
                                minX: 0, minY: 0, heights: bigHeights)
    let bigMesh = ReliefMeshEngine.build(bigHf, maxGridDimension: 64)
    try expect(bigMesh.vertices.count <= 65 * 65, "downsampled grid capped (\(bigMesh.vertices.count))")
    try expect(bigMesh.success, "big grid meshes")

    // Degenerate input fails honestly.
    let tiny = HeightfieldData(width: 1, height: 1, cellSizeMm: 1,
                               minX: 0, minY: 0, heights: [0])
    let tinyMesh = ReliefMeshEngine.build(tiny)
    try expect(!tinyMesh.success && tinyMesh.errorMessage != nil, "degenerate grid fails honestly")
}

do {
    try verify()
    print("ShopPilotVerify2000d: PASS — mesh counts/normals/shading/light-response/downsample/degenerate verified")
} catch {
    print("ShopPilotVerify2000d: FAIL — \(error)")
    exit(1)
}
