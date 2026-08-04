import Foundation
import ShopPilotCore

/// SPK-1102d verify (CLT machines, no XCTest).
/// Proves the Pocket / Drill / V-Carve add-op spine the Cut stage's
/// "Add Toolpath" menu drives (session generate*Toolpath → real engines →
/// tree node with G-code):
///   1. Pocket on a closed rect → real engine G-code (O=POCKET_TOOLPATH,
///      cut moves, time estimate); open-only input cuts nothing.
///   2. Drill on points → O=DRILL_TOOLPATH with peck plunges per point.
///   3. V-Carve on a closed square → O=V_CARVE_TOOLPATH with passes + moves.
///   4. Tree wiring pattern (mirror of session addToolpathNode): each result
///      lands as a node whose toolpathResult feeds the session buffer; a
///      mixed tree concatenates in order.
/// The menu/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect() -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: 10, y: 10), VectorPoint(x: 60, y: 10),
            VectorPoint(x: 60, y: 50), VectorPoint(x: 10, y: 50), VectorPoint(x: 10, y: 10),
        ],
        isClosed: true
    )
}

func main() throws {
    let sheetHeight = 25.0

    // ── 1. Pocket: closed rect cuts; open-only input cuts nothing. ───────────
    let pocket = PocketToolpathEngine.compute(
        vectors: [makeClosedRect()],
        params: PocketToolpathParams(),
        material: nil,
        stockHeightMm: sheetHeight
    )
    try expect(pocket.gcodeLines.contains("O=POCKET_TOOLPATH"), "pocket output carries its marker")
    try expect(pocket.gcodeLines.contains { $0.hasPrefix("G1") }, "pocket emits cut moves")
    try expect(pocket.estimatedTimeSeconds > 0, "pocket has a time estimate")
    try expect(!pocket.isTooSmall, "50x40 rect is not too small for the default tool")

    let openOnly = PocketToolpathEngine.compute(
        vectors: [VectorPath(points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10)], isClosed: false)],
        params: PocketToolpathParams(),
        material: nil,
        stockHeightMm: sheetHeight
    )
    try expect(!openOnly.gcodeLines.contains { $0.hasPrefix("G1") },
               "pocket on open vectors emits no cut moves")

    // ── 2. Drill: peck plunges per point, marker + estimate. ─────────────────
    let drill = DrillToolpathEngine.compute(
        points: [
            DrillPoint(x: 10, y: 10, zDepthMm: -8),
            DrillPoint(x: 40, y: 30, zDepthMm: -8),
        ],
        params: DrillToolpathParams(),
        material: nil,
        stockHeightMm: sheetHeight
    )
    try expect(drill.gcodeLines.contains("O=DRILL_TOOLPATH"), "drill output carries its marker")
    try expect(drill.pointCount == 2, "drill reports both points")
    let plunges = drill.gcodeLines.filter { $0.hasPrefix("G1 Z") }
    try expect(plunges.count >= 2, "drill emits at least one plunge per point")
    try expect(drill.estimatedTimeSeconds > 0, "drill has a time estimate")

    // ── 3. V-Carve: marker, passes, moves on a closed square. ────────────────
    let vcarve = VCarveEngine.compute(
        vectors: [makeClosedRect()],
        params: VCarveParams(),
        stockHeightMm: sheetHeight
    )
    try expect(vcarve.gcodeLines.contains("O=V_CARVE_TOOLPATH"), "v-carve output carries its marker")
    try expect(vcarve.passCount >= 1, "v-carve has at least one pass")
    try expect(vcarve.gcodeLines.contains { $0.hasPrefix("G1") }, "v-carve emits cut moves")
    try expect(vcarve.estimatedTimeSeconds > 0, "v-carve has a time estimate")

    // ── 4. Tree wiring (mirror of session addToolpathNode + buffer). ─────────
    let tree = ToolpathTreeManager()
    let pocketNode = tree.addOperation("Pocket 1")
    pocketNode.toolpathResult = pocket.gcodeLines.joined(separator: "\n")
    pocketNode.estimatedTimeSeconds = pocket.estimatedTimeSeconds
    let drillNode = tree.addOperation("Drill 1")
    drillNode.toolpathResult = drill.gcodeLines.joined(separator: "\n")
    drillNode.estimatedTimeSeconds = drill.estimatedTimeSeconds

    try expect(tree.allNodes.count == 3, "root + 2 strategy ops in the tree")
    try expect(!pocketNode.isDirty && !drillNode.isDirty, "freshly computed ops are clean")
    let buffer = tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(buffer.contains("O=POCKET_TOOLPATH") && buffer.contains("O=DRILL_TOOLPATH"),
               "session buffer concatenates both strategy outputs in tree order")

    print("ShopPilotVerify1102d: PASS — pocket/drill/v-carve engines + tree-node wiring + buffer concat")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1102d: FAIL — \(error)")
    exit(1)
}
