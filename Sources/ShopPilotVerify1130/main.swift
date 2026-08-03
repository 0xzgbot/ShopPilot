import Foundation
import ShopPilotCore

/// SPK-1130 verify (CLT machines, no XCTest).
/// Covers: stock W/D/H mutation, material selection, package round-trip
/// persistence of dimensions + material, and MaterialStore last-used
/// persistence (UserDefaults, isolated suite).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 1. Material database defaults are populated on first access.
    MaterialDatabase.preloadDefaults()
    let db = MaterialDatabase.shared
    try expect(db.allMaterials.count >= 8, "default materials registered (\(db.allMaterials.count))")
    guard let mdf = db.lookup(byName: "MDF") else {
        throw VerifyError.failed("MDF preset missing")
    }
    try expect(mdf.category == .composite, "MDF category")
    try expect(db.lookup(byName: "Pine") != nil, "Pine preset present")
    try expect(db.lookup(byName: "Nope") == nil, "unknown material lookup is nil")

    // 2. Sheet stock W/D/H mutation + material assignment.
    var sheet = Sheet(name: "Stock", width: 600, depth: 400, height: 25)
    sheet.width = 610
    sheet.depth = 305
    sheet.height = 18
    sheet.material = mdf
    try expect(sheet.width == 610 && sheet.depth == 305 && sheet.height == 18, "dimensions mutated")
    try expect(sheet.material?.name == "MDF", "material assigned")

    // 3. Package round-trip keeps W/D/H + material name.
    var job = Job(name: "Material Job")
    job.addSheet(sheet)
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1130-verify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let packageURL = temp.appendingPathComponent("material.shoppilot")
    try DocumentSaver().save(ShopPilotPackagePayload(job: job), to: packageURL)
    let loaded = try DocumentLoader().loadPayload(from: packageURL)
    guard let loadedSheet = loaded.job.sheets.first else {
        throw VerifyError.failed("no sheet after round-trip")
    }
    try expect(loadedSheet.width == 610, "width persisted (\(loadedSheet.width))")
    try expect(loadedSheet.depth == 305, "depth persisted (\(loadedSheet.depth))")
    try expect(loadedSheet.height == 18, "height persisted (\(loadedSheet.height))")
    try expect(loadedSheet.material?.name == "MDF", "material persisted (\(loadedSheet.material?.name ?? "nil"))")

    // 4. MaterialStore last-used persistence in an isolated UserDefaults suite.
    let suite = "spk1130-verify-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        throw VerifyError.failed("cannot create UserDefaults suite")
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = MaterialStore(defaults: defaults)
    try expect(store.lastUsedMaterialName == nil, "no last-used initially")

    store.saveLastUsed(mdf)
    try expect(store.lastUsedMaterialName == "MDF", "last-used saved")

    // A fresh store reading the same defaults sees the persisted selection.
    let store2 = MaterialStore(defaults: defaults)
    try expect(store2.lastUsedMaterialName == "MDF", "last-used read back")

    // Default material resolves from the persisted selection.
    let defaulted = store2.defaultMaterial()
    try expect(defaulted?.name == "MDF", "default material resolves to last-used")

    // Clearing persists too, and the fallback default is still MDF.
    store2.saveLastUsed(nil)
    try expect(store2.lastUsedMaterialName == nil, "last-used cleared")
    try expect(store2.defaultMaterial()?.name == "MDF", "fallback default is MDF")

    print("SPK-1130 verification: PASS")
    print("  stock W/D/H mutation + package round-trip OK")
    print("  material selection persisted in package + last-used store OK")
}

do {
    try main()
} catch {
    fputs("SPK-1130 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
