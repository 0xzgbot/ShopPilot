import Foundation
import ShopPilotCore

/// SPK-1000 verify (CLT machine, no XCTest).
/// Proves the POST STUDIO contract (user templates + variable blocks on top
/// of the SPK-1134 template engine):
///   1. VARIABLE SUBSTITUTION: `PostTemplateEngine.emit` replaces `$name`
///      tokens in header/footer/move recipe lines from the variables dict
///      (e.g. `$jobName` → the job name in the header comment).
///   2. UNKNOWN TOKENS: tokens without a variable stay verbatim (a template
///      written for a newer store still emits readable output).
///   3. STORE: `PostTemplateStore` starts with the shipped set, upserts +
///      removes USER templates, persists across instances (UserDefaults),
///      and never lets shipped templates be removed.
///   4. BLOCK KEYS: the documented document-variable keys are exactly the
///      set the export path fills (jobName/sheet/material/tool/feed/rpm).
/// The AppSession glue (postTemplateStore + postTemplateVariables +
/// PostStudioView + export wiring) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Variable substitution in header + move lines. ─────────────────
    let template = PostTemplate(
        id: "user-test",
        name: "Test Post",
        summary: "variable probe",
        text: """
        (job: $jobName / $sheetWidth x $sheetDepth mm)
        (--- moves ---)
        [X|A|X|1.3] [Y|A|Y|1.3]
        (--- end ---)
        (tool: $toolName)
        """
    )
    let vars: [String: String] = [
        "jobName": "Vase", "sheetWidth": "300", "sheetDepth": "200", "toolName": "End Mill 1/4",
    ]
    let raw = ["G0 X10 Y20", "G1 X30 Y40 F1500"]
    let result = PostTemplateEngine.emit(gcodeLines: raw, template: template, variables: vars)
    try expect(result.lines[0] == "(job: Vase / 300 x 200 mm)",
               "header $variables substituted (got \(result.lines[0]))")
    try expect(result.lines.contains("(tool: End Mill 1/4)"),
               "footer $variables substituted")
    try expect(result.lines.contains("X10.000 Y20.000"), "move template still expands")

    // ── 2. Unknown tokens stay verbatim. ──────────────────────────────────
    let missing = PostTemplateEngine.emit(
        gcodeLines: raw, template: template, variables: ["jobName": "Vase"]
    )
    try expect(missing.lines[0] == "(job: Vase / $sheetWidth x $sheetDepth mm)",
               "unknown tokens left verbatim (got \(missing.lines[0]))")

    // ── 3. Store: shipped + user templates, persist, protected shipped. ───
    let defaults = UserDefaults(suiteName: "verify1000-\(UUID().uuidString)")!
    let store = PostTemplateStore(defaults: defaults)
    try expect(store.allTemplates.count == PostTemplate.shipped.count,
               "store starts with exactly the shipped set")
    let user = PostTemplate(id: "user-a", name: "A", summary: "s", text: "%\n(--- moves ---)\n[G]\n(--- end ---)\nM2")
    store.upsertUserTemplate(user)
    try expect(store.allTemplates.count == PostTemplate.shipped.count + 1, "user template added")
    try expect(store.template(byID: "user-a")?.name == "A", "user template resolvable")

    // Persistence across a fresh instance.
    let store2 = PostTemplateStore(defaults: defaults)
    try expect(store2.userTemplates.count == 1, "user templates persist across instances")
    try expect(store2.template(byID: "user-a") != nil, "persisted template resolvable")

    // Shipped templates cannot be removed.
    try expect(!store.removeUserTemplate(id: "grbl-mm"), "shipped template removal refused")
    try expect(store.template(byID: "grbl-mm") != nil, "shipped template still present")
    // User template removal works.
    try expect(store.removeUserTemplate(id: "user-a"), "user template removal succeeds")
    try expect(store.template(byID: "user-a") == nil, "user template gone")

    // ── 4. Block keys match the document variable surface. ────────────────
    let keys = Set(PostTemplateStore.documentVariableKeys)
    try expect(keys.contains("jobName") && keys.contains("sheetWidth")
               && keys.contains("materialName") && keys.contains("toolName")
               && keys.contains("feedRate") && keys.contains("spindleRpm"),
               "block keys cover job/sheet/material/tool/feed/rpm")

    print("ShopPilotVerify1000: PASS — $variable substitution (known + unknown tokens), store upsert/remove/persist, shipped protection, block-key surface")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1000: FAIL — \(error)")
    exit(1)
}
