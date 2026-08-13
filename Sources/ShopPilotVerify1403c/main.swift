import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-1403c verify (CLT executable, no XCTest).
// Proves the extracted Profile generation orchestration:
//   1. EMPTY VECTORS → returns false, no node, friendly summary.
//   2. WITH VECTORS → returns true; computes REAL g-code via
//      ProfileToolpathEngine (the same engine the session used), creates one
//      node with the generated lines + time + params JSON; summary matches
//      the "Profile: N lines, ~Xs, P depth pass(es), F finish pass(es)"
//      format.
//   3. LAYER GUARD: if the fake's addToolpathNode reshuffles layer ids (as
//      the real op could), the generator restores them (SPK-UI603a).
//   4. UNDO: registerUndoPoint was called exactly once.
//   5. SOURCE CONTRACT: AppSession.generateProfileToolpath is a one-line
//      delegate to ProfileToolpathGenerator.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Drives the generator exactly like AppSession would (real engine, real
/// node type, controlled layer-reshuffle behavior).
final class FakeProfileSession: ProfileGeneratingSession {
    var vectors: [VectorPath] = []
    var shapeLayerIDs: [UUID] = []
    var activeSheetHeightMm: Double = 12.0
    var toolpathNodeCount: Int = 0
    var undoCount = 0
    var node: ToolpathTreeNode
    var summaries: [String] = []
    var shouldReshuffleLayers = false

    init() {
        node = ToolpathTreeManager().addOperation("Profile 0")
    }

    func registerUndoPoint() { undoCount += 1 }

    @discardableResult
    func addToolpathNode(named: String, gcode: [String], estimatedTime: Double) -> ToolpathTreeNode {
        node = ToolpathTreeNode(name: named, type: .operation("Profile"))
        node.toolpathResult = gcode.joined(separator: "\n")
        node.estimatedTimeSeconds = estimatedTime
        if shouldReshuffleLayers {
            shapeLayerIDs.reverse()   // simulate the op clobbering membership
        }
        toolpathNodeCount += 1
        return node
    }

    func encodeParams<T: Encodable>(_ params: T) -> String? {
        guard let data = try? JSONEncoder().encode(params) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setLastToolpathSummary(_ text: String) { summaries.append(text) }
}

func main() throws {
    // A closed square — the same input the session feeds the engine.
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
    let circle = VectorPath(
        points: [
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: -10, y: 0),
            VectorPoint(x: 0, y: -10),
            VectorPoint(x: 10, y: 0),
        ],
        isClosed: true
    )

    // ── 1. Empty vectors → false, no node, friendly message. ─────────────
    let empty = FakeProfileSession()
    let okEmpty = ProfileToolpathGenerator.generateProfile(on: empty)
    try expect(!okEmpty, "no vectors → returns false")
    try expect(empty.node.toolpathResult == nil, "no vectors → no node g-code")
    try expect(empty.summaries.first?.contains("No vectors") == true,
               "no vectors → friendly summary (got \(empty.summaries.first ?? "nil"))")

    // ── 2. With vectors → real g-code, node, summary. ────────────────────
    let session = FakeProfileSession()
    let layerA = UUID()
    let layerB = UUID()
    session.vectors = [square, circle]
    session.shapeLayerIDs = [layerA, layerB]

    let ok = ProfileToolpathGenerator.generateProfile(on: session)
    try expect(ok, "with vectors → returns true")
    try expect(session.undoCount == 1, "one undo point pushed")

    let gcode = session.node.toolpathResult ?? ""
    try expect(!gcode.isEmpty, "generated real g-code (\(gcode.count) chars)")
    try expect(gcode.contains("G0") || gcode.contains("G1") || gcode.contains("G2") || gcode.contains("G3"),
               "g-code contains motion words")

    // Node wiring.
    try expect(session.node.name.hasPrefix("Profile"), "node named 'Profile …' (got \(session.node.name))")
    try expect(session.node.estimatedTimeSeconds >= 0, "node carries estimated time")
    try expect(session.node.paramsJSON != nil && session.node.paramsJSON!.contains("cutMode"),
               "node params JSON encodes ProfileToolpathParams")

    // Summary format.
    let summary = session.summaries.last ?? ""
    try expect(summary.hasPrefix("Profile: ") && summary.contains("lines")
               && summary.contains("depth pass") && summary.contains("finish pass"),
               "summary matches the Profile format (got \(summary))")

    // Layer membership untouched when the op behaves.
    try expect(session.shapeLayerIDs == [layerA, layerB], "layer membership unchanged by a well-behaved op")

    // ── 3. Layer guard: a reshuffling op gets its clobber undone. ────────
    let ruffling = FakeProfileSession()
    let rLayerA = UUID()
    let rLayerB = UUID()
    ruffling.vectors = [circle, square]
    ruffling.shapeLayerIDs = [rLayerA, rLayerB]
    ruffling.shouldReshuffleLayers = true   // addToolpathNode reverses → [rLayerB, rLayerA]
    _ = ProfileToolpathGenerator.generateProfile(on: ruffling)
    try expect(ruffling.shapeLayerIDs == [rLayerA, rLayerB],
               "generator restores layer membership after unexpected reshuffle (got \(ruffling.shapeLayerIDs))")
    try expect(ruffling.summaries.last?.contains("restored layer membership") == true,
               "restore note published (got \(ruffling.summaries.last ?? "nil"))")

    // ── 4. Source contract: async one-line delegate (SPK-UI-BUG-03). ──────
    // The Cut button path must dispatch through the async witness (off-main
    // engine compute); the sync `generateProfile(on:)` stays in Core for
    // tests/CLTs but must NOT be on the AppSession button path anymore.
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/AppSession.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    try expect(source.contains("ProfileToolpathGenerator.generateProfileAsync(on: self)"),
               "AppSession.generateProfileToolpath delegates to Core async witness")
    try expect(!source.contains("ProfileToolpathGenerator.generateProfile(on: self)"),
               "sync generateProfile is no longer on the Cut button path")
    try expect(source.contains("ProfileGeneratingSession"),
               "AppSession conforms to ProfileGeneratingSession")

    print("1403c: PASS — profile generate extracted to Core ProfileToolpathGenerator")
    print("  empty-guard, real engine g-code, node + params + summary, undo once, layer-guard, one-line delegate")
}

do {
    try main()
} catch {
    print("1403c: FAIL — \(error)")
    exit(1)
}
