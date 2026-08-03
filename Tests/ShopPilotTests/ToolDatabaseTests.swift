import XCTest
@testable import ShopPilotCore

final class ToolDatabaseTests: XCTestCase {

    /// Helper: create a temporary file for tool persistence so tests don't pollute real data.
    private static var tempURL: URL?

    /// Helper: clear persisted tool state before each test so tests are
    /// hermetic (save/load go through UserDefaults, not the temp file).
    private static func resetPersistedState() {
        UserDefaults.standard.removeObject(forKey: ToolDatabase.userDefaultsKey)
    }

    override class func setUp() {
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShopPilot_ToolsTest_\(UUID().uuidString).json")
    }

    override func setUp() {
        super.setUp()
        Self.resetPersistedState()
    }

    override class func tearDown() {
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
    }

    // MARK: - Tool model tests

    func testEndMillHasCorrectFields() {
        let tool = Tool(
            name: "3mm End Mill",
            type: .endMill,
            diameter: 3.0,
            cuttingLength: 9.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            flutes: 2,
            material: "carbide"
        )

        XCTAssertEqual(tool.name, "3mm End Mill")
        XCTAssertEqual(tool.type, .endMill)
        XCTAssertEqual(tool.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(tool.flutes, 2)
        XCTAssertEqual(tool.material, "carbide")
    }

    func testVBitHasCorrectFields() {
        let tool = Tool(
            name: "60 deg V-Bit",
            type: .vBit,
            diameter: 3.0,
            cuttingLength: 8.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            flutes: 1,
            material: "carbide"
        )

        XCTAssertEqual(tool.name, "60 deg V-Bit")
        XCTAssertEqual(tool.type, .vBit)
        XCTAssertEqual(tool.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(tool.flutes, 1)
    }

    // MARK: - CRUD tests

    func testAddAndRemoveTool() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let tool = Tool(
            name: "Test Tool",
            type: .endMill,
            diameter: 4.0,
            cuttingLength: 10.0,
            totalLength: 25.0,
            shankDiameter: 6.0
        )

        db.add(tool)
        XCTAssertEqual(db.tools.count, 1)
        XCTAssertEqual(db.tools[0].name, "Test Tool")

        db.remove(id: tool.id)
        XCTAssertTrue(db.tools.isEmpty)
    }

    func testUpdateToolChangesUpdatedAt() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let tool = Tool(
            name: "Original",
            type: .endMill,
            diameter: 3.0,
            cuttingLength: 8.0,
            totalLength: 20.0,
            shankDiameter: 6.0
        )
        db.add(tool)
        let originalUpdated = db.tool(withID: tool.id)?.updatedAt

        Thread.sleep(forTimeInterval: 0.05)

        var updated = tool
        updated.name = "Updated"
        db.update(updated)

        let found = db.tool(withID: tool.id)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertGreaterThan(found!.updatedAt, originalUpdated!)
    }

    func testLookupByType() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let endMill = Tool(name: "EM", type: .endMill, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0)
        let vBit = Tool(name: "VB", type: .vBit, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0)
        let ballNose = Tool(name: "BN", type: .ballNose, diameter: 3.0, cuttingLength: 4.0, totalLength: 20.0, shankDiameter: 6.0)

        db.add(endMill)
        db.add(vBit)
        db.add(ballNose)

        let foundEndMills = db.tools(ofTypes: [.endMill])
        XCTAssertEqual(foundEndMills.count, 1)
        XCTAssertEqual(foundEndMills[0].name, "EM")

        let foundVBits = db.tools(ofTypes: [.vBit])
        XCTAssertEqual(foundVBits.count, 1)
        XCTAssertEqual(foundVBits[0].name, "VB")

        let foundNone = db.tools(ofTypes: [.drill])
        XCTAssertTrue(foundNone.isEmpty)
    }

    func testFirstOfOptionalType() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let em1 = Tool(name: "EM1", type: .endMill, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0)
        let em2 = Tool(name: "EM2", type: .endMill, diameter: 6.0, cuttingLength: 10.0, totalLength: 25.0, shankDiameter: 8.0)

        db.add(em1)
        db.add(em2)

        let first = db.tools(ofTypes: [.endMill]).first
        XCTAssertEqual(first?.name, "EM1")
    }

    // MARK: - File persistence tests (round-trip)

    func testRoundTripTwoTools() {
        // Create two distinct tools
        let tool1 = Tool(
            name: "3mm End Mill",
            type: .endMill,
            diameter: 3.0,
            cuttingLength: 9.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            flutes: 2,
            material: "carbide"
        )

        let tool2 = Tool(
            name: "60 deg V-Bit",
            type: .vBit,
            diameter: 3.0,
            cuttingLength: 8.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            flutes: 1,
            material: "carbide"
        )

        // Build database with both tools
        let db = ToolDatabase()
        db.tools.removeAll()
        db.add(tool1)
        db.add(tool2)
        XCTAssertEqual(db.tools.count, 2)

        // Save to file
        db.save()

        // Create a fresh database and load
        let db2 = ToolDatabase()
        db2.tools.removeAll()
        db2.load()

        // Verify both tools round-tripped
        XCTAssertEqual(db2.tools.count, 2)

        let loaded1 = db2.tools.first { $0.id == tool1.id }
        XCTAssertNotNil(loaded1, "Tool 1 should be found after reload")
        XCTAssertEqual(loaded1?.name, "3mm End Mill")
        XCTAssertEqual(loaded1?.type, .endMill)
        XCTAssertEqual(loaded1?.diameter ?? .nan, 3.0, accuracy: 1e-9)
        XCTAssertEqual(loaded1?.flutes, 2)
        XCTAssertEqual(loaded1?.material, "carbide")

        let loaded2 = db2.tools.first { $0.id == tool2.id }
        XCTAssertNotNil(loaded2, "Tool 2 should be found after reload")
        XCTAssertEqual(loaded2?.name, "60 deg V-Bit")
        XCTAssertEqual(loaded2?.type, .vBit)
        XCTAssertEqual(loaded2?.diameter ?? .nan, 3.0, accuracy: 1e-9)
        XCTAssertEqual(loaded2?.flutes, 1)
    }

    func testEmptyDatabaseLoadsClean() {
        let db = ToolDatabase()
        db.tools.removeAll()
        db.save()

        let db2 = ToolDatabase()
        db2.tools.removeAll()
        db2.load()
        XCTAssertTrue(db2.tools.isEmpty)
    }

    func testMissingFileLoadsEmpty() {
        let db = ToolDatabase()
        db.tools.removeAll()
        // Don't save — just load from a non-existent file
        let db2 = ToolDatabase()
        db2.tools.removeAll()
        db2.load()
        XCTAssertTrue(db2.tools.isEmpty)
    }

    // MARK: - JSON encoding test

    func testToolEncodesToJson() {
        let tool = Tool(
            name: "Test Tool",
            type: .endMill,
            diameter: 6.0,
            cuttingLength: 14.0,
            totalLength: 30.0,
            shankDiameter: 8.0,
            flutes: 4,
            material: "cobalt"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try! encoder.encode(tool)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"diameter\""))
        XCTAssertTrue(json.contains("\"type\""))
        XCTAssertTrue(json.contains("\"endMill\""))
        XCTAssertTrue(json.contains("\"flutes\""))
        XCTAssertTrue(json.contains("4"))
        XCTAssertTrue(json.contains("\"material\""))
        XCTAssertTrue(json.contains("cobalt"))
        XCTAssertTrue(json.contains("Test Tool"))
    }

    // MARK: - Calculations (instance methods)

    func testRecommendedFeedRateForEndMill() {
        let db = ToolDatabase()
        let rate = db.recommendedFeedRate(diameter: 6.0, material: "hardwood")
        XCTAssertGreaterThan(rate, 0)
        XCTAssertEqual(rate, 10 * 6.0 * sqrt(6.0) * 3.0, accuracy: 1e-9)
    }

    func testRecommendedFeedRateMaterialDefaults() {
        let db = ToolDatabase()
        let hardwood = db.recommendedFeedRate(diameter: 3.0, material: "hardwood")
        let aluminum = db.recommendedFeedRate(diameter: 3.0, material: "aluminum")
        XCTAssertGreaterThan(hardwood, aluminum)
    }

    func testRecommendedFeedRateUnknownMaterialDefaultsToHardwood() {
        let db = ToolDatabase()
        let unknown = db.recommendedFeedRate(diameter: 3.0, material: "unobtainium")
        let hardwood = db.recommendedFeedRate(diameter: 3.0, material: "hardwood")
        XCTAssertEqual(unknown, hardwood, accuracy: 1e-9)
    }

    func testRecommendedPlungeRate() {
        let db = ToolDatabase()
        let tool = Tool(
            name: "Test",
            type: .endMill,
            diameter: 6.0,
            cuttingLength: 14.0,
            totalLength: 30.0,
            shankDiameter: 8.0
        )
        let plunge = db.recommendedPlungeRate(for: tool, in: "hardwood")
        let cutRate = db.recommendedFeedRate(diameter: 6.0, material: "hardwood")
        XCTAssertEqual(plunge, cutRate * 0.4, accuracy: 1e-9)
    }
}
