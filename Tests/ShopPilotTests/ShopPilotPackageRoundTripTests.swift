import XCTest
@testable import ShopPilotCore

/// SPK-1100 — Core package payload save/load round-trip (vectors, toolpaths, doc vars).
final class ShopPilotPackageRoundTripTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spk1100-core-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPayloadRoundTripsVectorsToolpathsAndDocumentVariables() throws {
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
        let packageURL = tempDir.appendingPathComponent("test.shoppilot")

        let saver = DocumentSaver()
        try saver.save(payload, to: packageURL)

        let loader = DocumentLoader()
        let loaded = try loader.loadPayload(from: packageURL)

        XCTAssertEqual(loaded.job.name, "Round Trip Job")
        XCTAssertEqual(loaded.job.documentVariables.count, 2)
        XCTAssertEqual(loaded.job.documentVariables.first?.key, "material")

        let loadedVectors = loaded.job.sheets.flatMap(\.layers).flatMap(\.vectors)
        XCTAssertEqual(loadedVectors.count, 1)
        XCTAssertEqual(loadedVectors.first?.points.count, 4)

        XCTAssertEqual(loaded.toolpaths.count, 1)
        XCTAssertEqual(loaded.toolpaths.first?.name, "Profile 1")
        XCTAssertEqual(loaded.toolpaths.first?.estimatedTimeSeconds, 42)
        XCTAssertEqual(loaded.toolpaths.first?.toolpathResult, "G0 X0 Y0\nG1 X10 F800")
    }

    func testLoadLegacyPackageWithoutToolpathsFile() throws {
        var job = Job(name: "Legacy")
        _ = job.ensureSingleSheet()
        let packageURL = tempDir.appendingPathComponent("legacy.shoppilot")

        let saver = DocumentSaver()
        try saver.save(ShopPilotPackagePayload(job: job), to: packageURL)

        let toolpathsURL = packageURL.appendingPathComponent("toolpaths.json")
        try FileManager.default.removeItem(at: toolpathsURL)

        let loaded = try DocumentLoader().loadPayload(from: packageURL)
        XCTAssertEqual(loaded.job.name, "Legacy")
        XCTAssertTrue(loaded.toolpaths.isEmpty)
    }

    func testPersistedToolpathCodable() throws {
        let original = PersistedToolpath(
            id: UUID(),
            name: "Pocket",
            toolpathResult: "G1",
            estimatedTimeSeconds: 10,
            isDirty: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedToolpath.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
