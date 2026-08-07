import Foundation
import ShopPilotCore

/// SPK-3D-spine verify (CLT machine, no XCTest): 3MF → heightfield relief
/// import. Proves:
///   1. A 20×20×20 cube 3MF (8 vertices, 12 triangles) rasterizes to a
///      heightfield with ≈20/cellSize footprint and maxHeight ≈ 20.
///   2. Triangle/vertex counts parse correctly.
///   3. A single-triangle model still rasterizes (some cell raised).
///   4. Non-zip payload → success=false with a clear error (no crash).
///   5. Zip without 3dmodel.model → success=false.
///   6. Missing file → success=false (file-not-found).
///   7. Malformed model XML → success=false (no crash).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, tolerance: Double = 1e-6) throws {
    try expect(abs(a - b) <= tolerance, "expected \(a) ≈ \(b) (±\(tolerance))")
}

// MARK: - 3MF fixture builders

/// Minimal-but-valid 3MF model XML: a box from (0,0,0) to (w,d,h).
/// 8 vertices, 12 triangles, spec namespace.
func box3MFXML(w: Double, d: Double, h: Double) -> String {
    let v: [(Double, Double, Double)] = [
        (0, 0, 0), (w, 0, 0), (w, d, 0), (0, d, 0),
        (0, 0, h), (w, 0, h), (w, d, h), (0, d, h),
    ]
    let faces: [[Int]] = [
        [0, 2, 1], [0, 3, 2], // bottom
        [4, 5, 6], [4, 6, 7], // top
        [0, 1, 5], [0, 5, 4], // front
        [1, 2, 6], [1, 6, 5], // right
        [2, 3, 7], [2, 7, 6], // back
        [3, 0, 4], [3, 4, 7], // left
    ]
    var verts = ""
    for p in v {
        verts += "      <vertex x=\"\(p.0)\" y=\"\(p.1)\" z=\"\(p.2)\"/>\n"
    }
    var tris = ""
    for f in faces {
        tris += "      <triangle v1=\"\(f[0])\" v2=\"\(f[1])\" v3=\"\(f[2])\"/>\n"
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
      <resources>
        <object id="1">
          <mesh>
            <vertices>
    \(verts)      </vertices>
            <triangles>
    \(tris)      </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid="1"/>
      </build>
    </model>
    """
}

/// 3MF model XML with a single flat triangle: z=5 over part of the XY plane.
func singleTriangleXML() -> String {
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
      <resources>
        <object id="1">
          <mesh>
            <vertices>
              <vertex x="0" y="0" z="5"/>
              <vertex x="10" y="0" z="5"/>
              <vertex x="0" y="10" z="5"/>
            </vertices>
            <triangles>
              <triangle v1="0" v2="1" v3="2"/>
            </triangles>
          </mesh>
        </object>
      </resources>
      <build>
        <item objectid="1"/>
      </build>
    </model>
    """
}

// MARK: - ZIP building via Process + /usr/bin/zip

/// Write `entries` (archive-path → content) into a fresh temp dir and zip them
/// with /usr/bin/zip. Returns the .3mf path. Temp dir is left for OS cleanup.
func makeZip(entries: [String: String]) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-3mf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (entry, content) in entries {
        let url = dir.appendingPathComponent(entry)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url)
    }
    let outURL = dir.appendingPathComponent("model.3mf")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    proc.currentDirectoryURL = dir
    proc.arguments = ["-q", outURL.lastPathComponent] + Array(entries.keys)
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        throw VerifyError.failed("zip creation failed (exit \(proc.terminationStatus))")
    }
    return outURL.path
}

/// Plain (non-zip) bytes at a .3mf path, for the not-a-zip negative test.
func writePlainFile(_ content: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-3mf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("notazip.3mf")
    try Data(content.utf8).write(to: url)
    return url.path
}

func main() throws {
    // ── 1. Cube 20×20×20 → footprint ≈ 20/cellSize, top at 20mm. ─────────
    let cubePath = try makeZip(entries: ["3D/3dmodel.model": box3MFXML(w: 20, d: 20, h: 20)])
    let cube = ThreeMFImporter.import3MF(at: cubePath, cellSizeMm: 2.0, scale: 1.0)
    try expect(cube.success, "cube import succeeds")
    guard let hf = cube.heightfield else { throw VerifyError.failed("cube heightfield produced") }
    try expect(cube.triangleCount == 12, "cube has 12 triangles (got \(cube.triangleCount))")
    try expect(cube.vertexCount == 8, "cube has 8 vertices (got \(cube.vertexCount))")
    try expect(hf.width == 10 && hf.height == 10,
               "20mm cube at 2mm cells → 10×10 grid (got \(hf.width)×\(hf.height))")
    let center = try hf.height(atX: 10, y: 10) ?? { throw VerifyError.failed("center cell missing") }()
    try expectClose(center, 20, tolerance: 0.001)
    let nearEdge = try hf.height(atX: 19, y: 19) ?? { throw VerifyError.failed("edge cell missing") }()
    try expectClose(nearEdge, 20, tolerance: 0.001)
    try expect(hf.height(atX: -1, y: -1) == nil, "cell outside the grid returns nil")
    try expectClose(hf.maxHeight, 20, tolerance: 0.001)

    // 1mm cells → 20×20 footprint (the ≈20/cellSize rule).
    let fine = ThreeMFImporter.import3MF(at: cubePath, cellSizeMm: 1.0, scale: 1.0)
    try expect(fine.success, "cube import at 1mm cells succeeds")
    let fhf = try fine.heightfield ?? { throw VerifyError.failed("fine heightfield produced") }()
    try expect(fhf.width == 20 && fhf.height == 20,
               "20mm cube at 1mm cells → 20×20 grid (got \(fhf.width)×\(fhf.height))")
    try expectClose(fhf.maxHeight, 20, tolerance: 0.001)

    // ── 2. Triangle/vertex counts are surfaced on the result. ─────────────
    try expect(cube.triangleCount == 12 && cube.vertexCount == 8,
               "counts parsed: 12 triangles / 8 vertices (got \(cube.triangleCount)/\(cube.vertexCount))")
    try expect(cube.fileSizeBytes > 0, "file size reported (\(cube.fileSizeBytes) bytes)")

    // ── 3. Single-triangle model rasterizes (some cell raised). ───────────
    let singlePath = try makeZip(entries: ["3D/3dmodel.model": singleTriangleXML()])
    let single = ThreeMFImporter.import3MF(at: singlePath, cellSizeMm: 1.0, scale: 1.0)
    try expect(single.success, "single-triangle import succeeds")
    let shf = try single.heightfield ?? { throw VerifyError.failed("single-triangle heightfield produced") }()
    try expect(single.triangleCount == 1 && single.vertexCount == 3,
               "single-triangle counts (got \(single.triangleCount)/\(single.vertexCount))")
    try expect(shf.heights.contains { $0 > 4.9 }, "single-triangle raises some cell to ~5mm")
    try expectClose(shf.maxHeight, 5, tolerance: 0.01)

    // ── 4. Non-zip payload → graceful failure. ─────────────────────────────
    let junkPath = try writePlainFile("this is definitely not a zip archive\n")
    let junk = ThreeMFImporter.import3MF(at: junkPath, cellSizeMm: 1.0, scale: 1.0)
    try expect(!junk.success && junk.errorMessage != nil,
               "non-zip payload fails with an error (no crash)")

    // ── 5. Zip without 3dmodel.model → graceful failure. ───────────────────
    let noModelPath = try makeZip(entries: ["readme.txt": "hello from a non-3MF zip"])
    let noModel = ThreeMFImporter.import3MF(at: noModelPath, cellSizeMm: 1.0, scale: 1.0)
    try expect(!noModel.success && (noModel.errorMessage ?? "").contains("3dmodel.model"),
               "zip without 3dmodel.model reports missing-model (got \(noModel.errorMessage ?? "nil"))")

    // ── 6. Missing file → file-not-found error. ────────────────────────────
    let missing = ThreeMFImporter.import3MF(at: "/nonexistent/definitely-missing.3mf", cellSizeMm: 1.0, scale: 1.0)
    try expect(!missing.success && (missing.errorMessage ?? "").contains("not found"),
               "missing file reports file-not-found (got \(missing.errorMessage ?? "nil"))")

    // ── 7. Malformed model XML → graceful failure, no crash. ───────────────
    let badXMLPath = try makeZip(entries: ["3D/3dmodel.model": "<model><mesh><vertices>"])
    let badXML = ThreeMFImporter.import3MF(at: badXMLPath, cellSizeMm: 1.0, scale: 1.0)
    try expect(!badXML.success && badXML.errorMessage != nil,
               "malformed XML fails with an error (no crash)")

    print("ShopPilotVerify3MFImport: PASS — cube 20×20×20 footprint+top, counts, single-triangle, graceful failures (non-zip, missing model, missing file, malformed XML)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify3MFImport: FAIL — \(error)")
    exit(1)
}
