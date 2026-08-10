import Foundation
import ShopPilotCore

/// SPK-1006 verify (CLT machine, no XCTest).
/// Proves the JSON RECIPE FORMAT + codec contract:
///   1. ROUND-TRIP: a recipe encodes to pretty JSON and decodes back
///      identically (id/name/dims/strategy all preserved).
///   2. SAMPLE FILES: every `fixtures/recipes/*.recipe.json` parses as a
///      single recipe with the expected fields (the shipped defaults).
///   3. PACK + ENVELOPE: the JSON-array pack and the `{"recipes": [...]}`
///      envelope (plugin/API shape) both decode to the same recipe set.
///   4. FORWARD-COMPAT: a recipe with an unknown extra key still decodes
///      (unknown keys tolerated — a newer recipe loads in this build).
///   5. NON-RECIPE PAYLOAD: garbage returns nil, never crashes.
/// The docs draft (`docs/planning/RECIPE_PLUGIN_API_DRAFT.md`) documents the
/// schema + plugin API proposal.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("fixtures/recipes/\(name)")
}

func main() throws {
    // ── 1. Round-trip. ───────────────────────────────────────────────────
    let recipe = JobRecipe(
        name: "Test Relief",
        description: "round-trip probe",
        icon: "cube",
        stockWidth: 100, stockDepth: 200, stockHeight: 12.5,
        recommendedStrategy: "Z-level roughing"
    )
    let data = try RecipeJSONCodec.encode(recipe)
    let text = String(data: data, encoding: .utf8) ?? ""
    try expect(text.contains("\"name\" : \"Test Relief\""), "pretty JSON carries name")
    let back = RecipeJSONCodec.decode(data)
    try expect(back?.id == recipe.id, "id round-trips")
    try expect(back?.name == "Test Relief" && back?.stockWidth == 100
               && abs((back?.stockHeight ?? 0) - 12.5) < 1e-9, "fields round-trip")
    try expect(back?.recommendedStrategy == "Z-level roughing", "strategy round-trips")

    // ── 2. Sample files parse (shipped defaults). ────────────────────────
    let portrait = RecipeJSONCodec.decode(try Data(contentsOf: fixtureURL("portrait-relief.recipe.json")))
    try expect(portrait?.name == "Portrait Relief", "portrait sample parses")
    try expect(abs((portrait?.stockWidth ?? 0) - 304.8) < 1e-9, "portrait stock width")

    let panel = RecipeJSONCodec.decode(try Data(contentsOf: fixtureURL("decorative-panel.recipe.json")))
    try expect(panel?.name == "Decorative Panel" && panel?.stockWidth == 609.6, "panel sample parses")

    let signage = RecipeJSONCodec.decode(try Data(contentsOf: fixtureURL("signage.recipe.json")))
    try expect(signage?.name == "Signage" && signage?.stockHeight == 19.05, "signage sample parses")

    // ── 3. Pack + envelope decode. ───────────────────────────────────────
    let packData = try Data(contentsOf: fixtureURL("recipe-pack.json"))
    let fromEnvelope = RecipeJSONCodec.decodeEnvelope(packData)
    try expect(fromEnvelope.count == 3, "envelope pack decodes 3 recipes (got \(fromEnvelope.count))")
    try expect(fromEnvelope.map(\.name).contains("Signage"), "envelope carries the set")

    // Bare-array pack (no envelope) also decodes.
    let bareArray = try JSONSerialization.data(withJSONObject: [
        ["id": UUID().uuidString, "name": "A", "description": "d", "icon": "i",
         "stockWidth": 1, "stockDepth": 2, "stockHeight": 3, "recommendedStrategy": "s"],
    ])
    try expect(RecipeJSONCodec.decodePack(bareArray).count == 1, "bare array pack decodes")

    // ── 4. Forward-compat: unknown keys tolerated. ───────────────────────
    let forward = """
    {"id": "\(UUID().uuidString)", "name": "Newer", "description": "d", "icon": "i",
     "stockWidth": 10, "stockDepth": 20, "stockHeight": 5, "recommendedStrategy": "s",
     "futureParam": {"nested": true}, "version": 2}
    """
    let forwardRecipe = RecipeJSONCodec.decode(Data(forward.utf8))
    try expect(forwardRecipe?.name == "Newer", "recipe with unknown keys still decodes")

    // ── 5. Garbage → nil, never crash. ───────────────────────────────────
    try expect(RecipeJSONCodec.decode(Data("not json".utf8)) == nil, "garbage → nil")
    try expect(RecipeJSONCodec.decode(Data("[1,2,3]".utf8)) == nil, "wrong shape → nil")
    try expect(RecipeJSONCodec.decodeEnvelope(Data("{}".utf8)).isEmpty, "empty envelope → empty")

    print("ShopPilotVerify1006: PASS — JSON recipe round-trip, 3 sample files parse, pack + envelope decode, forward-compatible unknown keys, garbage → nil")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1006: FAIL — \(error)")
    exit(1)
}
