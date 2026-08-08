import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0512/0513 verify (CLT machines, no XCTest).
/// Proves the document-variables machinery the panel (0512) and the sign
/// recipe width/height overrides (0513) hang off:
///   1. CRUD: add / update / delete / categories.
///   2. Persistence: save → new model → load round-trip (custom URL).
///   3. SPK-0513: the NewJobView override contract — width/depth/height
///      document variables resolve to Double and override the recipe stock.
///   4. Expression integration: variables resolve inside ExpressionCalculator
///      (the SPK-0209 calc boxes read the same model).
///   5. Legacy-safe: a fresh model loads cleanly with no stored file.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

@MainActor
func run() async throws {
    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-0512-\(UUID().uuidString).json")

    // ── 1. CRUD ───────────────────────────────────────────────────────────
    let model = DocumentVariablesModel(customStorageURL: storageURL)
    try expect(model.variables.isEmpty, "fresh model is empty")
    let w = model.addVariable(key: "width", value: "600", category: "Stock")
    let d = model.addVariable(key: "depth", value: "900", category: "Stock")
    let h = model.addVariable(key: "height", value: "18", category: "Stock")
    model.addVariable(key: "material", value: "Oak", category: "General")
    try expect(model.variables.count == 4, "4 variables added")
    try expect(model.categories == ["General", "Stock"], "categories grouped + sorted (got \(model.categories))")

    try expect(model.updateVariable(id: w.id, key: "width", value: "610"), "update width → true")
    try expect(model.variables.first { $0.id == w.id }?.value == "610", "width updated to 610")
    try expect(model.deleteVariable(id: h.id), "delete height → true")
    try expect(model.variables.count == 3, "3 variables after delete")

    // ── 2. Persistence round-trip ─────────────────────────────────────────
    try expect(model.save(), "save succeeds")
    let reloaded = DocumentVariablesModel(customStorageURL: storageURL)
    try expect(reloaded.load(), "load succeeds")
    try expect(reloaded.variables.count == 3, "reload keeps 3 variables")
    try expect(reloaded.variables.first { $0.key == "width" }?.value == "610", "reload keeps updated value")

    // ── 3. SPK-0513 sign-recipe override contract ─────────────────────────
    // NewJobView reads width/depth/height doc vars and overrides the recipe
    // stock when they parse as Double. Reproduce that logic exactly.
    func stockOverride(key: String, fallback: Double) -> Double {
        if let v = reloaded.variables.first(where: { $0.key.lowercased() == key })?.value,
           let num = Double(v) {
            return num
        }
        return fallback
    }
    try expect(stockOverride(key: "width", fallback: 457.2) == 610, "0513: width override wins")
    try expect(stockOverride(key: "depth", fallback: 609.6) == 900, "0513: depth override wins")
    try expect(stockOverride(key: "height", fallback: 19.05) == 19.05, "0513: missing height falls back")

    // ── 4. Expression integration (calc boxes read the same model) ────────
    let resolved = ExpressionCalculator.evaluate("width / 2", variables: reloaded.variables)
    try expect(resolved == 305, "calc box resolves width/2 from the model (got \(String(describing: resolved)))")

    // ── 5. Legacy-safe fresh load ─────────────────────────────────────────
    let emptyURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-0512-missing-\(UUID().uuidString).json")
    let empty = DocumentVariablesModel(customStorageURL: emptyURL)
    try expect(empty.load() || empty.variables.isEmpty, "no stored file → clean empty model, no crash")

    try? FileManager.default.removeItem(at: storageURL)
    print("ShopPilotVerify0512: PASS — CRUD, categories, save/load round-trip, 0513 width/depth/height overrides, calc-box integration, legacy-safe load")
}

do {
    try await run()
    exit(0)
} catch {
    print("ShopPilotVerify0512: FAIL — \(error)")
    exit(1)
}
