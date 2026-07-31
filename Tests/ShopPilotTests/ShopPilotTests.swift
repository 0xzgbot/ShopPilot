import XCTest
@testable import ShopPilotGeometry
@testable import ShopPilotCore

final class ShopPilotGeometryTests: XCTestCase {
    
    // MARK: - VectorShape Tests
    
    func testLineAreaIsZero() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 100, y: 0))
        XCTAssertEqual(line.area, 0.0, accuracy: 1e-9)
    }
    
    func testCircleArea() {
        let circle = VectorShape.circle(center: VectorPoint(x: 50, y: 50), radius: 25.0)
        XCTAssertEqual(circle.area, Double.pi * 25.0 * 25.0, accuracy: 1e-6)
    }
    
    func testRectangleArea() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 50)
        XCTAssertEqual(rect.area, 5000.0, accuracy: 1e-9)
    }
    
    // MARK: - Translation
    
    func testLineTranslation() {
        let line = VectorShape.line(start: VectorPoint(x: 10, y: 10), end: VectorPoint(x: 50, y: 10))
        let translated = line.translated(by: 5, 3)
        
        if case .line(let start, let end) = translated {
            XCTAssertEqual(start.x, 15.0, accuracy: 1e-9)
            XCTAssertEqual(start.y, 13.0, accuracy: 1e-9)
            XCTAssertEqual(end.x, 55.0, accuracy: 1e-9)
            XCTAssertEqual(end.y, 13.0, accuracy: 1e-9)
        } else {
            XCTFail("Translation failed")
        }
    }
    
    // MARK: - Node Extraction / Reconstruction
    
    func testLineNodeExtraction() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 100, y: 100))
        let nodes = line.extractNodes()
        
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].point, VectorPoint(x: 0, y: 0))
        XCTAssertEqual(nodes[1].point, VectorPoint(x: 100, y: 100))
    }
    
    func testCircleNodeExtraction() {
        let circle = VectorShape.circle(center: VectorPoint(x: 50, y: 50), radius: 25.0)
        let nodes = circle.extractNodes()
        
        XCTAssertGreaterThanOrEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].point, VectorPoint(x: 50, y: 50))
    }
    
    // MARK: - Transform Tests
    
    func testLineRotation90() {
        let line = VectorShape.line(start: VectorPoint(x: 1, y: 0), end: VectorPoint(x: 2, y: 0))
        let center = VectorPoint(x: 0, y: 0)
        let rotated = line.rotated(around: center, by: .pi / 2)
        
        if case .line(let start, let end) = rotated {
            XCTAssertEqual(start.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(start.y, 1.0, accuracy: 1e-6)
            XCTAssertEqual(end.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(end.y, 2.0, accuracy: 1e-6)
        } else {
            XCTFail("Rotation failed")
        }
    }
    
    func testLineScaling() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let scaled = line.scaled(by: 2, about: VectorPoint(x: 0, y: 0))
        
        if case .line(_, let end) = scaled {
            XCTAssertEqual(end.x, 20.0, accuracy: 1e-9)
        } else {
            XCTFail("Scaling failed")
        }
    }
    
    // MARK: - Offset Tests
    
    func testLineOffsetPositive() {
        // Horizontal line y=0 from x=0..10; offset +5 should yield parallel line at y=5
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = VectorOffsetCalculator.offsetLine(line, by: 5.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertEqual(result?.offsetPath.count, 2)
        XCTAssertEqual(result?.offsetPath[0].y, 5.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[1].y, 5.0, accuracy: 1e-6)
    }
    
    func testCircleOffsetExpandsRadius() {
        let center = VectorPoint(x: 0, y: 0)
        let circle = VectorShape.circle(center: center, radius: 10.0)
        let result = VectorOffsetCalculator.offsetCircle(circle: circle, by: 5.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertFalse(result?.offsetPath.isEmpty ?? true)
        // All sample points should be at distance 15 from center
        if let pts = result?.offsetPath {
            for pt in pts {
                let d = hypot(pt.x - center.x, pt.y - center.y)
                XCTAssertEqual(d, 15.0, accuracy: 1e-5)
            }
        }
    }
    
    func testRectangleOffsetCorners() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let result = VectorOffsetCalculator.offsetRectangle(rect: rect, by: 2.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 2.0)
        XCTAssertEqual(result?.offsetPath.count, 5) // 4 corners + closing back to first
        // Expected expanded corner: (-2, -2)
        XCTAssertEqual(result?.offsetPath[0].x, -2.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[0].y, -2.0, accuracy: 1e-6)
    }
    
    func testArcOffsetPreservesSweepCount() {
        let arc = VectorShape.arc(center: VectorPoint(x: 0, y: 0), radius: 10.0, startAngle: 0, endAngle: .pi)
        let result = VectorOffsetCalculator.offsetArc(arc: arc, by: 1.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 1.0)
        XCTAssertFalse(result?.offsetPath.isEmpty ?? true)
    }
    
    // MARK: - Fillet / Extend Tests
    
    func testRectangleFilletReplacesWithLines() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 100)
        let result = FilletExtendEngine.fillet(shape: rect, cornerPoint: VectorPoint(x: 0, y: 0), radius: 10.0)
        
        XCTAssertFalse(result.isEmpty)
        XCTAssertGreaterThan(result.count, 1) // Filleted rectangle becomes multiple line segments
    }
    
    func testExtendLineToPoint() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = FilletExtendEngine.extendLine(line, to: VectorPoint(x: 20, y: 0))
        
        XCTAssertEqual(result.count, 1)
        if case .line(_, let e) = result[0] {
            XCTAssertEqual(e.x, 20.0, accuracy: 1e-9)
        } else {
            XCTFail("Extend failed")
        }
    }
    
    // MARK: - Array Copy Tests
    
    func testGridArrayProducesCorrectCount() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = line.gridArray(columns: 2, rows: 2, spacingX: 20, spacingY: 20)
        
        XCTAssertEqual(result.copies.count, 4)
        XCTAssertEqual(result.layout, .grid)
    }
    
    func testCircularArrayProducesCorrectCount() {
        let circle = VectorShape.circle(center: VectorPoint(x: 0, y: 0), radius: 5)
        let result = circle.circularArray(count: 4, radius: 20)
        
        XCTAssertEqual(result.copies.count, 4)
        XCTAssertEqual(result.layout, .circular)
    }
    
    // MARK: - Boolean Sanity (API existence + basic equality)
    
    func testBooleanUnionNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.union([a, b])
        XCTAssertFalse(result.isEmpty, "Union of two rectangles should not be empty")
    }
    
    func testBooleanIntersectionNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.intersection([a, b])
        XCTAssertFalse(result.isEmpty, "Intersection of overlapping rectangles should not be empty")
    }
    
    func testBooleanDifferenceNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.difference([a], [b])
        XCTAssertFalse(result.isEmpty, "Difference of overlapping rectangles should not be empty")
    }
    
    // MARK: - ExportBlocker Tests (SPK-0603)
    
    func testExportAllowedWhenNoDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let exporter = ExportBlocker(treeManager: treeManager)
        
        let result = exporter.validateForExport()
        XCTAssertTrue(result.isValid, "Export should be valid when no dirty nodes exist")
        XCTAssertTrue(result.canExport, "canExport should be true when clean")
        XCTAssertFalse(result.requiresOverride, "Should not require override when clean")
        XCTAssertTrue(dirtyNodes.isEmpty, "No dirty nodes expected")
        XCTAssertFalse(exporter.isExportBlocked, "Export should not be blocked when clean")
    }
    
    func testExportBlockedWhenDirtyNodeExists() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        let result = exporter.validateForExport()
        
        XCTAssertFalse(result.isValid, "Export should be invalid when dirty nodes exist")
        XCTAssertFalse(result.canExport, "canExport should be false when dirty")
        XCTAssertTrue(result.requiresOverride, "Should require override when dirty")
        XCTAssertEqual(dirtyNodes.count, 1, "Should report exactly one dirty node")
        XCTAssertTrue(exporter.isExportBlocked, "Export should be blocked when dirty nodes exist")
    }
    
    func testExportBlocksMultipleDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node1 = treeManager.addOperation("Profile 1")
        let node2 = treeManager.addOperation("Pocket 1")
        node1.markDirty()
        node2.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        let result = exporter.validateForExport()
        
        XCTAssertFalse(result.isValid, "Export should be invalid with multiple dirty nodes")
        XCTAssertEqual(dirtyNodes.count, 2, "Should report both dirty nodes")
    }
    
    func testOverrideAllowsExportDespiteDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        _ = exporter.validateForExport()
        XCTAssertTrue(exporter.isExportBlocked, "Should be blocked before override")
        
        let overridden = exporter.overrideExportBlock()
        XCTAssertTrue(overridden, "Override should succeed")
        XCTAssertFalse(exporter.isExportBlocked, "Should not be blocked after override")
    }
    
    func testClearDirtyFlagsResolvesBlock() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        _ = exporter.validateForExport()
        XCTAssertTrue(exporter.isExportBlocked, "Should be blocked before clearing")
        
        exporter.clearDirtyFlags()
        XCTAssertFalse(exporter.isExportBlocked, "Should not be blocked after clearing dirty flags")
    }
    
    func testOverrideOnCleanTreeSucceeds() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let exporter = ExportBlocker(treeManager: treeManager)
        
        let overridden = exporter.overrideExportBlock()
        XCTAssertTrue(overridden, "Override should succeed even on clean tree")
    }
    
    // MARK: - ToolpathTree Dirty State Tests
    
    func testMarkDirtyPropagatesToParent() {
        let treeManager = ToolpathTreeManager(rootName: "Root")
        let node = treeManager.addOperation("Child 1")
        
        XCTAssertFalse(treeManager.root.isDirty, "Root should not be dirty initially")
        node.markDirty()
        XCTAssertTrue(treeManager.root.isDirty, "Parent root should become dirty when child is marked dirty")
    }
    
    func testAllDirtyNodesReturnsOnlyDirty() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let cleanNode = treeManager.addOperation("Clean Node")
        let dirtyNode = treeManager.addOperation("Dirty Node")
        
        dirtyNode.markDirty()
        
        let dirtyNodes = treeManager.root.allDirtyNodes
        XCTAssertEqual(dirtyNodes.count, 1, "Should return exactly one dirty node")
        XCTAssertTrue(dirtyNodes[0].name == "Dirty Node", "Should be the marked dirty node")
    }
    
    func testClearDirtyResolvesNode() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        XCTAssertTrue(node.isDirty, "Node should be dirty after markDirty")
        node.clearDirty()
        XCTAssertFalse(node.isDirty, "Node should not be dirty after clearDirty")
    }
    
    func testRecalculateDirtyNodesResolvesAll() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node1 = treeManager.addOperation("Profile 1")
        let node2 = treeManager.addOperation("Pocket 1")
        node1.markDirty()
        node2.markDirty()
        
        XCTAssertEqual(treeManager.dirtyNodeCount, 2, "Should have two dirty nodes before recalculation")
        
        let recalculated = treeManager.recalculateDirtyNodes()
        XCTAssertEqual(recalculated.count, 2, "Should return both recalculated nodes")
        XCTAssertFalse(node1.isDirty, "First node should not be dirty after recalculation")
        XCTAssertFalse(node2.isDirty, "Second node should not be dirty after recalculation")
    }
    
    // MARK: - Golden Fixture Tests (SPK-0317)
    
    func testGoldenFixtureProfileMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let profileGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 Z5.0
        G0 X-5.0 Y0.0
        G1 Z-2.0 F300
        G1 X5.0 Y0.0 F1000
        G1 X5.0 Y10.0 F1000
        G1 X-5.0 Y10.0 F1000
        G1 X-5.0 Y0.0 F1000
        G0 Z5.0
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.profile, against: profileGcode)
        XCTAssertTrue(result.passed, "Profile fixture should match expected output")
    }
    
    func testGoldenFixturePocketMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let pocketGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 Z5.0
        G0 X0.0 Y0.0
        G1 Z-2.0 F300
        G1 X10.0 Y0.0 F1000
        G1 X10.0 Y10.0 F1000
        G1 X0.0 Y10.0 F1000
        G1 X0.0 Y0.0 F1000
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.pocket, against: pocketGcode)
        XCTAssertTrue(result.passed, "Pocket fixture should match expected output")
    }
    
    func testGoldenFixtureDrillMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let drillGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 X5.0 Y5.0
        G0 Z5.0
        G1 Z-3.0 F300
        G4 P1.0
        G0 Z5.0
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.drill, against: drillGcode)
        XCTAssertTrue(result.passed, "Drill fixture should match expected output")
    }
    
    func testGoldenFixtureMismatchDetected() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let wrongGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        
        G0 Z5.0
        G0 X0 Y0
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.profile, against: wrongGcode)
        XCTAssertFalse(result.passed, "Mismatched fixture should not pass")
        XCTAssertFalse(result.matches, "Matches should be false for different output")
    }
    
    func testGoldenFixtureNotRegisteredReturnsEmpty() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        
        // Register a custom fixture
        manager.register("G21\nG90\nM2", for: .profile)
        
        let result = manager.verifyFixture(.profile, against: "G21\nG90\nM2")
        XCTAssertTrue(result.passed, "Custom registered fixture should match")
    }
    
    // MARK: - GCode Streamer Tests (SPK-0404)
    
    func testStreamerInitialState() {
        let streamer = GCodeStreamer()
        XCTAssertEqual(streamer.state, .idle, "Should start in idle state")
        XCTAssertEqual(streamer.currentLine, 0, "Current line should be 0 initially")
        XCTAssertEqual(streamer.totalLines, 0, "Total lines should be 0 initially")
    }
    
    func testStreamerProgressTracking() {
        let streamer = GCodeStreamer()
        let lines = ["G21", "G90", "M8", "G0 Z5", "G1 X10 F500"]
        
        // Simulate progress by setting properties directly (since we can't easily test async streaming)
        streamer.totalLines = lines.count
        
        XCTAssertEqual(streamer.progress, 0.0, "Progress should be 0 before starting")
    }
    
    func testGcodeNormalizationRemovesComments() {
        let gcode = """
        G21 ; Set units
        (This is a comment)
        G90
        ; Another comment
        M8
        """
        
        let normalized = normalizeGcode(gcode)
        XCTAssertFalse(normalized.contains(";"), "Normalized should not contain comments")
        XCTAssertFalse(normalized.contains("("), "Normalized should not contain parenthesized comments")
        XCTAssertTrue(normalized.contains("G21"), "Should retain G-code commands")
    }
    
    func testFindDifferencesDetectsLineChanges() {
        let expected = "G21\nG90\nM8"
        let actual = "G21\nG91\nM8" // Different line
        
        let diffs = findGcodeDifferences(expected, actual)
        XCTAssertFalse(diffs.isEmpty, "Should detect differences")
    }
    
    func testFindDifferencesEmptyWhenIdentical() {
        let gcode = "G21\nG90\nM8"
        let diffs = findGcodeDifferences(gcode, gcode)
        XCTAssertTrue(diffs.isEmpty, "No differences when identical")
    }
}
    
    // MARK: - ExportBlocker Tests (SPK-0603)
    
    func testExportAllowedWhenNoDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let exporter = ExportBlocker(treeManager: treeManager)
        
        let result = exporter.validateForExport()
        XCTAssertTrue(result.isValid, "Export should be valid when no dirty nodes exist")
        XCTAssertTrue(result.canExport, "canExport should be true when clean")
        XCTAssertFalse(result.requiresOverride, "Should not require override when clean")
        XCTAssertTrue(result.dirtyNodes.isEmpty, "No dirty nodes expected")
        XCTAssertFalse(exporter.isExportBlocked, "Export should not be blocked when clean")
    }
    
    func testExportBlockedWhenDirtyNodeExists() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        let result = exporter.validateForExport()
        
        XCTAssertFalse(result.isValid, "Export should be invalid when dirty nodes exist")
        XCTAssertFalse(result.canExport, "canExport should be false when dirty")
        XCTAssertTrue(result.requiresOverride, "Should require override when dirty")
        XCTAssertEqual(result.dirtyNodes.count, 1, "Should report exactly one dirty node")
        XCTAssertTrue(exporter.isExportBlocked, "Export should be blocked when dirty nodes exist")
    }
    
    func testExportBlocksMultipleDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node1 = treeManager.addOperation("Profile 1")
        let node2 = treeManager.addOperation("Pocket 1")
        node1.markDirty()
        node2.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        let result = exporter.validateForExport()
        
        XCTAssertFalse(result.isValid, "Export should be invalid with multiple dirty nodes")
        XCTAssertEqual(dirtyNodes.count, 2, "Should report both dirty nodes")
    }
    
    func testOverrideAllowsExportDespiteDirtyNodes() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        _ = exporter.validateForExport()
        XCTAssertTrue(exporter.isExportBlocked, "Should be blocked before override")
        
        let overridden = exporter.overrideExportBlock()
        XCTAssertTrue(overridden, "Override should succeed")
        XCTAssertFalse(exporter.isExportBlocked, "Should not be blocked after override")
    }
    
    func testClearDirtyFlagsResolvesBlock() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        let exporter = ExportBlocker(treeManager: treeManager)
        _ = exporter.validateForExport()
        XCTAssertTrue(exporter.isExportBlocked, "Should be blocked before clearing")
        
        exporter.clearDirtyFlags()
        XCTAssertFalse(exporter.isExportBlocked, "Should not be blocked after clearing dirty flags")
    }
    
    func testOverrideOnCleanTreeSucceeds() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let exporter = ExportBlocker(treeManager: treeManager)
        
        let overridden = exporter.overrideExportBlock()
        XCTAssertTrue(overridden, "Override should succeed even on clean tree")
    }
    
    // MARK: - ToolpathTree Dirty State Tests
    
    func testMarkDirtyPropagatesToParent() {
        let treeManager = ToolpathTreeManager(rootName: "Root")
        let node = treeManager.addOperation("Child 1")
        
        XCTAssertFalse(treeManager.root.isDirty, "Root should not be dirty initially")
        node.markDirty()
        XCTAssertTrue(treeManager.root.isDirty, "Parent root should become dirty when child is marked dirty")
    }
    
    func testAllDirtyNodesReturnsOnlyDirty() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let cleanNode = treeManager.addOperation("Clean Node")
        let dirtyNode = treeManager.addOperation("Dirty Node")
        
        dirtyNode.markDirty()
        
        let dirtyNodes = treeManager.root.allDirtyNodes
        XCTAssertEqual(dirtyNodes.count, 1, "Should return exactly one dirty node")
        XCTAssertTrue(dirtyNodes[0].name == "Dirty Node", "Should be the marked dirty node")
    }
    
    func testClearDirtyResolvesNode() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node = treeManager.addOperation("Profile 1")
        node.markDirty()
        
        XCTAssertTrue(node.isDirty, "Node should be dirty after markDirty")
        node.clearDirty()
        XCTAssertFalse(node.isDirty, "Node should not be dirty after clearDirty")
    }
    
    func testRecalculateDirtyNodesResolvesAll() {
        let treeManager = ToolpathTreeManager(rootName: "Test")
        let node1 = treeManager.addOperation("Profile 1")
        let node2 = treeManager.addOperation("Pocket 1")
        node1.markDirty()
        node2.markDirty()
        
        XCTAssertEqual(treeManager.dirtyNodeCount, 2, "Should have two dirty nodes before recalculation")
        
        let recalculated = treeManager.recalculateDirtyNodes()
        XCTAssertEqual(recalculated.count, 2, "Should return both recalculated nodes")
        XCTAssertFalse(node1.isDirty, "First node should not be dirty after recalculation")
        XCTAssertFalse(node2.isDirty, "Second node should not be dirty after recalculation")
    }
    
    // MARK: - Golden Fixture Tests (SPK-0317)
    
    func testGoldenFixtureProfileMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let profileGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 Z5.0
        G0 X-5.0 Y0.0
        G1 Z-2.0 F300
        G1 X5.0 Y0.0 F1000
        G1 X5.0 Y10.0 F1000
        G1 X-5.0 Y10.0 F1000
        G1 X-5.0 Y0.0 F1000
        G0 Z5.0
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.profile, against: profileGcode)
        XCTAssertTrue(result.passed, "Profile fixture should match expected output")
    }
    
    func testGoldenFixturePocketMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let pocketGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 Z5.0
        G0 X0.0 Y0.0
        G1 Z-2.0 F300
        G1 X10.0 Y0.0 F1000
        G1 X10.0 Y10.0 F1000
        G1 X0.0 Y10.0 F1000
        G1 X0.0 Y0.0 F1000
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.pocket, against: pocketGcode)
        XCTAssertTrue(result.passed, "Pocket fixture should match expected output")
    }
    
    func testGoldenFixtureDrillMatches() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let drillGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        M8 ; Flood coolant on
        
        G0 X5.0 Y5.0
        G0 Z5.0
        G1 Z-3.0 F300
        G4 P1.0
        G0 Z5.0
        
        M9 ; Coolant off
        G0 Z5.0 ; Rapid to safe height
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.drill, against: drillGcode)
        XCTAssertTrue(result.passed, "Drill fixture should match expected output")
    }
    
    func testGoldenFixtureMismatchDetected() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        let wrongGcode = """
        G21 ; Set millimeter units
        G90 ; Absolute positioning
        
        G0 Z5.0
        G0 X0 Y0
        M2 ; Program end
        """
        
        let result = manager.verifyFixture(.profile, against: wrongGcode)
        XCTAssertFalse(result.passed, "Mismatched fixture should not pass")
        XCTAssertFalse(result.matches, "Matches should be false for different output")
    }
    
    func testGoldenFixtureNotRegisteredReturnsEmpty() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        
        // Register a custom fixture
        manager.register("G21\nG90\nM2", for: .profile)
        
        let result = manager.verifyFixture(.profile, against: "G21\nG90\nM2")
        XCTAssertTrue(result.passed, "Custom registered fixture should match")
    }
    
    // MARK: - GCode Streamer Tests (SPK-0404)
    
    func testStreamerInitialState() {
        let streamer = GCodeStreamer()
        XCTAssertEqual(streamer.state, .idle, "Should start in idle state")
        XCTAssertEqual(streamer.currentLine, 0, "Current line should be 0 initially")
        XCTAssertEqual(streamer.totalLines, 0, "Total lines should be 0 initially")
    }
    
    func testStreamerProgressTracking() {
        let streamer = GCodeStreamer()
        let lines = ["G21", "G90", "M8", "G0 Z5", "G1 X10 F500"]
        
        // Simulate progress by setting properties directly (since we can't easily test async streaming)
        streamer.totalLines = lines.count
        
        XCTAssertEqual(streamer.progress, 0.0, "Progress should be 0 before starting")
    }
    
    func testGcodeNormalizationRemovesComments() {
        let gcode = """
        G21 ; Set units
        (This is a comment)
        G90
        ; Another comment
        M8
        """
        
        let normalized = normalizeGcode(gcode)
        XCTAssertFalse(normalized.contains(";"), "Normalized should not contain comments")
        XCTAssertFalse(normalized.contains("("), "Normalized should not contain parenthesized comments")
        XCTAssertTrue(normalized.contains("G21"), "Should retain G-code commands")
    }
    
    func testFindDifferencesDetectsLineChanges() {
        let expected = "G21\nG90\nM8"
        let actual = "G21\nG91\nM8" // Different line
        
        let diffs = findGcodeDifferences(expected, actual)
        XCTAssertFalse(diffs.isEmpty, "Should detect differences")
    }
    
    func testFindDifferencesEmptyWhenIdentical() {
        let gcode = "G21\nG90\nM8"
        let diffs = findGcodeDifferences(gcode, gcode)
        XCTAssertTrue(diffs.isEmpty, "No differences when identical")
    }
}
