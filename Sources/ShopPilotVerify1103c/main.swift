import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1103c verify: selected toolpath node highlights its wireframe segments in Preview.
///
/// Tests:
///  - ToolpathTreeManager.addOperation + findNode + toolpathResult
///  - WireframeRenderer generates correct segment count from gcode
///  - Simulates AppSession.selectedToolpathSegments logic inline
///  - No selection → nil segments
///  - Selecting a node with no toolpathResult → nil

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Simulates AppSession.selectedToolpathSegments logic.
func selectedSegments(for id: UUID?, tree: ToolpathTreeManager) -> [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]? {
    guard let id = id,
          let node = tree.findNode(id: id),
          let gcode = node.toolpathResult else { return nil }
    return WireframeRenderer.generateSegments(from: gcode.components(separatedBy: .newlines))
}

func main() throws {
    // 1. Build a tree, add an operation, set its toolpathResult
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile 1")
    let gcodeLines = [
        "G21", "G90", "G0 X0 Y0", "G1 Z-2 F300",
        "G1 X50 Y0 F800", "G1 X50 Y30", "G1 X0 Y30", "G1 X0 Y0",
        "G0 Z5",
    ]
    node.toolpathResult = gcodeLines.joined(separator: "\n")

    // 2. Verify findNode returns the node
    guard let found = tree.findNode(id: node.id) else {
        throw VerifyError.failed("findNode returned nil for added node")
    }
    try expect(found.id == node.id, "findNode returned correct node")
    try expect(found.toolpathResult == gcodeLines.joined(separator: "\n"), "toolpathResult preserved")

    // 3. WireframeRenderer produces segments from that gcode
    let segments = WireframeRenderer.generateSegments(from: gcodeLines)
    try expect(segments.count >= 3, "expected ≥3 segments from toolpath gcode, got \(segments.count)")

    // 4. No selection → nil selected segments
    try expect(selectedSegments(for: nil, tree: tree) == nil, "no selection → nil segments")

    // 5. Select the node → should return its segments
    guard let selSegs = selectedSegments(for: node.id, tree: tree) else {
        throw VerifyError.failed("selected toolpath segments was nil after select")
    }
    try expect(selSegs.count == segments.count, "selected segments count matches: \(selSegs.count) == \(segments.count)")

    // 6. Select a non-existent node → nil
    try expect(selectedSegments(for: UUID(), tree: tree) == nil, "non-existent node → nil segments")

    // 7. Select a node with no toolpathResult → nil
    let emptyNode = tree.addOperation("Empty Op")
    try expect(selectedSegments(for: emptyNode.id, tree: tree) == nil, "node with no toolpathResult → nil segments")

    print("ShopPilotVerify1103c PASS — segments=\(segments.count) selected=\(selSegs.count)")
}

do {
    try main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
