import Foundation
import ShopPilotCore

/// SPK-0800 verify (CLT machine, no XCTest).
/// Proves the MULTI-SHEET management contract at the Core level:
///   1. JOB CRUD: addSheet/removeSheet/ensureSingleSheet semantics — the
///      document can hold several sheets and removal honors boundaries.
///   2. ACTIVE-SHEET PERSIST: `Job.activeSheetID` round-trips through Codable
///      and legacy documents (no key) decode as nil → first sheet.
///   3. PER-SHEET ISOLATION: each sheet owns its own layers/vectors — adding
///      a layer to sheet 2 never touches sheet 1, and removing one sheet
///      leaves the others' layer ids intact.
///   4. STOCK PRESETS: `StockSheetPresets.apply` targets the sheet passed in
///      (the session routes it to the ACTIVE sheet), leaving siblings alone.
/// The AppSession glue (activeSheet routing for layers/design/toolpaths,
/// SheetListView in Setup) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeSheet(_ name: String, w: Double = 600, d: Double = 400, h: Double = 25) -> Sheet {
    var sheet = Sheet(name: name, width: w, depth: d, height: h)
    sheet.layers = [Layer(name: "Layer 1")]
    return sheet
}

func main() throws {
    // ── 1. Job multi-sheet CRUD. ──────────────────────────────────────────
    var job = Job(name: "Multi")
    _ = job.ensureSingleSheet()
    try expect(job.sheets.count == 1, "ensureSingleSheet creates the first sheet")
    let firstID = job.sheets[0].id

    let second = makeSheet("Face 2", w: 800, d: 500, h: 30)
    job.addSheet(second)
    try expect(job.sheets.count == 2, "addSheet appends a second sheet")
    try expect(job.sheets[1].id == second.id, "added sheet keeps its identity")

    let third = makeSheet("Face 3")
    job.addSheet(third)
    try expect(job.sheets.count == 3, "three sheets in one document")

    // Removal honors boundaries.
    let removed = job.removeSheet(id: second.id)
    try expect(removed, "removeSheet removes an existing sheet")
    try expect(job.sheets.count == 2, "two sheets remain")
    try expect(!job.sheets.contains(where: { $0.id == second.id }), "removed sheet is gone")
    try expect(job.sheets.contains(where: { $0.id == firstID }), "sibling sheet survives removal")

    // ── 2. Active-sheet persist: round-trip + legacy-safe decode. ─────────
    job.activeSheetID = third.id
    let data = try JSONEncoder().encode(job)
    let back = try JSONDecoder().decode(Job.self, from: data)
    try expect(back.sheets.count == 2, "sheet count survives round-trip")
    try expect(back.activeSheetID == third.id, "activeSheetID survives round-trip")

    // Legacy payload without the key → nil (session falls back to sheet 0).
    // Non-optional Job fields must be present for the synthesized Codable.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","sheets":[],"createdAt":0,"updatedAt":0,"vcarvePasses":0,"vcarveTimeSeconds":0,"documentVariables":[],"drivenDimensions":[]}"#
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.activeSheetID == nil, "legacy document without activeSheetID decodes nil")
    try expect(legacy.sheets.isEmpty, "legacy empty sheets decode empty")

    // ── 3. Per-sheet isolation. ───────────────────────────────────────────
    var iso = Job(name: "Iso")
    _ = iso.ensureSingleSheet()
    let s1 = makeSheet("Sheet A")
    let s2 = makeSheet("Sheet B")
    iso.addSheet(s1)
    iso.addSheet(s2)
    let aID = iso.sheets[1].id
    let bID = iso.sheets[2].id
    // Sheet B gains its own layer; Sheet A's layer list is untouched.
    var bIndex = iso.sheets.firstIndex(where: { $0.id == bID })!
    iso.sheets[bIndex].layers.append(Layer(name: "B extra"))
    let aLayerCount = iso.sheets.first(where: { $0.id == aID })?.layers.count ?? -1
    try expect(aLayerCount == 1, "sheet A keeps exactly its own layer (got \(aLayerCount))")
    let bLayerCount = iso.sheets.first(where: { $0.id == bID })?.layers.count ?? -1
    try expect(bLayerCount == 2, "sheet B gained its own layer (got \(bLayerCount))")

    // Removing B drops only B's layers.
    _ = iso.removeSheet(id: bID)
    let aLayersAfter = iso.sheets.first(where: { $0.id == aID })?.layers.map(\.id) ?? []
    try expect(aLayersAfter.count == 1, "removing sheet B leaves sheet A's layers intact")
    try expect(!iso.sheets.contains(where: { $0.id == bID }), "sheet B removed")

    // ── 4. Stock preset applies to the passed sheet only (active-sheet
    //        routing target), siblings unchanged. ──────────────────────────
    var presetJob = Job(name: "Preset")
    _ = presetJob.ensureSingleSheet()
    presetJob.addSheet(makeSheet("Other", w: 100, d: 100, h: 5))
    let targetID = presetJob.sheets[0].id
    let siblingID = presetJob.sheets[1].id
    let preset = StockSheetPresets.all.first { $0.name.contains("4'x8'") } ?? StockSheetPresets.all[0]
    var targetIndex = presetJob.sheets.firstIndex(where: { $0.id == targetID })!
    StockSheetPresets.apply(preset, to: &presetJob.sheets[targetIndex])
    try expect(presetJob.sheets[targetIndex].width != 600 || presetJob.sheets[targetIndex].depth != 400,
               "stock preset changed the target sheet dims")
    let sibling = presetJob.sheets.first(where: { $0.id == siblingID })
    try expect(sibling?.width == 100 && sibling?.depth == 100 && sibling?.height == 5,
               "sibling sheet untouched by the preset")

    print("ShopPilotVerify0800: PASS — Job multi-sheet CRUD, activeSheetID round-trip + legacy nil, per-sheet layer isolation, active-sheet preset routing")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0800: FAIL — \(error)")
    exit(1)
}
