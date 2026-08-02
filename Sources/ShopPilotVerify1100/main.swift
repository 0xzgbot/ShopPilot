import Foundation
import ShopPilotCore

/// SPK-1100 verify without XCTest (CLT-only machines).
/// Round-trips vectors + toolpaths + document variables through `.shoppilot` package.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1100-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    var job = Job(name: "Round Trip Job")
    var sheet = Sheet(name: "Sheet A", width: 500, depth: 300, height: 20)
    var layer = Layer(name: "Vectors")
    let path = VectorPath(
        name: "Rect",
        points: [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 100, y: 50),
            VectorPoint(x: 0, y: 50),
        ],
        isClosed: true
    )
    layer.addVector(path)
    sheet.addLayer(layer)
    job.addSheet(sheet)
    job.documentVariables = [
        DocumentVariable(key: "material", value: "Plywood", category: "Stock"),
        DocumentVariable(key: "width", value: "500", category: "Stock"),
    ]

    let toolpaths = [
        PersistedToolpath(
            name: "Profile 1",
            toolpathResult: "G0 X0 Y0\nG1 X10 F800",
            estimatedTimeSeconds: 42,
            isDirty: false
        ),
    ]

    let payload = ShopPilotPackagePayload(job: job, toolpaths: toolpaths)
    let packageURL = temp.appendingPathComponent("test.shoppilot")

    try DocumentSaver().save(payload, to: packageURL)
    let loaded = try DocumentLoader().loadPayload(from: packageURL)

    try expect(loaded.job.name == "Round Trip Job", "job name")
    try expect(loaded.job.documentVariables.count == 2, "doc vars count")
    try expect(loaded.job.documentVariables.first?.key == "material", "doc var key")

    let vectors = loaded.job.sheets.flatMap(\.layers).flatMap(\.vectors)
    try expect(vectors.count == 1, "vector count")
    try expect(vectors.first?.points.count == 4, "vector points")

    try expect(loaded.toolpaths.count == 1, "toolpath count")
    try expect(loaded.toolpaths.first?.name == "Profile 1", "toolpath name")
    try expect(loaded.toolpaths.first?.estimatedTimeSeconds == 42, "toolpath time")
    try expect(
        loaded.toolpaths.first?.toolpathResult == "G0 X0 Y0\nG1 X10 F800",
        "toolpath gcode"
    )

    // Legacy package without toolpaths.json still loads.
    let legacyURL = temp.appendingPathComponent("legacy.shoppilot")
    var legacyJob = Job(name: "Legacy")
    _ = legacyJob.ensureSingleSheet()
    try DocumentSaver().save(ShopPilotPackagePayload(job: legacyJob), to: legacyURL)
    try FileManager.default.removeItem(at: legacyURL.appendingPathComponent("toolpaths.json"))
    let legacy = try DocumentLoader().loadPayload(from: legacyURL)
    try expect(legacy.job.name == "Legacy", "legacy name")
    try expect(legacy.toolpaths.isEmpty, "legacy empty toolpaths")

    // Tree restore helper
    let tree = ShopPilotPackagePayload.restoreToolpathTree(from: toolpaths)
    try expect(tree.root.children.count == 1, "restored tree ops")
    try expect(tree.root.children.first?.toolpathResult?.contains("G1") == true, "restored gcode")

    print("SPK-1100 verification: PASS")
    print("  vectors+toolpaths+documentVariables round-trip OK")
    print("  legacy package without toolpaths.json OK")
    print("  ToolpathTree restore OK")
}

do {
    try main()
} catch {
    fputs("SPK-1100 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
