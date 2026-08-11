import Foundation
import ShopPilotCore

/// SPK-1315 verify (CLT, no XCTest).
/// Proves the bundled manufacturer tool catalog contract:
///   1. CATALOG: presets() >= 10 REAL part numbers, >= 3 Amana + >= 3 Whiteside.
///   2. PRESET SANITY: every preset has positive geometry (diameter,
///      cuttingLength, shankDiameter), totalLength > cuttingLength,
///      flutes >= 1, non-empty partNumber/name, and a real ToolType.
///   3. makeTool: materializes every field — name carries the manufacturer
///      prefix and type/geometry/flutes match the preset exactly.
///   4. importAll: adds every preset to a fresh database, skips all on a
///      second no-duplicates import, and re-adds all with duplicatesAllowed.
/// The app-side "Import manufacturer catalog" menu action is compile-checked
/// by the app build; this CLT proves the engine contract.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Catalog size + manufacturer coverage. ──────────────────────────
    let presets = ManufacturerToolCatalog.presets()
    try expect(presets.count >= 10, "presets() >= 10 real part numbers (got \(presets.count))")

    let amana = presets.filter { $0.manufacturer == "Amana" }
    let whiteside = presets.filter { $0.manufacturer == "Whiteside" }
    try expect(amana.count >= 3, "at least 3 Amana presets (got \(amana.count))")
    try expect(whiteside.count >= 3, "at least 3 Whiteside presets (got \(whiteside.count))")

    // ── 2. Preset sanity, every entry. ────────────────────────────────────
    for (index, preset) in presets.enumerated() {
        try expect(!preset.manufacturer.isEmpty, "preset[\(index)] manufacturer non-empty")
        try expect(!preset.partNumber.isEmpty, "preset[\(index)] partNumber non-empty")
        try expect(!preset.name.isEmpty, "preset[\(index)] name non-empty")
        try expect(preset.diameter > 0, "preset[\(index)] diameter > 0 (got \(preset.diameter))")
        try expect(preset.cuttingLength > 0, "preset[\(index)] cuttingLength > 0 (got \(preset.cuttingLength))")
        try expect(preset.totalLength > preset.cuttingLength,
                   "preset[\(index)] totalLength \(preset.totalLength) > cuttingLength \(preset.cuttingLength)")
        try expect(preset.shankDiameter > 0, "preset[\(index)] shankDiameter > 0 (got \(preset.shankDiameter))")
        try expect(preset.flutes >= 1, "preset[\(index)] flutes >= 1 (got \(preset.flutes))")
        try expect(ToolType.allCases.contains(preset.type), "preset[\(index)] type is a real ToolType")
    }

    // ── 3. makeTool field mapping. ────────────────────────────────────────
    for preset in presets {
        let tool = ManufacturerToolCatalog.makeTool(preset)
        try expect(tool.name.hasPrefix(preset.manufacturer),
                   "tool name '\(tool.name)' carries manufacturer prefix '\(preset.manufacturer)'")
        try expect(tool.name.contains(preset.partNumber), "tool name contains part number \(preset.partNumber)")
        try expect(tool.type == preset.type, "\(preset.partNumber): type maps through")
        try expect(tool.diameter == preset.diameter, "\(preset.partNumber): diameter maps through")
        try expect(tool.cuttingLength == preset.cuttingLength, "\(preset.partNumber): cuttingLength maps through")
        try expect(tool.totalLength == preset.totalLength, "\(preset.partNumber): totalLength maps through")
        try expect(tool.shankDiameter == preset.shankDiameter, "\(preset.partNumber): shankDiameter maps through")
        try expect(tool.flutes == preset.flutes, "\(preset.partNumber): flutes maps through")
        try expect(tool.material == preset.material, "\(preset.partNumber): material maps through")
    }

    // ── 4. importAll semantics. ───────────────────────────────────────────
    // Isolate from any persisted tool database state: ToolDatabase's storage
    // key constant is internal, so clear the literal key ("shopPilotTools").
    UserDefaults.standard.removeObject(forKey: "shopPilotTools")
    let db = ToolDatabase()  // fresh run → seeded defaults, no persisted tools
    let baseline = db.tools.count

    let first = ManufacturerToolCatalog.importAll(into: db)
    try expect(first == presets.count, "first import adds every preset (got \(first), expected \(presets.count))")

    let second = ManufacturerToolCatalog.importAll(into: db)
    try expect(second == 0, "second import adds nothing — name collisions skipped (got \(second))")

    let third = ManufacturerToolCatalog.importAll(into: db, duplicatesAllowed: true)
    try expect(third == presets.count, "duplicatesAllowed re-import adds every preset again (got \(third))")
    try expect(db.tools.count == baseline + 2 * presets.count,
               "db holds baseline + 2× presets (got \(db.tools.count), expected \(baseline + 2 * presets.count))")

    print("ShopPilotVerify1315: PASS — \(presets.count) real manufacturer presets (Amana \(amana.count), Whiteside \(whiteside.count)), makeTool field mapping, importAll first-add/dup-skip/duplicatesAllowed semantics")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1315: FAIL — \(error)")
    exit(1)
}
