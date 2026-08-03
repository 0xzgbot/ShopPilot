import XCTest
@testable import ShopPilotCore

final class ToolpathTemplateManagerTests: XCTestCase {
    
    var tempDir: URL!
    var manager: ToolpathTemplateManager!
    
    override func setUp() {
        super.setUp()
        // Create a temporary directory for each test to avoid cross-test pollution
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ShopPilotTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("toolpath_templates.json")
        manager = ToolpathTemplateManager(fileURL: fileURL)
    }
    
    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Save Template
    
    func testSaveTemplate() {
        let paramsJson = """
        {
            "cutMode": "onCut",
            "feedRateMmPerMin": 1000,
            "plungeFeedRateMmPerMin": 300,
            "maxDepthOfCutMm": 2.0,
            "toolDiameterMm": 6.0,
            "tabWidths": [],
            "finishPasses": 1,
            "leadInDistanceMm": 5.0,
            "leadOutDistanceMm": 5.0
        }
        """
        
        let template = manager.saveTemplate(
            name: "Oak Profile",
            type: .profile,
            paramsJson: paramsJson
        )
        
        XCTAssertEqual(manager.templates.count, 1)
        XCTAssertEqual(template.name, "Oak Profile")
        XCTAssertEqual(template.toolpathType, .profile)
        XCTAssertEqual(template.paramsJson, paramsJson)
        XCTAssertNotNil(template.id)
        XCTAssertNotNil(template.createdAt)
    }
    
    func testSaveMultipleTemplates() {
        let profileJson = """
        {"cutMode": "onCut", "feedRateMmPerMin": 1000, "plungeFeedRateMmPerMin": 300, "maxDepthOfCutMm": 2.0, "toolDiameterMm": 6.0, "tabWidths": [], "finishPasses": 1, "leadInDistanceMm": 5.0, "leadOutDistanceMm": 5.0}
        """
        let vcarveJson = """
        {"vBitAngleDegrees": 90.0, "feedRateMmPerMin": 1000, "plungeFeedRateMmPerMin": 300, "maxDepthOfCutMm": 2.0, "leadInDistanceMm": 5.0, "leadOutDistanceMm": 5.0, "stepOverMm": 1.0, "flatBottomMode": false, "vectorDepths": {}}
        """
        
        manager.saveTemplate(name: "Oak Profile", type: .profile, paramsJson: profileJson)
        manager.saveTemplate(name: "Oak V-Carve", type: .vcarve, paramsJson: vcarveJson)
        
        XCTAssertEqual(manager.templates.count, 2)
        XCTAssertEqual(manager.templates[0].name, "Oak Profile")
        XCTAssertEqual(manager.templates[1].name, "Oak V-Carve")
    }
    
    // MARK: - Save/Load Cycle
    
    func testSaveLoadCycle() {
        let paramsJson = """
        {"vBitAngleDegrees": 45.0, "feedRateMmPerMin": 800, "plungeFeedRateMmPerMin": 250, "maxDepthOfCutMm": 1.5, "leadInDistanceMm": 3.0, "leadOutDistanceMm": 3.0, "stepOverMm": 0.5, "flatBottomMode": false, "vectorDepths": {}}
        """
        
        let template = manager.saveTemplate(
            name: "Fine V-Carve",
            type: .vcarve,
            paramsJson: paramsJson
        )
        
        // Create a new manager pointing to the same file (simulates app restart)
        let newManager = ToolpathTemplateManager(fileURL: manager.fileURL)
        
        XCTAssertEqual(newManager.templates.count, 1)
        let loaded = newManager.templates[0]
        XCTAssertEqual(loaded.id, template.id)
        XCTAssertEqual(loaded.name, "Fine V-Carve")
        XCTAssertEqual(loaded.toolpathType, .vcarve)
        XCTAssertEqual(loaded.paramsJson, paramsJson)
        // ISO8601 persistence truncates sub-second precision — compare within
        // one second rather than exact equality.
        XCTAssertEqual(loaded.createdAt.timeIntervalSince(template.createdAt), 0, accuracy: 1.0)
    }
    
    func testLoadEmptyWhenNoFile() {
        let freshManager = ToolpathTemplateManager(fileURL: tempDir.appendingPathComponent("nonexistent.json"))
        XCTAssertTrue(freshManager.templates.isEmpty)
    }
    
    func testLoadPreservesOrder() {
        manager.saveTemplate(name: "First", type: .profile, paramsJson: "{}")
        manager.saveTemplate(name: "Second", type: .pocket, paramsJson: "{}")
        manager.saveTemplate(name: "Third", type: .drill, paramsJson: "{}")
        
        let newManager = ToolpathTemplateManager(fileURL: manager.fileURL)
        
        XCTAssertEqual(newManager.templates[0].name, "First")
        XCTAssertEqual(newManager.templates[1].name, "Second")
        XCTAssertEqual(newManager.templates[2].name, "Third")
    }
    
    // MARK: - Delete Template
    
    func testDeleteTemplate() {
        let t1 = manager.saveTemplate(name: "Keep", type: .profile, paramsJson: "{}")
        let t2 = manager.saveTemplate(name: "Delete", type: .pocket, paramsJson: "{}")
        
        XCTAssertEqual(manager.templates.count, 2)
        
        manager.deleteTemplate(id: t2.id)
        XCTAssertEqual(manager.templates.count, 1)
        XCTAssertEqual(manager.templates[0].name, "Keep")
    }
    
    func testDeleteNonExistentTemplate() {
        let t1 = manager.saveTemplate(name: "Only", type: .profile, paramsJson: "{}")
        
        let fakeId = UUID()
        XCTAssertFalse(t1.id == fakeId)
        
        // Should not crash or remove anything
        manager.deleteTemplate(id: fakeId)
        XCTAssertEqual(manager.templates.count, 1)
    }
    
    // MARK: - Apply Template
    
    func testApplyTemplate() {
        let paramsJson = """
        {"cutMode": "outCut", "feedRateMmPerMin": 1200, "plungeFeedRateMmPerMin": 400, "maxDepthOfCutMm": 3.0, "toolDiameterMm": 10.0, "tabWidths": [10.0, 15.0], "finishPasses": 2, "leadInDistanceMm": 8.0, "leadOutDistanceMm": 8.0}
        """
        
        let template = manager.saveTemplate(name: "Aluminum Profile", type: .profile, paramsJson: paramsJson)
        
        let applied = manager.applyTemplate(id: template.id)
        XCTAssertEqual(applied, paramsJson)
    }
    
    func testApplyNonExistentTemplate() {
        let fakeId = UUID()
        XCTAssertNil(manager.applyTemplate(id: fakeId))
    }
    
    func testApplyTemplateAfterReload() {
        let paramsJson = """
        {"vBitAngleDegrees": 30.0, "feedRateMmPerMin": 600, "plungeFeedRateMmPerMin": 200, "maxDepthOfCutMm": 0.5, "leadInDistanceMm": 2.0, "leadOutDistanceMm": 2.0, "stepOverMm": 0.25, "flatBottomMode": true, "vectorDepths": {}}
        """
        
        let template = manager.saveTemplate(name: "Delicate Engrave", type: .quickengrave, paramsJson: paramsJson)
        
        // Reload and apply
        let newManager = ToolpathTemplateManager(fileURL: manager.fileURL)
        let applied = newManager.applyTemplate(id: template.id)
        XCTAssertEqual(applied, paramsJson)
    }
    
    // MARK: - Filter by Type
    
    func testTemplatesFilteredByType() {
        manager.saveTemplate(name: "Profile 1", type: .profile, paramsJson: "{}")
        manager.saveTemplate(name: "Pocket 1", type: .pocket, paramsJson: "{}")
        manager.saveTemplate(name: "Profile 2", type: .profile, paramsJson: "{}")
        manager.saveTemplate(name: "Drill 1", type: .drill, paramsJson: "{}")
        
        let profiles = manager.templates(for: .profile)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.allSatisfy { $0.toolpathType == .profile })
        
        let pockets = manager.templates(for: .pocket)
        XCTAssertEqual(pockets.count, 1)
        XCTAssertEqual(pockets[0].name, "Pocket 1")
        
        let drills = manager.templates(for: .drill)
        XCTAssertEqual(drills.count, 1)
        
        let vcarves = manager.templates(for: .vcarve)
        XCTAssertTrue(vcarves.isEmpty)
    }
    
    // MARK: - Template Exists
    
    func testTemplateExistsByName() {
        manager.saveTemplate(name: "Oak Profile", type: .profile, paramsJson: "{}")
        
        XCTAssertTrue(manager.templateExists(withName: "Oak Profile"))
        XCTAssertTrue(manager.templateExists(withName: "oak profile")) // case-insensitive
        XCTAssertFalse(manager.templateExists(withName: "Nonexistent"))
    }
    
    // MARK: - Template Types
    
    func testAllTemplateTypes() {
        for type in ToolpathTemplateType.allCases {
            let template = manager.saveTemplate(name: "Test \(type.displayName)", type: type, paramsJson: "{}")
            XCTAssertEqual(template.toolpathType, type)
        }
        XCTAssertEqual(manager.templates.count, ToolpathTemplateType.allCases.count)
    }
    
    // MARK: - Equatable
    
    func testTemplateEquatable() {
        let t1 = ToolpathTemplate(name: "Same", toolpathType: .profile, paramsJson: "{}")
        let t2 = ToolpathTemplate(name: "Different", toolpathType: .vcarve, paramsJson: "{}")
        
        // Same ID means equal (even if other fields differ)
        let t3 = ToolpathTemplate(id: t1.id, name: "Different", toolpathType: .vcarve, paramsJson: "{}")
        XCTAssertEqual(t1, t3)
        XCTAssertNotEqual(t1, t2)
    }
    
    // MARK: - Codable
    
    func testTemplateCodable() {
        let paramsJson = """
        {"cutMode": "inCut", "feedRateMmPerMin": 900, "plungeFeedRateMmPerMin": 280, "maxDepthOfCutMm": 1.8, "toolDiameterMm": 8.0, "tabWidths": [12.0], "finishPasses": 3, "leadInDistanceMm": 6.0, "leadOutDistanceMm": 6.0}
        """
        
        let template = ToolpathTemplate(
            name: "Coded Template",
            toolpathType: .pocket,
            paramsJson: paramsJson
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        let data = try! encoder.encode(template)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(ToolpathTemplate.self, from: data)
        
        XCTAssertEqual(decoded.name, "Coded Template")
        XCTAssertEqual(decoded.toolpathType, .pocket)
        XCTAssertEqual(decoded.paramsJson, paramsJson)
        XCTAssertEqual(decoded.id, template.id)
    }
    
    // MARK: - Bulk Operations
    
    func testDeleteAllTemplates() {
        manager.saveTemplate(name: "A", type: .profile, paramsJson: "{}")
        manager.saveTemplate(name: "B", type: .profile, paramsJson: "{}")
        manager.saveTemplate(name: "C", type: .profile, paramsJson: "{}")
        
        XCTAssertEqual(manager.templates.count, 3)
        
        // Delete each one
        manager.templates.forEach { manager.deleteTemplate(id: $0.id) }
        
        // Verify via reload
        let newManager = ToolpathTemplateManager(fileURL: manager.fileURL)
        XCTAssertTrue(newManager.templates.isEmpty)
    }
}
