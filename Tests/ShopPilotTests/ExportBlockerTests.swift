import XCTest
@testable import ShopPilotCore

// MARK: - ExportBlocker Tests

/// Tests for SPK-0603: Dirty toolpath cannot export without override.
final class ExportBlockerTests: XCTestCase {
    
    // MARK: - Test: Export blocked when dirty nodes exist
    
    func testValidateForExportBlocksWhenDirty() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        // Add a dirty node
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.markDirty()
        
        let result = blocker.validateForExport()
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.requiresOverride)
        XCTAssertEqual(result.dirtyNodes.count, 1)
        XCTAssertEqual(result.dirtyNodes[0], "Profile 1")
        XCTAssertTrue(blocker.isExportBlocked)
        XCTAssertFalse(blocker.dirtyNodeNames.isEmpty)
    }
    
    func testValidateForExportBlocksMultipleDirtyNodes() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.markDirty()
        
        let pocketNode = treeManager.addOperation("Pocket 1")
        pocketNode.markDirty()
        
        let result = blocker.validateForExport()
        
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.dirtyNodes.count, 2)
        XCTAssertTrue(result.dirtyNodes.contains("Profile 1"))
        XCTAssertTrue(result.dirtyNodes.contains("Pocket 1"))
    }
    
    // MARK: - Test: Export allowed when all nodes are clean
    
    func testValidateForExportAllowsWhenClean() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.isDirty = false // Already clean by default
        
        let result = blocker.validateForExport()
        
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.requiresOverride)
        XCTAssertTrue(result.canExport)
        XCTAssertFalse(blocker.isExportBlocked)
        XCTAssertTrue(blocker.dirtyNodeNames.isEmpty)
    }
    
    // MARK: - Test: Override export block
    
    func testOverrideExportBlockAllowsExport() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.markDirty()
        
        // First validate — should be blocked
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(blocker.isExportBlocked)
        
        // Override
        let overridden = blocker.overrideExportBlock()
        XCTAssertTrue(overridden)
        XCTAssertFalse(blocker.isExportBlocked)
        XCTAssertEqual(blocker.blockedReason, "Export overridden by user")
    }
    
    func testOverrideExportBlockWhenNotBlocked() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        // No dirty nodes
        let overridden = blocker.overrideExportBlock()
        XCTAssertTrue(overridden)
        XCTAssertFalse(blocker.isExportBlocked)
    }
    
    // MARK: - Test: Clear dirty flags
    
    func testClearDirtyFlagsResetsBlocker() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.markDirty()
        
        // Validate — should be blocked
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(blocker.isExportBlocked)
        
        // Clear dirty flags
        blocker.clearDirtyFlags()
        
        XCTAssertFalse(blocker.isExportBlocked)
        XCTAssertTrue(blocker.dirtyNodeNames.isEmpty)
        XCTAssertTrue(blocker.blockedReason.isEmpty)
        
        // Validate again — should pass
        let result2 = blocker.validateForExport()
        XCTAssertTrue(result2.isValid)
    }
    
    func testClearDirtyFlagsResetsAllDirtyNodes() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.markDirty()
        
        let pocketNode = treeManager.addOperation("Pocket 1")
        pocketNode.markDirty()
        
        blocker.clearDirtyFlags()
        
        XCTAssertFalse(profileNode.isDirty)
        XCTAssertFalse(pocketNode.isDirty)
        XCTAssertEqual(treeManager.dirtyNodeCount, 0)
    }
    
    // MARK: - Test: Dirty node detection when vectors modified
    
    func testDirtyNodeDetectionOnVectorModification() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.toolpathResult = "G0 Z5\nG1 X10"
        profileNode.isDirty = false
        
        // Simulate vector modification
        profileNode.markDirty()
        
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(profileNode.isDirty)
    }
    
    func testDirtyNodeDetectionOnToolpathParameterChange() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        let profileNode = treeManager.addOperation("Profile 1")
        profileNode.toolpathResult = "G0 Z5\nG1 X10"
        profileNode.isDirty = false
        
        // Simulate toolpath parameter change
        profileNode.markDirty()
        
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.dirtyNodes.contains("Profile 1"))
    }
    
    // MARK: - Test: Dirty propagation to parent nodes
    
    func testDirtyPropagationToParent() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        // Add a group with a dirty child
        let groupNode = treeManager.addGroup("Operations")
        let childNode = groupNode.addChild(ToolpathTreeNode(name: "Profile 1", type: .operation("Profile 1")))
        childNode.markDirty()
        
        // Parent should also be dirty
        XCTAssertTrue(groupNode.isDirty)
        
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.dirtyNodes.contains("Profile 1"))
    }
    
    // MARK: - Test: Tree manager dirty tracking
    
    func testDirtyNodeCount() {
        let treeManager = ToolpathTreeManager()
        
        let node1 = treeManager.addOperation("Profile 1")
        node1.markDirty()
        
        let node2 = treeManager.addOperation("Pocket 1")
        node2.markDirty()
        
        let node3 = treeManager.addOperation("Drill 1")
        // node3 is clean
        
        XCTAssertEqual(treeManager.dirtyNodeCount, 2)
    }
    
    func testRecalculateDirtyNodesClearsDirtyFlags() {
        let treeManager = ToolpathTreeManager()
        
        let node1 = treeManager.addOperation("Profile 1")
        node1.markDirty()
        
        let node2 = treeManager.addOperation("Pocket 1")
        node2.markDirty()
        
        let recalculated = treeManager.recalculateDirtyNodes()
        
        XCTAssertEqual(recalculated.count, 2)
        XCTAssertFalse(node1.isDirty)
        XCTAssertFalse(node2.isDirty)
        XCTAssertEqual(treeManager.dirtyNodeCount, 0)
        XCTAssertNotNil(node1.toolpathResult)
        XCTAssertNotNil(node2.toolpathResult)
    }
    
    // MARK: - Test: Empty tree
    
    func testEmptyTreeNoDirtyNodes() {
        let treeManager = ToolpathTreeManager()
        let blocker = ExportBlocker(treeManager: treeManager)
        
        XCTAssertFalse(treeManager.root.isDirty)
        XCTAssertTrue(treeManager.root.allDirtyNodes.isEmpty)
        XCTAssertEqual(treeManager.dirtyNodeCount, 0)
        
        let result = blocker.validateForExport()
        XCTAssertTrue(result.isValid)
    }
    
    // MARK: - Test: Complex tree structure
    
    func testComplexTreeDirtyTracking() {
        let treeManager = ToolpathTreeManager()
        
        let group1 = treeManager.addGroup("Group 1")
        let node1 = group1.addChild(ToolpathTreeNode(name: "Profile 1", type: .operation("Profile 1")))
        let node2 = group1.addChild(ToolpathTreeNode(name: "Pocket 1", type: .operation("Pocket 1")))
        
        let group2 = treeManager.addGroup("Group 2")
        let node3 = group2.addChild(ToolpathTreeNode(name: "Drill 1", type: .operation("Drill 1")))
        
        // Mark some dirty
        node1.markDirty()
        node3.markDirty()
        
        // Verify dirty count
        XCTAssertEqual(treeManager.dirtyNodeCount, 2)
        
        // Verify parent groups are dirty
        XCTAssertTrue(group1.isDirty)
        XCTAssertTrue(group2.isDirty)
        
        // Verify root is dirty
        XCTAssertTrue(treeManager.root.isDirty)
        
        // Validate — should block
        let blocker = ExportBlocker(treeManager: treeManager)
        let result = blocker.validateForExport()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.dirtyNodes.count, 2)
    }
    
    // MARK: - Test: ExportValidationResult properties
    
    func testExportValidationResultProperties() {
        let validResult = ExportValidationResult(
            isValid: true,
            dirtyNodes: [],
            warnings: []
        )
        XCTAssertTrue(validResult.isValid)
        XCTAssertTrue(validResult.canExport)
        XCTAssertFalse(validResult.requiresOverride)
        
        let invalidResult = ExportValidationResult(
            isValid: false,
            dirtyNodes: ["Profile 1"],
            warnings: ["Export blocked: Profile 1"]
        )
        XCTAssertFalse(invalidResult.isValid)
        XCTAssertFalse(invalidResult.canExport)
        XCTAssertTrue(invalidResult.requiresOverride)
    }
}
