import XCTest
@testable import ShopPilotCore

final class ToolDatabaseTests: XCTestCase {

    /// Helper: create a temporary file for tool persistence so tests don't pollute real data.
    private static var tempURL: URL?

    override class func setUp() {
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShopPilot_ToolsTest_\(UUID().uuidString).json")
    }

    override class func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
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
            material: "carbide",
            vBitAngleDegrees: 90.0,
            maxRPM: 15000,
            cornerRadius: 0.0,
            leadAngle: 0.0
        )

        XCTAssertEqual(tool.name, "3mm End Mill")
        XCTAssertEqual(tool.type, .endMill)
        XCTAssertEqual(tool.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(tool.flutes, 2)
        XCTAssertEqual(tool.material, "carbide")
        XCTAssertEqual(tool.maxRPM, 15000)
        XCTAssertFalse(tool.isSuitableForVCrave)
        XCTAssertTrue(tool.isEndMill)
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
            material: "carbide",
            vBitAngleDegrees: 60.0,
            maxRPM: 18000
        )

        XCTAssertEqual(tool.name, "60 deg V-Bit")
        XCTAssertEqual(tool.type, .vBit)
        XCTAssertEqual(tool.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(tool.vBitAngleDegrees, 60.0, accuracy: 1e-9)
        XCTAssertEqual(tool.flutes, 1)
        XCTAssertTrue(tool.isSuitableForVCrave)
        XCTAssertFalse(tool.isEndMill)
    }

    func testEndMillEffectiveCuttingWidthEqualsDiameter() {
        let tool = Tool(
            name: "Test",
            type: .endMill,
            diameter: 6.0,
            cuttingLength: 10.0,
            totalLength: 25.0,
            shankDiameter: 6.0
        )
        XCTAssertEqual(tool.effectiveCuttingWidth, 6.0, accuracy: 1e-9)
    }

    func testVBitEffectiveCuttingWidthEqualsDiameter() {
        let tool = Tool(
            name: "Test",
            type: .vBit,
            diameter: 3.0,
            cuttingLength: 8.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            vBitAngleDegrees: 90.0
        )
        XCTAssertEqual(tool.effectiveCuttingWidth, 3.0, accuracy: 1e-9)
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
        let originalUpdated = tool.updatedAt

        Thread.sleep(forTimeInterval: 0.05)

        var updated = tool
        updated.name = "Updated"
        db.update(updated)

        let found = db.lookup(id: tool.id)
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertGreaterThan(found!.updatedAt, originalUpdated)
    }

    func testLookupByType() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let endMill = Tool(name: "EM", type: .endMill, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0)
        let vBit = Tool(name: "VB", type: .vBit, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0, vBitAngleDegrees: 90.0)
        let ballNose = Tool(name: "BN", type: .ballNose, diameter: 3.0, cuttingLength: 4.0, totalLength: 20.0, shankDiameter: 6.0)

        db.add(endMill)
        db.add(vBit)
        db.add(ballNose)

        let foundEndMills = db.lookup(byType: .endMill)
        XCTAssertEqual(foundEndMills.count, 1)
        XCTAssertEqual(foundEndMills[0].name, "EM")

        let foundVBits = db.lookup(byType: .vBit)
        XCTAssertEqual(foundVBits.count, 1)
        XCTAssertEqual(foundVBits[0].name, "VB")

        let foundNone = db.lookup(byType: .drill)
        XCTAssertTrue(foundNone.isEmpty)
    }

    func testFirstOfOptionalType() {
        let db = ToolDatabase()
        db.tools.removeAll()

        let em1 = Tool(name: "EM1", type: .endMill, diameter: 3.0, cuttingLength: 8.0, totalLength: 20.0, shankDiameter: 6.0)
        let em2 = Tool(name: "EM2", type: .endMill, diameter: 6.0, cuttingLength: 10.0, totalLength: 25.0, shankDiameter: 8.0)

        db.add(em1)
        db.add(em2)

        let first = db.first(ofType: .endMill)
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
            material: "carbide",
            vBitAngleDegrees: 90.0,
            maxRPM: 15000
        )

        let tool2 = Tool(
            name: "60 deg V-Bit",
            type: .vBit,
            diameter: 3.0,
            cuttingLength: 8.0,
            totalLength: 25.0,
            shankDiameter: 6.0,
            flutes: 1,
            material: "carbide",
            vBitAngleDegrees: 60.0,
            maxRPM: 18000
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
        XCTAssertEqual(loaded1?.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(loaded1?.flutes, 2)
        XCTAssertEqual(loaded1?.material, "carbide")
        XCTAssertEqual(loaded1?.maxRPM, 15000)

        let loaded2 = db2.tools.first { $0.id == tool2.id }
        XCTAssertNotNil(loaded2, "Tool 2 should be found after reload")
        XCTAssertEqual(loaded2?.name, "60 deg V-Bit")
        XCTAssertEqual(loaded2?.type, .vBit)
        XCTAssertEqual(loaded2?.diameter, 3.0, accuracy: 1e-9)
        XCTAssertEqual(loaded2?.vBitAngleDegrees, 60.0, accuracy: 1e-9)
        XCTAssertEqual(loaded2?.flutes, 1)
        XCTAssertEqual(loaded2?.maxRPM, 18000)
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
            material: "cobalt",
            vBitAngleDegrees: 90.0,
            maxRPM: 12000,
            cornerRadius: 0.5,
            leadAngle: 15.0
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try! encoder.encode(tool)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"diameter\""))
        XCTAssertTrue(json.contains("\"type\""))
        XCTAssertTrue(json.contains("\"endMill\""))
        XCTAssertTrue(json.contains("\"name\":\"Test Tool\""))
        XCTAssertTrue(json.contains("\"flutes\":4"))
        XCTAssertTrue(json.contains("\"material\":\"cobalt\""))
        XCTAssertTrue(json.contains("\"maxRPM\":12000"))
    }

    // MARK: - Static calculations

    func testRecommendedFeedRateForEndMill() {
        let rate = ToolDatabase.recommendedFeedRate(diameter: 6.0, material: "hardwood")
        XCTAssertGreaterThan(rate, 0)
        XCTAssertEqual(rate, 10 * 6.0 * sqrt(6.0) * 3.0)
    }

    func testRecommendedFeedRateMaterialDefaults() {
        let hardwood = ToolDatabase.recommendedFeedRate(diameter: 3.0, material: "hardwood")
        let aluminum = ToolDatabase.recommendedFeedRate(diameter: 3.0, material: "aluminum")
        XCTAssertGreaterThan(hardwood, aluminum)
    }

    func testRecommendedFeedRateUnknownMaterialDefaultsToHardwood() {
        let unknown = ToolDatabase.recommendedFeedRate(diameter: 3.0, material: "unobtainium")
        let hardwood = ToolDatabase.recommendedFeedRate(diameter: 3.0, material: "hardwood")
        XCTAssertEqual(unknown, hardwood)
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
        let plunge = ToolDatabase.recommendedPlungeRate(for: tool, in: "hardwood")
        let cutRate = ToolDatabase.recommendedFeedRate(diameter: 6.0, material: "hardwood")
        XCTAssertEqual(plunge, cutRate * 0.4)
    }
}
