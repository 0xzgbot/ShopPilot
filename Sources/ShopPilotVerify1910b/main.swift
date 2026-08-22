import Foundation
import ShopPilotCore

// SPK-1910b — Trochoid Slot tree + recalc CLT (no UI, no XCTest).
//   1. A "Trochoid Slot N" node classifies as .trochoidSlot ("Trochoid Slot"
//      displayName, no collision with "Thread Mill").
//   2. Recalc regenerates a dirty trochoid node from stored paramsJSON.
//   3. Mutating WOC in the stored params + recalc changes the G-code
//      (loop count grows when WOC shrinks) — the persist→recalc loop works.
//   4. Too-narrow slot still recalcs to header-only G-code (node clears).
//   5. Round-trip: paramsJSON decode returns the stored WOC.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeSlotRect(lengthMm: Double, widthMm: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 10 + lengthMm, y: 10),
            VectorPoint(x: 10 + lengthMm, y: 10 + widthMm),
            VectorPoint(x: 10, y: 10 + widthMm),
            VectorPoint(x: 10, y: 10),
        ],
        isClosed: true
    )
}

func encodeParams<T: Encodable>(_ params: T) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func main() throws {
    let slot = makeSlotRect(lengthMm: 80, widthMm: 8)

    // ── 1. Strategy classification. ────────────────────────────────────────
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Trochoid Slot 7")
    try expect(node.strategyKind == .trochoidSlot, "Trochoid Slot node → .trochoidSlot")
    try expect(node.strategyKind.displayName == "Trochoid Slot", "displayName is 'Trochoid Slot'")
    try expect(node.strategyKind.displayName != "Thread Mill", "no Thread Mill collision")
    // Neighbors still classify correctly.
    let tm = tree.addOperation("Thread Mill 8")
    try expect(tm.strategyKind == .threadMill, "Thread Mill still classifies")
    let tx = tree.addOperation("Texture 9")
    try expect(tx.strategyKind == .texture, "Texture still classifies")

    // ── 2 + 3. Persist params → recalc → WOC mutation → recalc changes. ───
    var params = TrochoidSlotParams(
        toolDiameterMm: 6.35,
        cutDepthMm: 4.0,
        maxDepthOfCutMm: 2.0,
        maxWocMm: 0.8,
        loopPitchMm: 0.6
    )
    node.paramsJSON = encodeParams(params)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [slot],
        material: nil,
        stockHeightMm: 12.0
    )
    try expect(regenerated.count == 1, "recalc regenerated the dirty Trochoid node")
    try expect(!node.isDirty, "node cleared its dirty badge")
    var gcode = node.toolpathResult ?? ""
    try expect(gcode.contains("O=TROCHOID_SLOT"), "recalc output is real engine G-code")

    func loopCount(_ g: String) -> Int {
        g.components(separatedBy: .newlines).filter { $0.hasPrefix("G3 ") || $0.hasPrefix("G2 ") }.count
    }
    let baseLoops = loopCount(gcode)
    try expect(baseLoops > 0, "recalc emitted loops (\(baseLoops))")

    // Mutate WOC smaller in the STORED params, recalc → more loops.
    params.maxWocMm = 0.4
    node.paramsJSON = encodeParams(params)
    node.markDirty()
    _ = tree.recalculateDirtyToolpaths(vectors: [slot], material: nil, stockHeightMm: 12.0)
    gcode = node.toolpathResult ?? ""
    let fineLoops = loopCount(gcode)
    try expect(fineLoops > baseLoops,
               "smaller stored WOC → more loops after recalc (\(fineLoops) > \(baseLoops))")

    // Stored WOC round-trips through paramsJSON.
    try expect(abs(node.trochoidSlotParams().maxWocMm - 0.4) < 1e-9,
               "stored WOC 0.4 round-trips from paramsJSON")

    // ── 4. Too-narrow slot: recalc still completes (header-only). ─────────
    let tree2 = ToolpathTreeManager()
    let narrow = tree2.addOperation("Trochoid Slot 1")
    narrow.paramsJSON = encodeParams(TrochoidSlotParams(toolDiameterMm: 6.35, cutDepthMm: 2.0))
    narrow.markDirty()
    _ = tree2.recalculateDirtyToolpaths(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 5)],
        material: nil,
        stockHeightMm: 12.0
    )
    try expect(!narrow.isDirty, "too-narrow node still clears its dirty badge")
    let ng = narrow.toolpathResult ?? ""
    try expect(ng.contains("O=TROCHOID_SLOT"), "too-narrow output keeps the header")
    try expect(!ng.components(separatedBy: .newlines).contains { $0.hasPrefix("G1 ") || $0.hasPrefix("G2 ") || $0.hasPrefix("G3 ") },
               "too-narrow recalc emits zero cut moves")

    // ── 5. Legacy safety on a fresh node with no paramsJSON. ──────────────
    let tree3 = ToolpathTreeManager()
    let bare = tree3.addOperation("Trochoid Slot 2")
    bare.markDirty()
    _ = tree3.recalculateDirtyToolpaths(vectors: [slot], material: nil, stockHeightMm: 12.0)
    try expect((bare.toolpathResult ?? "").contains("O=TROCHOID_SLOT"),
               "node without stored params recalcs with defaults")

    print("ShopPilotVerify1910b: PASS — trochoid slot tree + recalc "
        + "(\(baseLoops)→\(fineLoops) loops on WOC 0.8→0.4, classification + too-narrow clear)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1910b: FAIL — \(error)")
    exit(1)
}
