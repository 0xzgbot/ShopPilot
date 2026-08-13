import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-UI-BUG-03 verify (CLT executable, no XCTest).
// Proves the Cut-stage generate path no longer runs engine compute on the
// main thread:
//   1. SOURCE: AppSession.swift dispatches single-op generates through the
//      `generateToolpathAsync` helper (DispatchQueue.global background
//      compute + main-actor apply) — not a sync engine call on the button
//      path.
//   2. SOURCE: the Profile "Cut out" button delegates to the async witness
//      `ProfileToolpathGenerator.generateProfileAsync(on: self)`; the sync
//      `generateProfile(on: self)` is gone from AppSession.
//   3. SOURCE: at least 15 strategy generates route through the helper (the
//      sibling Cut buttons: Pocket, V-Carve, Drill, Drill Bank, Wrapped
//      Fluting, Prism, Fluting, Chamfer, Inlay ×2, Quick Engrave, Photo
//      V-Carve, Drag Knife, Texture, Sketch Carve, Rotary Wrap, Rough 3D,
//      Finish 3D, Rest Machine, Thread Mill).
//   4. BEHAVIOR: `generateProfileAsync` completes on a real engine compute
//      off the caller's thread — the fake session receives the node +
//      summary, and the completion fires with true. The empty-vectors guard
//      completes synchronously with false.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Drives the async generator exactly like AppSession would (real engine,
/// real node type, completion observed from the caller's thread).
final class AsyncFakeProfileSession: ProfileGeneratingSession {
    var vectors: [VectorPath] = []
    var shapeLayerIDs: [UUID] = []
    var activeSheetHeightMm: Double = 12.0
    var toolpathNodeCount: Int = 0
    var undoCount = 0
    var node: ToolpathTreeNode?
    var summaries: [String] = []

    func registerUndoPoint() { undoCount += 1 }

    @discardableResult
    func addToolpathNode(named: String, gcode: [String], estimatedTime: Double) -> ToolpathTreeNode {
        let newNode = ToolpathTreeNode(name: named, type: .operation("Profile"))
        newNode.toolpathResult = gcode.joined(separator: "\n")
        newNode.estimatedTimeSeconds = estimatedTime
        node = newNode
        toolpathNodeCount += 1
        return newNode
    }

    func encodeParams<T: Encodable>(_ params: T) -> String? {
        guard let data = try? JSONEncoder().encode(params) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setLastToolpathSummary(_ text: String) { summaries.append(text) }
}

func main() throws {
    // ── 1+2+3. Source contract: off-main dispatch on the Cut path. ────────
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/AppSession.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    try expect(source.contains("generateToolpathAsync(compute:"),
               "AppSession routes single-op generates through the async helper")
    try expect(source.contains("DispatchQueue.global(qos: .userInitiated)"),
               "the helper dispatches compute to a background queue")
    try expect(source.contains("ProfileToolpathGenerator.generateProfileAsync(on: self)"),
               "Cut out delegates to the Core async witness")
    try expect(!source.contains("ProfileToolpathGenerator.generateProfile(on: self)"),
               "no sync generateProfile call remains on the AppSession path")

    let asyncHelperUsages = source.components(separatedBy: "generateToolpathAsync(compute:").count - 1
    try expect(asyncHelperUsages >= 15,
               "sibling Cut buttons route through the helper (found \(asyncHelperUsages) uses)")

    // ── 4a. Empty vectors → completes synchronously with false. ───────────
    let empty = AsyncFakeProfileSession()
    var emptyCompleted = false
    var emptyResult: Bool?
    ProfileToolpathGenerator.generateProfileAsync(on: empty) { ok in
        emptyCompleted = true
        emptyResult = ok
    }
    try expect(emptyCompleted, "empty-vectors guard must complete synchronously")
    try expect(emptyResult == false, "empty vectors → completion(false)")
    try expect(empty.summaries.first?.contains("No vectors") == true,
               "empty vectors → friendly summary")
    try expect(empty.node == nil, "empty vectors → no node created")

    // ── 4b. With vectors → background compute lands the node + summary. ───
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    let session = AsyncFakeProfileSession()
    session.vectors = [square]
    session.shapeLayerIDs = [UUID(), UUID()]

    // The compute runs on a background queue and the generator applies on
    // DispatchQueue.main — a CLI's main thread must service the main queue
    // (no NSApplication run loop here), so drain RunLoop.main until the
    // completion fires (bounded).
    var okResult: Bool?
    ProfileToolpathGenerator.generateProfileAsync(on: session) { ok in
        okResult = ok
    }
    let deadline = Date().addingTimeInterval(30)
    while okResult == nil && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    try expect(okResult != nil, "async generate must complete within 30s")

    try expect(okResult == true, "with vectors → completion(true)")
    try expect(session.undoCount == 1, "one undo point pushed")
    guard let node = session.node else {
        throw VerifyError.failed("async generate created no node")
    }
    let gcode = node.toolpathResult ?? ""
    try expect(!gcode.isEmpty, "node carries real engine g-code (\(gcode.count) chars)")
    try expect(node.name.hasPrefix("Profile"), "node named 'Profile …' (got \(node.name))")
    try expect(node.paramsJSON != nil && node.paramsJSON!.contains("cutMode"),
               "node params JSON encodes ProfileToolpathParams")
    let summary = session.summaries.last ?? ""
    try expect(summary.hasPrefix("Profile: ") && summary.contains("lines"),
               "summary matches the Profile format (got \(summary))")

    print("BUG-03: PASS — Cut generates dispatch off the main thread")
    print("  async helper (\(asyncHelperUsages) strategy generates), Profile async witness, no sync generate on the button path, async completion lands node + summary")
}

do {
    try main()
} catch {
    print("BUG-03: FAIL — \(error)")
    exit(1)
}
