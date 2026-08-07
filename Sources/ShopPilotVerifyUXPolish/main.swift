import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// UI-polish cluster verify (CLT machines, no XCTest).
/// Proves the engine gates the cluster rides on:
///   1. Group / Ungroup (`ShapeGroupEngine`): grouping folds groups + folds
///      selection; ungrouping dissolves; transforms expand to whole groups;
///      deleted indices are pruned; persisted groups are sanitized on load.
///   2. Set Size (`ShapeTransformer.setSize`): exact W×H of the selection
///      bbox with the center preserved; aspect-lock uses the smaller factor.
///   3. View presets (`HeightfieldCamera.apply`): Fit shows the whole grid,
///      1:1 clamps to zoom 1, Top is 2× fit — all within the zoom clamp.
///   4. Canvas overlay chips (`CanvasOverlayOptions` + store): flag math and
///      the UserDefaults round-trip.
///   5. Customizable shortcuts (`ShortcutStore`): override precedence,
///      normalization, reset.
///   6. First-run gate (`FirstRunGate`): first-run → acknowledge → done.
/// The button/UI glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func main() throws {
    // ══ 1. ShapeGroupEngine ═══════════════════════════════════════════════
    // Grouping two shapes folds them into one group; selection expands to it.
    let groups1 = ShapeGroupEngine.grouping(selected: [0, 1], existing: [], shapeCount: 4)
    try expect(groups1 == [[0, 1]], "grouping [0,1] forms [[0,1]]")

    // Selecting a NON-member and grouping creates a second group (multi-group).
    let groups2 = ShapeGroupEngine.grouping(selected: [3], existing: groups1, shapeCount: 4)
    try expect(groups2 == [[0, 1], [3]], "grouping a non-member creates a second group")

    // Expanded selection: selecting one member selects all members.
    let expanded = ShapeGroupEngine.expandedSelection(selected: [1], groups: groups2)
    try expect(expanded == [0, 1], "selection expands to whole group (only group [0,1])")

    // Selecting members of BOTH groups and grouping folds them into one.
    let groups2b = ShapeGroupEngine.grouping(selected: [1, 3], existing: groups2, shapeCount: 4)
    try expect(groups2b == [[0, 1, 3]], "grouping members of both groups folds them in")

    // Ungrouping one member keeps the others grouped.
    let groups3 = ShapeGroupEngine.ungrouping(selected: [0], existing: groups2b)
    try expect(groups3 == [[1, 3]], "ungroup drops the selected member only")

    // Ungrouping all remaining members dissolves the group entirely.
    let groups4 = ShapeGroupEngine.ungrouping(selected: [1, 3], existing: groups3)
    try expect(groups4.isEmpty, "ungroup all members dissolves the group")

    // Removing indices (deletion) prunes them; empty groups disappear.
    let groups5 = ShapeGroupEngine.removing(indices: [2], from: [[0, 1, 2], [5]])
    try expect(groups5 == [[0, 1], [5]], "removing prunes dead indices")

    // Sanitization clamps/drops out-of-range indices (legacy-safe load).
    let sanitized = ShapeGroupEngine.sanitized([[0, 9], [1], [99]], shapeCount: 4)
    try expect(sanitized == [[0], [1]], "sanitized drops out-of-range + empty groups")

    // ══ 2. ShapeTransformer.setSize ════════════════════════════════════════
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 20), width: 50, height: 25)
    let circle = VectorShape.circle(center: VectorPoint(x: 60, y: 45), radius: 10)
    let shapes = [rect, circle]  // bbox 10..70 × 20..55 → 60 × 35, center (40, 37.5)

    let resized = ShapeTransformer().setSize(shapes: shapes, width: 120, height: 70)
    let resizedUnion = resized.map { $0.boundingRect }.reduce(Rect(minX: .greatestFiniteMagnitude, minY: .greatestFiniteMagnitude, maxX: -.greatestFiniteMagnitude, maxY: -.greatestFiniteMagnitude)) { acc, r in
        Rect(minX: min(acc.minX, r.minX), minY: min(acc.minY, r.minY), maxX: max(acc.maxX, r.maxX), maxY: max(acc.maxY, r.maxY))
    }
    try expectClose(resizedUnion.maxX - resizedUnion.minX, 120, "setSize width 120 (union bbox)")
    try expectClose(resizedUnion.maxY - resizedUnion.minY, 70, "setSize height 70 (union bbox)")
    try expectClose(resized[0].boundingRect.width, 100, "rect scaled ×2 → 100 wide")
    try expectClose(resized[0].boundingRect.height, 50, "rect scaled ×2 → 50 tall")
    let resizedCentroid = selectionCentroid(of: resized)!
    try expectClose(resizedCentroid.x, 40, "setSize keeps centroid x")
    try expectClose(resizedCentroid.y, 37.5, "setSize keeps centroid y")

    // Aspect-lock: requesting 120×140 with lock uses the smaller factor
    // (fx=2, fy=4 → 2), so the union scales to 120×70 — never distorted.
    let locked = ShapeTransformer().setSize(shapes: shapes, width: 120, height: 140, preserveAspect: true)
    let lockedUnion = locked.map { $0.boundingRect }.reduce(Rect(minX: .greatestFiniteMagnitude, minY: .greatestFiniteMagnitude, maxX: -.greatestFiniteMagnitude, maxY: -.greatestFiniteMagnitude)) { acc, r in
        Rect(minX: min(acc.minX, r.minX), minY: min(acc.minY, r.minY), maxX: max(acc.maxX, r.maxX), maxY: max(acc.maxY, r.maxY))
    }
    let lockedCentroid = selectionCentroid(of: locked)!
    try expectClose(lockedCentroid.x, 40, "locked setSize keeps centroid x")
    try expectClose(lockedCentroid.y, 37.5, "locked setSize keeps centroid y")
    try expectClose(lockedUnion.maxX - lockedUnion.minX, 120, "locked setSize union width = 60×2")
    try expectClose(lockedUnion.maxY - lockedUnion.minY, 70, "locked setSize union height = 35×2")

    // ══ 3. HeightfieldCamera view presets ══════════════════════════════════
    var cam = HeightfieldCamera(zoom: 3.0, panX: 5, panY: -5, cellSizeMm: 1.0)
    // Fit: 20×10 grid in a 200×200 viewport → zoom = min(200/20, 200/10) = 10 → clamped 8.
    cam.apply(.fit, viewport: (200, 200), gridWidth: 20, gridHeight: 10)
    try expectClose(cam.zoom, 8.0, "fit clamps to 8 (was 10)")
    try expectClose(cam.panX, 0, "fit resets panX")
    try expectClose(cam.panY, 0, "fit resets panY")
    // 1:1 clamps to zoom 1.
    cam.apply(.oneToOne, viewport: (200, 200), gridWidth: 20, gridHeight: 10)
    try expectClose(cam.zoom, 1.0, "1:1 zoom = 1")
    // Top: 2× fit — fit would be 10 (clamped 8) → 8×2=16 → clamped 8? No:
    // fit computed from unclamped numbers then doubled: 10×2 = 20 → 8.
    cam.apply(.top, viewport: (200, 200), gridWidth: 20, gridHeight: 10)
    try expectClose(cam.zoom, 8.0, "top clamps to 8")
    cam.apply(.top, viewport: (400, 200), gridWidth: 40, gridHeight: 20)
    try expectClose(cam.zoom, 8.0, "top = 2× fit then clamped (fit 10 → 20 → 8)")

    // ══ 4. Canvas overlay options ══════════════════════════════════════════
    var overlays: CanvasOverlayOptions = [.vectors, .toolpaths]
    try expect(overlays.contains(.vectors), "vectors flag set")
    try expect(!overlays.contains(.keepOuts), "keepOuts flag clear")
    overlays.insert(.keepOuts)
    try expect(overlays.contains(.keepOuts), "insert keepOuts")
    overlays.subtract(.vectors)
    try expect(!overlays.contains(.vectors), "subtract vectors")
    try expect(CanvasOverlayOptions.chips.count == 4, "four chips defined")
    try expect(CanvasOverlayOptions.option(at: 0) == .vectors, "chip 0 = vectors")

    // UserDefaults round-trip.
    let prior = CanvasOverlayStore.load()
    CanvasOverlayStore.save([.vectors])
    try expect(CanvasOverlayStore.load() == [.vectors], "overlay store round-trip")
    CanvasOverlayStore.save(prior)

    // ══ 5. ShortcutStore ═══════════════════════════════════════════════════
    ShortcutStore.resetAll()
    try expect(ShortcutStore.shortcut(for: "undo", default: "z") == "z", "default shortcut used")
    ShortcutStore.setOverride("shift+z", for: "undo")
    try expect(ShortcutStore.shortcut(for: "undo", default: "z") == "shift+z", "override wins")
    try expect(ShortcutStore.normalize("  Shift+Z ") == "shift+z", "normalize lowercases + trims")
    ShortcutStore.setOverride(nil, for: "undo")
    try expect(ShortcutStore.shortcut(for: "undo", default: "z") == "z", "clearing override restores default")
    ShortcutStore.resetAll()

    // ══ 6. FirstRunGate ════════════════════════════════════════════════════
    FirstRunGate.reset()
    try expect(FirstRunGate.isFirstRun, "first run is true after reset")
    FirstRunGate.acknowledge()
    try expect(!FirstRunGate.isFirstRun, "acknowledge ends first run")
    FirstRunGate.reset()

    print("ShopPilotVerifyUXPolish: PASS — group/ungroup, set-size, view presets, overlay chips, shortcut store, first-run gate")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyUXPolish: FAIL — \(error)")
    exit(1)
}
