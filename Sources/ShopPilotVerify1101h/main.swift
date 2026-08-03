import Foundation
import ShopPilotCore

/// SPK-1101h verify (CLT machines, no XCTest).
/// Proves that layer visibility controls which vectors the design canvas shows:
///   1. LayerVisibility.isVisible / visibleIndices semantics (visible, hidden,
///      unassigned, dangling layer id).
///   2. LayerVisibility.distribute splits a flat path list into per-layer
///      vectors by layerId and clears stale vectors (the persistence shape).
///   3. End-to-end: shapes assigned to two layers, one hidden, survive a
///      .shoppilot round-trip and still filter to the visible layer only —
///      the same reconstruction AppSession performs on load.
/// The AppSession/UI glue (eye toggle → setLayerVisible, canvas draw filter)
/// is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makePath(_ layerID: UUID) -> VectorPath {
    VectorPath(
        points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10)],
        isClosed: false,
        layerId: layerID
    )
}

func main() throws {
    let visibleLayer = Layer(name: "Cut lines")
    var hiddenLayer = Layer(name: "Engrave")
    hiddenLayer.isVisible = false
    let layers = [visibleLayer, hiddenLayer]

    // 1. Visibility semantics.
    let ids = [visibleLayer.id, hiddenLayer.id]
    try expect(
        LayerVisibility.isVisible(index: 0, shapeLayerIDs: ids, layers: layers),
        "shape on a visible layer is visible"
    )
    try expect(
        !LayerVisibility.isVisible(index: 1, shapeLayerIDs: ids, layers: layers),
        "shape on a hidden layer is hidden"
    )
    try expect(
        LayerVisibility.isVisible(index: 0, shapeLayerIDs: [], layers: layers),
        "unassigned shape (no layerIDs recorded) is visible"
    )
    let dangling = UUID()
    try expect(
        !LayerVisibility.isVisible(index: 0, shapeLayerIDs: [dangling], layers: layers),
        "shape referencing a missing layer is hidden"
    )

    let visible = LayerVisibility.visibleIndices(
        count: 3,
        shapeLayerIDs: [visibleLayer.id, hiddenLayer.id, visibleLayer.id],
        layers: layers
    )
    try expect(visible == [0, 2], "visibleIndices keeps only visible-layer shapes (got \(visible))")

    // 2. Distribution by layerId.
    var layers2 = [visibleLayer, hiddenLayer]
    LayerVisibility.distribute(
        [makePath(visibleLayer.id), makePath(hiddenLayer.id), makePath(visibleLayer.id)],
        into: &layers2
    )
    try expect(layers2[0].vectors.count == 2, "visible layer holds its 2 paths (\(layers2[0].vectors.count))")
    try expect(layers2[1].vectors.count == 1, "hidden layer holds its 1 path")
    try expect(
        layers2[0].vectors.allSatisfy { $0.layerId == visibleLayer.id },
        "no cross-layer leakage into the visible layer"
    )
    try expect(
        layers2[1].vectors.allSatisfy { $0.layerId == hiddenLayer.id },
        "no cross-layer leakage into the hidden layer"
    )

    // Stale vectors are cleared on re-distribute.
    LayerVisibility.distribute([makePath(visibleLayer.id)], into: &layers2)
    try expect(layers2[1].vectors.isEmpty, "re-distribute clears the hidden layer's stale vectors")

    // 3. Round-trip: a job with two layers (one hidden) filters after load.
    var sheet = Sheet(name: "Stock")
    sheet.addLayer(visibleLayer)
    sheet.addLayer(hiddenLayer)
    var persisted = sheet
    LayerVisibility.distribute(
        [makePath(visibleLayer.id), makePath(hiddenLayer.id)],
        into: &persisted.layers
    )
    persisted.layers[1].isVisible = false

    var job = Job(name: "Visibility Job")
    job.addSheet(persisted)

    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1101h-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let packageURL = temp.appendingPathComponent("visibility.shoppilot")
    try DocumentSaver().save(ShopPilotPackagePayload(job: job), to: packageURL)
    let loaded = try DocumentLoader().loadPayload(from: packageURL)
    guard let loadedSheet = loaded.job.sheets.first else {
        throw VerifyError.failed("no sheet after round-trip")
    }
    try expect(loadedSheet.layers.count == 2, "two layers persisted")
    try expect(loadedSheet.layers[1].isVisible == false, "hidden flag persisted")

    // Reconstruct the session's parallel arrays the way AppSession does:
    // flatten per owning layer, tagging each shape with the owning layer id.
    var shapeLayerIDs: [UUID] = []
    for layer in loadedSheet.layers {
        for _ in layer.vectors { shapeLayerIDs.append(layer.id) }
    }
    let flatCount = loadedSheet.layers.reduce(0) { $0 + $1.vectors.count }
    let shown = LayerVisibility.visibleIndices(
        count: flatCount,
        shapeLayerIDs: shapeLayerIDs,
        layers: loadedSheet.layers
    )
    try expect(
        shown.count == 1,
        "only the visible layer's vector shows after round-trip (got \(shown.count))"
    )

    print("SPK-1101h verification: PASS")
    print("  isVisible/visibleIndices semantics OK (visible/hidden/unassigned/dangling)")
    print("  distribute() keeps per-layer vectors isolated and clears stale ones")
    print("  hidden layer's vectors stay hidden across .shoppilot round-trip")
}

do {
    try main()
} catch {
    fputs("SPK-1101h verification: FAIL — \(error)\n", stderr)
    exit(1)
}
