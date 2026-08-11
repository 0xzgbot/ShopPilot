import Foundation
import ShopPilotCore

/// SPK-1317 verify (CLT machine, no XCTest).
/// Proves the SHORTCUT REGISTRY contract:
///   1. CATALOG: 11 commands with stable ids (file.new … stage.machine).
///   2. DEFAULTS: fresh registry has every binding at its shipped default
///      (isDefault true, key matches defaultKey).
///   3. OVERRIDE: setOverride persists a remap; binding(for:) returns it;
///      unknown id / empty key are rejected (false, no change).
///   4. RESET: reset(id) and resetAll() restore defaults.
///   5. PERSISTENCE: a registry created over the SAME UserDefaults (suite)
///      sees the overrides — the Codable round-trip through the store.
///   6. CATALOG STABILITY: ids are unique (menu lookup never ambiguous).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1 + 2. Catalog + defaults. ────────────────────────────────────────
    let suite = "spk-verify-1317-\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    defer { store.removePersistentDomain(forName: suite) }

    let registry = ShortcutRegistry(userDefaults: store)
    try expect(registry.bindings.count == 11, "catalog has 11 commands (got \(registry.bindings.count))")
    for binding in registry.bindings {
        try expect(binding.isDefault, "fresh registry: \(binding.id) at default")
    }
    try expect(registry.binding(for: "stage.cut")?.key == "4", "stage.cut default key 4")

    // ── 6. Unique ids. ────────────────────────────────────────────────────
    let ids = Set(registry.bindings.map(\.id))
    try expect(ids.count == registry.bindings.count, "command ids are unique")

    // ── 3. Override. ──────────────────────────────────────────────────────
    try expect(registry.setOverride(id: "stage.cut", key: "c", modifiers: ["command", "shift"]),
               "override accepted")
    try expect(registry.binding(for: "stage.cut")?.key == "c"
               && registry.binding(for: "stage.cut")?.modifiers == ["command", "shift"],
               "override visible via binding(for:)")
    try expect(!registry.setOverride(id: "nope", key: "x", modifiers: []),
               "unknown id rejected")
    try expect(!registry.setOverride(id: "stage.cut", key: "", modifiers: []),
               "empty key rejected")
    try expect(registry.binding(for: "stage.cut")?.key == "c",
               "rejected override left the binding untouched")

    // ── 4. Reset. ─────────────────────────────────────────────────────────
    registry.reset("stage.cut")
    try expect(registry.binding(for: "stage.cut")?.isDefault == true, "reset(id) restores default")
    _ = registry.setOverride(id: "stage.design", key: "d", modifiers: ["command"])
    _ = registry.setOverride(id: "stage.model", key: "m", modifiers: ["command"])
    registry.resetAll()
    for binding in registry.bindings {
        try expect(binding.isDefault, "resetAll restores every default")
    }

    // ── 5. Persistence across instances. ──────────────────────────────────
    _ = registry.setOverride(id: "palette", key: "p", modifiers: ["command"])
    let reloaded = ShortcutRegistry(userDefaults: store)
    try expect(reloaded.binding(for: "palette")?.key == "p",
               "second instance sees the persisted override")
    try expect(reloaded.binding(for: "stage.machine")?.key == "6",
               "non-overridden commands stay at defaults after reload")

    print("ShopPilotVerify1317: PASS — 11-command catalog, defaults, override+reject, reset/resetAll, cross-instance persistence, unique ids")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1317: FAIL — \(error)")
    exit(1)
}
