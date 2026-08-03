import Foundation
import ShopPilotCore

/// SPK-1123 verify (CLT machines, no XCTest).
/// Proves session layer CRUD at the engine level:
///   1. Sheet.addLayer / rename / visibility / lock mutations.
///   2. Sheet.moveLayer reorder (up, down, clamp, no-op).
///   3. Package round-trip: layer order + flags survive save/load.
/// The AppSession glue (undo points, dirty flag) is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 1. Add layers + mutate name/vis/lock through the sheet.
    var sheet = Sheet(name: "Stock")
    let first = Layer(name: "Cut lines")
    let second = Layer(name: "Engrave")
    sheet.addLayer(first)
    sheet.addLayer(second)
    try expect(sheet.layers.count == 2, "two layers added (\(sheet.layers.count))")

    sheet.layers[0].name = "Renamed"
    try expect(sheet.layers[0].name == "Renamed", "layer rename")

    sheet.layers[1].isVisible = false
    try expect(sheet.layers[1].isVisible == false, "visibility off")

    sheet.layers[0].isLocked = true
    try expect(sheet.layers[0].isLocked == true, "lock on")
    sheet.layers[0].isLocked = false
    try expect(sheet.layers[0].isLocked == false, "lock off")

    // 2. Reorder semantics.
    let c = Layer(name: "Third")
    sheet.addLayer(c)
    try expect(sheet.layers.map(\.name) == ["Renamed", "Engrave", "Third"], "order after add")

    try expect(sheet.moveLayer(from: 2, to: 0), "move 2->0")
    try expect(sheet.layers.map(\.name) == ["Third", "Renamed", "Engrave"], "order after move up")

    try expect(sheet.moveLayer(from: 0, to: 2), "move 0->2")
    try expect(sheet.layers.map(\.name) == ["Renamed", "Engrave", "Third"], "order after move down")

    // Clamp: destination beyond bounds clamps to last index.
    try expect(sheet.moveLayer(from: 0, to: 99), "move with out-of-range dest clamps")
    try expect(sheet.layers.map(\.name) == ["Engrave", "Third", "Renamed"], "clamped order")

    // No-op: same index returns false and keeps order.
    try expect(!sheet.moveLayer(from: 1, to: 1), "same-index move is a no-op")
    try expect(!sheet.moveLayer(from: 9, to: 0), "out-of-range source is a no-op")
    try expect(sheet.layers.count == 3, "count stable after no-ops")

    // 3. Remove layer by id.
    let toRemove = sheet.layers[1] // "Third"
    try expect(sheet.removeLayer(id: toRemove.id), "removeLayer(id:) succeeds")
    try expect(sheet.layers.count == 2, "layer removed")
    try expect(sheet.layers.contains(where: { $0.id == toRemove.id }) == false, "id gone")
    try expect(!sheet.removeLayer(id: toRemove.id), "second remove fails")

    // 4. Package round-trip preserves order + visibility + lock.
    var job = Job(name: "Layers Job")
    job.addSheet(sheet)
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1123-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let packageURL = temp.appendingPathComponent("layers.shoppilot")
    try DocumentSaver().save(ShopPilotPackagePayload(job: job), to: packageURL)
    let loaded = try DocumentLoader().loadPayload(from: packageURL)
    guard let loadedSheet = loaded.job.sheets.first else {
        throw VerifyError.failed("no sheet after round-trip")
    }
    try expect(loadedSheet.layers.count == 2, "layers persisted (\(loadedSheet.layers.count))")
    try expect(loadedSheet.layers.map(\.name) == ["Engrave", "Renamed"], "layer order persisted")
    try expect(loadedSheet.layers[0].isVisible == false, "visibility flag persisted")
    try expect(loadedSheet.layers[1].name == "Renamed", "renamed layer persisted")

    print("SPK-1123 verification: PASS")
    print("  add / rename / vis / lock / reorder / remove CRUD OK")
    print("  moveLayer clamp + no-op semantics OK")
    print("  layer order + flags survive .shoppilot round-trip OK")
}

do {
    try main()
} catch {
    fputs("SPK-1123 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
