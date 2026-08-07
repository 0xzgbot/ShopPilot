import Foundation
import ShopPilotCore

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg) (got \(a), expected \(b))") }
}

func errMsg(_ s: String?) -> String { s ?? "nil" }

func tempURL(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-obj-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

func writeFixture(_ text: String, _ name: String) throws -> URL {
    let url = try tempURL(name)
    try Data(text.utf8).write(to: url)
    return url
}

func main() throws {
    // (1) 20x20x20 cube: 8 vertex records, 12 triangular face records.
    let cube = """
    # Cube 20x20x20 (X/Y centered on origin, sitting on Z=0)
    v -10 -10 0
    v 10 -10 0
    v 10 10 0
    v -10 10 0
    v -10 -10 20
    v 10 -10 20
    v 10 10 20
    v -10 10 20
    f 1 3 2
    f 1 4 3
    f 5 6 7
    f 5 7 8
    f 1 2 6
    f 1 6 5
    f 2 3 7
    f 2 7 6
    f 3 4 8
    f 3 8 7
    f 4 1 5
    f 4 5 8
    """
    let cubeURL = try writeFixture(cube, "cube.obj")
    let cubeRes = OBJHeightfieldImporter.importOBJ(at: cubeURL.path, cellSizeMm: 1.0)
    try expect(cubeRes.success, "cube import succeeds: \(errMsg(cubeRes.errorMessage))")
    try expect(cubeRes.vertexCount == 8, "cube vertex count 8 got \(cubeRes.vertexCount)")
    try expect(cubeRes.faceCount == 12, "cube face count 12 got \(cubeRes.faceCount)")
    try expect(cubeRes.triangleCount == 12, "cube triangle count 12 got \(cubeRes.triangleCount)")
    try expect(cubeRes.fileSizeBytes > 0, "cube file size reported")
    let cubeHF = try cubeRes.heightfield ?? { throw VerifyError.failed("cube heightfield nil") }()
    try expect(cubeHF.width == 20 && cubeHF.height == 20,
               "cube grid 20x20 got \(cubeHF.width)x\(cubeHF.height)")
    try expectClose(cubeHF.maxHeight, 20.0, "cube maxHeight 20")
    try expectClose(cubeHF.height(atX: 0, y: 0) ?? -1, 20.0, "cube top face at center")
    try expectClose(cubeHF.height(atX: 5.25, y: -3.5) ?? -1, 20.0, "cube top face off-center")
    try expectClose(cubeHF.minX, -10.0, "cube minX")
    try expectClose(cubeHF.minY, -10.0, "cube minY")
    try expectClose(cubeHF.cellSizeMm, 1.0, "cube cell size")
    try expectClose(cubeHF.bounds.maxX - cubeHF.bounds.minX, 20.0, "cube world width")
    try expectClose(cubeHF.bounds.maxY - cubeHF.bounds.minY, 20.0, "cube world depth")

    // Finer cells: 0.5mm → 40x40 footprint for the same 20mm cube.
    let fine = OBJHeightfieldImporter.importOBJ(at: cubeURL.path, cellSizeMm: 0.5)
    try expect(fine.success, "cube at 0.5mm succeeds")
    let fineHF = try fine.heightfield ?? { throw VerifyError.failed("fine heightfield nil") }()
    try expect(fineHF.width == 40 && fineHF.height == 40,
               "cube at 0.5mm -> 40x40 got \(fineHF.width)x\(fineHF.height)")

    // (2) A single 4-vertex face fans into 2 triangles; the raised vertex
    //     makes the center cell rise while corner cells stay low.
    let fan = """
    v 0 0 0
    v 10 0 0
    v 10 10 10
    v 0 10 0
    f 1 2 3 4
    """
    let fanURL = try writeFixture(fan, "fan.obj")
    let fanRes = OBJHeightfieldImporter.importOBJ(at: fanURL.path)
    try expect(fanRes.success, "fan import succeeds")
    try expect(fanRes.triangleCount == 2, "4-vertex face fans to 2 triangles got \(fanRes.triangleCount)")
    let fanHF = try fanRes.heightfield ?? { throw VerifyError.failed("fan heightfield nil") }()
    try expect(fanHF.width == 10 && fanHF.height == 10, "fan grid 10x10 got \(fanHF.width)x\(fanHF.height)")
    let centerH = fanHF.heights[5 * 10 + 5]
    let cornerH = fanHF.heights[0]
    try expect(centerH > 4.0, "fan center cell raised got \(centerH)")
    try expect(cornerH < 1.0, "fan corner cell low got \(cornerH)")

    // (3) CRLF line endings + comments + texture-only face format (no normals).
    let crlf = "# tiny slab\r\nv 0 0 0\r\nv 1 0 0\r\nv 1 1 0\r\nv 0 1 0\r\n\r\nf 1/1 2/1 3/1 4/1\r\n"
    let crlfURL = try writeFixture(crlf, "crlf.obj")
    let crlfRes = OBJHeightfieldImporter.importOBJ(at: crlfURL.path)
    try expect(crlfRes.success, "CRLF/comment import succeeds: \(errMsg(crlfRes.errorMessage))")
    try expect(crlfRes.vertexCount == 4 && crlfRes.faceCount == 1,
               "crlf counts 4v/1f got \(crlfRes.vertexCount)v/\(crlfRes.faceCount)f")
    try expect(crlfRes.triangleCount == 2, "crlf quad fans to 2 got \(crlfRes.triangleCount)")
    let crlfHF = try crlfRes.heightfield ?? { throw VerifyError.failed("crlf heightfield nil") }()
    try expect(crlfHF.width == 1 && crlfHF.height == 1, "crlf grid 1x1 got \(crlfHF.width)x\(crlfHF.height)")
    try expectClose(crlfHF.heights[0], 0.0, "crlf flat height 0")

    // i//k form (normals, no texture) + scale doubles the world footprint.
    let normals = """
    # normals present, no texture coords
    v 0 0 0
    v 1 0 0
    v 1 1 0
    f 1//1 2//1 3//1
    """
    let normalsURL = try writeFixture(normals, "normals.obj")
    let scaled = OBJHeightfieldImporter.importOBJ(at: normalsURL.path, cellSizeMm: 1.0, scale: 2.0)
    try expect(scaled.success, "scaled import succeeds: \(errMsg(scaled.errorMessage))")
    let scaledHF = try scaled.heightfield ?? { throw VerifyError.failed("scaled heightfield nil") }()
    try expect(scaledHF.width == 2 && scaledHF.height == 2,
               "scale 2 -> grid 2x2 got \(scaledHF.width)x\(scaledHF.height)")

    // (4) Empty / garbage / binary input fails cleanly, never crashes.
    let emptyURL = try writeFixture("", "empty.obj")
    let emptyRes = OBJHeightfieldImporter.importOBJ(at: emptyURL.path)
    try expect(!emptyRes.success && emptyRes.errorMessage != nil,
               "empty OBJ fails with message (no crash)")
    let garbageURL = try writeFixture("this is definitely not an obj file", "garbage.obj")
    let garbageRes = OBJHeightfieldImporter.importOBJ(at: garbageURL.path)
    try expect(!garbageRes.success && garbageRes.errorMessage != nil,
               "garbage OBJ fails with message (no crash)")

    let binaryURL = try tempURL("binary.obj")
    try Data([0x76, 0x20, 0x00, 0x01, 0x02, 0xFF]).write(to: binaryURL)
    let binaryRes = OBJHeightfieldImporter.importOBJ(at: binaryURL.path)
    try expect(!binaryRes.success && (binaryRes.errorMessage ?? "").contains("Binary"),
               "binary input rejected with Binary message got \(errMsg(binaryRes.errorMessage))")

    // (5) File not found.
    let missing = OBJHeightfieldImporter.importOBJ(at: "/nonexistent/definitely-missing.obj")
    try expect(!missing.success && (missing.errorMessage ?? "").contains("not found"),
               "missing file reports file-not-found got \(errMsg(missing.errorMessage))")

    print("ShopPilotVerifyOBJImport: PASS - cube 20x20x20 footprint/maxHeight, vertex/face/triangle counts, quad fan rasterization, CRLF+comments+scale, graceful failures")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyOBJImport: FAIL - \(error)")
    exit(1)
}
