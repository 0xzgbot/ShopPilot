import Foundation
import ShopPilotCore

/// SPK-1311 verify (CLT machine, no XCTest).
/// Proves the ToolpathTemplateLibrary contract on top of ToolpathTemplateManager:
///   1. EMPTY: a fresh library has 0 templates; count(for: .profile) == 0.
///   2. SAVE: valid params JSON + type + name → saved, templates.count == 1,
///      count(for: .profile) == 1, saved template present in the library.
///   3. REJECT: empty name → nil; non-JSON params → nil; duplicate name → nil
///      (count stays 1; nothing persisted).
///   4. APPLY ROUND-TRIP: apply(id:) returns the exact paramsJson string.
///   5. DELETE: delete(id:) → count 0; apply(id:) after delete → nil.
///   6. STRATEGY MATCH: lowercase-contains on displayName, positive + negative.
///   7. PERSISTENCE: a library built on the SAME manager instance sees
///      templates saved through it; a fresh manager on the same file reloads
///      them from disk via loadTemplates().
/// Uses a temp-file manager so the real Documents toolpath_templates.json is
/// never touched.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1311-\(UUID().uuidString).json")
    let manager = ToolpathTemplateManager(fileURL: fileURL)
    let library = ToolpathTemplateLibrary(manager: manager)
    let paramsJson = "{ \"cutDepth\": 5 }"

    // ── 1. Empty library. ─────────────────────────────────────────────────
    try expect(library.templates.isEmpty, "fresh library starts with 0 templates")
    try expect(library.count(for: .profile) == 0, "count(for: .profile) == 0 on empty library")

    // ── 2. Save succeeds. ─────────────────────────────────────────────────
    guard let saved = library.save(name: "Sign 6mm", type: .profile, paramsJson: paramsJson) else {
        throw VerifyError.failed("save of valid template returned nil")
    }
    try expect(library.templates.count == 1, "templates.count == 1 after save (got \(library.templates.count))")
    try expect(library.count(for: .profile) == 1, "count(for: .profile) == 1 after save (got \(library.count(for: .profile)))")
    try expect(library.templates.first?.id == saved.id, "saved template is present in library")

    // ── 3. Rejections (nothing saved). ────────────────────────────────────
    try expect(library.save(name: "", type: .profile, paramsJson: paramsJson) == nil,
               "empty name rejected")
    try expect(library.save(name: "   ", type: .profile, paramsJson: paramsJson) == nil,
               "whitespace-only name rejected")
    try expect(library.save(name: "Bad JSON", type: .profile, paramsJson: "nope") == nil,
               "non-JSON params rejected")
    try expect(library.save(name: "Sign 6mm", type: .profile, paramsJson: paramsJson) == nil,
               "duplicate name rejected")
    try expect(library.templates.count == 1, "count stays 1 after all rejected saves")

    // ── 4. Apply round-trip. ──────────────────────────────────────────────
    try expect(library.apply(id: saved.id) == paramsJson,
               "apply returns exact paramsJson (got \(library.apply(id: saved.id) ?? "nil"))")

    // ── 5. Delete. ────────────────────────────────────────────────────────
    library.delete(id: saved.id)
    try expect(library.templates.isEmpty, "delete removes the template (count 0)")
    try expect(library.count(for: .profile) == 0, "count(for: .profile) == 0 after delete")
    try expect(library.apply(id: saved.id) == nil, "apply after delete returns nil")

    // ── 6. Strategy matching. ─────────────────────────────────────────────
    try expect(ToolpathTemplateLibrary.strategyMatches("Profile Outer", .profile),
               "'Profile Outer' matches .profile")
    try expect(!ToolpathTemplateLibrary.strategyMatches("Pocket Inner", .profile),
               "'Pocket Inner' does not match .profile")
    try expect(ToolpathTemplateLibrary.strategyMatches("V-Carve Text", .vcarve),
               "'V-Carve Text' matches .vcarve")
    try expect(!ToolpathTemplateLibrary.strategyMatches("Quick Engrave", .drill),
               "'Quick Engrave' does not match .drill")

    // ── 7. Persistence. ───────────────────────────────────────────────────
    guard let persisted = library.save(name: "Sign 6mm", type: .profile, paramsJson: paramsJson) else {
        throw VerifyError.failed("re-save for persistence check returned nil")
    }
    let library2 = ToolpathTemplateLibrary(manager: manager)
    try expect(library2.templates.count == 1, "library on same manager instance sees saved template")
    try expect(library2.apply(id: persisted.id) == paramsJson, "same-manager library applies persisted template")

    let freshManager = ToolpathTemplateManager(fileURL: fileURL)
    let onDisk = freshManager.loadTemplates()
    try expect(onDisk.count == 1, "fresh manager reloads 1 template from disk (got \(onDisk.count))")
    try expect(onDisk.first?.paramsJson == paramsJson, "disk template carries exact paramsJson")
    try expect(onDisk.first?.toolpathType == .profile, "disk template carries .profile type")

    try? FileManager.default.removeItem(at: fileURL)

    print("ShopPilotVerify1311: PASS — empty library, validated save/reject, apply round-trip, delete, strategyMatches, same-manager + disk persistence")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1311: FAIL — \(error)")
    exit(1)
}
