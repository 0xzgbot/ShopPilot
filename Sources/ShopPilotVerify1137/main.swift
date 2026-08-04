import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1137 verify (CLT machines, no XCTest).
/// Proves the P0-B layer correctness spine end-to-end:
///   1. LayerVisibility.isLocked / editableIndices semantics (locked, unlocked,
///      unassigned back-compat, orphaned layer id).
///   2. GeometryBridge.toCorePaths(_:layerIDs:) assigns per-path layer ids
///      index-aligned with shapes; the single-arg variant stays unassigned.
///   3. Layer-faithful sync: LayerVisibility.distribute gives every layer
///      exactly its own vectors — no cross-layer clobber, no duplication,
///      nothing lost (the AppSession syncLayerVectors shape).
///   4. Full `.shoppilot`-style round-trip: Job with visible/hidden/locked
///      layers survives JSON encode→decode and the load-side reconstruction
///      (AppSession.shapesFromLayerVectors shape) restores per-shape layer
///      membership so canvas filters behave identically after open.
/// The SwiftUI glue (draw filter, hit-test gating) is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeShape(_ tag: Double) -> VectorShape {
    // A tiny freehand polyline; tag shifts coordinates so paths are distinct.
    VectorShape.freehand(points: [
        ShopPilotGeometry.VectorPoint(x: tag, y: 0),
        ShopPilotGeometry.VectorPoint(x: tag, y: 10),
        ShopPilotGeometry.VectorPoint(x: tag + 10, y: 10),
    ])
}

/// Mirror of AppSession.shapesFromLayerVectors: flatten layers in order,
/// rebuild (shapes, layerIDs) from persisted VectorPath.layerId.
func reconstruct(from job: Job) -> (shapes: [VectorShape], layerIDs: [UUID]) {
    var shapes: [VectorShape] = []
    var layerIDs: [UUID] = []
    for layer in job.sheets.flatMap(\.layers) {
        for path in layer.vectors {
            let pts = path.points.map { ShopPilotGeometry.VectorPoint(x: $0.x, y: $0.y) }
            shapes.append(VectorShape.freehand(points: pts))
            layerIDs.append(path.layerId)
        }
    }
    return (shapes, layerIDs)
}

func main() throws {
    // Three layers with distinct roles: visible+unlocked, hidden+unlocked,
    // visible+locked. Every layer ends up holding at least one shape.
    let unlocked = Layer(name: "Cut lines")
    var hidden = Layer(name: "Engrave")
    hidden.isVisible = false
    var locked = Layer(name: "Reference")
    locked.isLocked = true
    let layers3 = [unlocked, hidden, locked]

    // --- 1. Lock / editability semantics -------------------------------------
    let ids3 = [unlocked.id, hidden.id, locked.id, unlocked.id]
    try expect(
        !LayerVisibility.isLocked(index: 0, shapeLayerIDs: ids3, layers: layers3),
        "shape on an unlocked layer is editable"
    )
    try expect(
        !LayerVisibility.isLocked(index: 1, shapeLayerIDs: ids3, layers: layers3),
        "shape on a hidden (but unlocked) layer is editable"
    )
    try expect(
        LayerVisibility.isLocked(index: 2, shapeLayerIDs: ids3, layers: layers3),
        "shape on a locked layer is locked"
    )
    try expect(
        !LayerVisibility.isLocked(index: 0, shapeLayerIDs: [], layers: layers3),
        "unassigned shape (no layerIDs recorded) stays editable (back-compat)"
    )
    try expect(
        LayerVisibility.isLocked(index: 0, shapeLayerIDs: [UUID()], layers: layers3),
        "shape referencing a missing layer is treated as locked (orphan)"
    )
    let editable = LayerVisibility.editableIndices(
        count: ids3.count,
        shapeLayerIDs: ids3,
        layers: layers3
    )
    try expect(editable == [0, 1, 3], "editableIndices returns only unlocked-layer shapes")

    // --- 2. Layer-id conversion (GeometryBridge overload) ---------------------
    let shapes = [makeShape(0), makeShape(100), makeShape(200), makeShape(300)]
    let shapeLayerIDs = ids3  // [unlocked, hidden, locked, unlocked]
    let paths = GeometryBridge.toCorePaths(shapes, layerIDs: shapeLayerIDs)
    try expect(paths.count == 4, "toCorePaths(_:layerIDs:) converts every shape")
    for (i, path) in paths.enumerated() {
        try expect(path.layerId == shapeLayerIDs[i], "path \(i) carries its shape's layer id")
    }
    let unassigned = GeometryBridge.toCorePaths([makeShape(9)])
    try expect(unassigned.count == 1, "single-arg toCorePaths still converts")
    try expect(
        !layers3.contains(where: { $0.id == unassigned[0].layerId }),
        "single-arg toCorePaths leaves layer id unassigned (fresh UUID)"
    )

    // --- 3. Layer-faithful distribution (syncLayerVectors shape) --------------
    var distributable = layers3
    LayerVisibility.distribute(paths, into: &distributable)
    try expect(
        distributable[0].vectors.count == 2,
        "visible layer keeps exactly its own 2 vectors"
    )
    try expect(
        distributable[1].vectors.count == 1,
        "hidden layer keeps exactly its own vector"
    )
    try expect(
        distributable[2].vectors.count == 1,
        "locked layer keeps exactly its own vector"
    )
    let totalAfterDistribute = distributable.reduce(0) { $0 + $1.vectors.count }
    try expect(totalAfterDistribute == 4, "distribute preserves total path count (no dup/loss)")

    // --- 4. Full .shoppilot round-trip (Job Codable) --------------------------
    var job = Job(name: "Layer round-trip")
    _ = job.ensureSingleSheet()
    var persisted = layers3
    LayerVisibility.distribute(paths, into: &persisted)
    job.sheets[0].layers = persisted

    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)

    // Load-side reconstruction restores per-shape layer membership.
    let restored = reconstruct(from: decoded)
    try expect(restored.shapes.count == 4, "reconstruction restores all shapes")
    // Membership is preserved; order is layer-grouped after flattening (all of
    // layer A's shapes, then B's…) — an index order change, not a data change.
    try expect(
        restored.layerIDs.sorted() == shapeLayerIDs.sorted(),
        "reconstruction preserves the per-shape layer id multiset"
    )
    try expect(
        restored.layerIDs.filter { $0 == unlocked.id }.count == 2
            && restored.layerIDs.filter { $0 == hidden.id }.count == 1
            && restored.layerIDs.filter { $0 == locked.id }.count == 1,
        "reconstruction keeps each layer's own shape count"
    )

    // Canvas filters after open behave exactly like before save.
    let decodedLayers = decoded.sheets[0].layers
    let visible = LayerVisibility.visibleIndices(
        count: restored.shapes.count,
        shapeLayerIDs: restored.layerIDs,
        layers: decodedLayers
    )
    try expect(
        visible == [0, 1, 3],
        "after open: hidden-layer shape (index 2) is not drawn, others are"
    )
    let editableAfterOpen = LayerVisibility.editableIndices(
        count: restored.shapes.count,
        shapeLayerIDs: restored.layerIDs,
        layers: decodedLayers
    )
    try expect(
        editableAfterOpen == [0, 1, 2],
        "after open: only the locked-layer shape (index 3) is excluded from editing"
    )

    print("ShopPilotVerify1137: PASS — layer lock/editability, layer-id conversion, faithful distribution, round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1137: FAIL — \(error)")
    exit(1)
}
