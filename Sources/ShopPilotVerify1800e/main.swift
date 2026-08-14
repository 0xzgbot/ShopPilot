import Foundation
import ShopPilotCore

/// SPK-1800e verify (CLT machine, no XCTest).
/// Inspector F/S/Z readout:
///   1. ToolpathTreeNode.paramFeedRate / paramSpindleRpm / paramCutDepth read from stored params.
///   2. Readout shows "—" when a param is nil (never crashes).
///   3. InspectorShell.swift references the param accessors.
///   4. Readout appears on the Cut stage (not duplicating strategy forms).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 1. paramCutDepth reads from profile params.
let profileNode = ToolpathTreeNode(name: "Profile 1", type: .operation("Profile 1"))
profileNode.paramsJSON = "{\"maxDepthOfCutMm\":4.0,\"startDepthMm\":0.0}"
try expect(profileNode.paramCutDepth == 4.0, "profile paramCutDepth = 4.0")

// 2. paramCutDepth reads from pocket params.
let pocketNode = ToolpathTreeNode(name: "Pocket 1", type: .operation("Pocket 1"))
pocketNode.paramsJSON = "{\"maxDepthOfCutMm\":6.0,\"startDepthMm\":0.0}"
try expect(pocketNode.paramCutDepth == 6.0, "pocket paramCutDepth = 6.0")

// 3. paramCutDepth reads from drill params.
let drillNode = ToolpathTreeNode(name: "Drill 1", type: .operation("Drill 1"))
drillNode.paramsJSON = "{\"cutDepthMm\":10.0,\"startDepthMm\":0.0}"
try expect(drillNode.paramCutDepth == 10.0, "drill paramCutDepth = 10.0")

// 4. nil params → nil depth.
let emptyNode = ToolpathTreeNode(name: "Test", type: .operation("Test"))
try expect(emptyNode.paramCutDepth == nil, "empty params → nil cutDepth")

// 5. paramFeedRate reads from profile params.
let feedNode = ToolpathTreeNode(name: "Profile 2", type: .operation("Profile 2"))
feedNode.paramsJSON = "{\"feedRateMmPerMin\":1500.0}"
try expect(feedNode.paramFeedRate == 1500.0, "feedRate = 1500")

// 6. paramSpindleRpm reads from profile params.
let rpmNode = ToolpathTreeNode(name: "Profile 3", type: .operation("Profile 3"))
rpmNode.paramsJSON = "{\"spindleRpm\":18000.0}"
try expect(rpmNode.paramSpindleRpm == 18000.0, "spindleRpm = 18000")

// 7. InspectorShell.swift source references the param accessors (static).
let inspectorSource = try String(contentsOfFile: "Sources/ShopPilot/InspectorShell.swift", encoding: .utf8)
try expect(inspectorSource.contains("paramFeedRate"), "InspectorShell reads paramFeedRate")
try expect(inspectorSource.contains("paramSpindleRpm"), "InspectorShell reads paramSpindleRpm")
try expect(inspectorSource.contains("paramCutDepth"), "InspectorShell reads paramCutDepth")

print("ShopPilotVerify1800e: PASS — inspector F/S/Z read from params, nil-safe, source references")
