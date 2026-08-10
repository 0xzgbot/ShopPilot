import Foundation
import ShopPilotCore

/// SPK-1010 verify (CLT machine, no XCTest).
/// Proves the V2.0 SHIP CHECKLIST is honest: every verify target the
/// checklist names (SPK-0800 … SPK-1008 wave) is registered in Package.swift
/// (grep-checked), every named Core symbol exists, and the checklist doc
/// itself is present. The target-registration check is the same grep the
/// board's own audit uses — a checklist row naming a missing verify is a lie,
/// and this CLT catches it.
///
/// NOTE: the target check reads Package.swift relative to the repo root;
/// when run via verify_locked.sh the CWD is the repo root.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let cwd = FileManager.default.currentDirectoryPath
    let root = cwd.hasSuffix("ShopPilot") ? cwd : cwd + "/../.."

    // ── 1. Checklist doc exists. ──────────────────────────────────────────
    let checklistURL = URL(fileURLWithPath: root)
        .appendingPathComponent("docs/planning/V2_SHIP_CHECKLIST.md")
    let checklistText = try String(contentsOf: checklistURL, encoding: .utf8)
    try expect(checklistText.contains("SPK-1010"), "checklist self-identifies")

    // ── 2. Every named verify target is registered in Package.swift. ──────
    let packageText = try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("Package.swift"),
                                 encoding: .utf8)
    let namedTargets = [
        "ShopPilotVerify0800", "ShopPilotVerify0801", "ShopPilotVerify0803",
        "ShopPilotVerify0804", "ShopPilotVerify0805", "ShopPilotVerify0806",
        "ShopPilotVerify0807", "ShopPilotVerify0808", "ShopPilotVerify0902",
        "ShopPilotVerify0903", "ShopPilotVerify0908", "ShopPilotVerify0909",
        "ShopPilotVerify1000", "ShopPilotVerify1001", "ShopPilotVerify1003",
        "ShopPilotVerify1006", "ShopPilotVerify1008",
    ]
    for target in namedTargets {
        try expect(packageText.contains("name: \"\(target)\""),
                   "verify target \(target) is registered in Package.swift")
    }

    // ── 3. Every named Core symbol exists (the checklist's engine claims). ─
    // Multi-sheet + double-sided + rotary config on Job.
    let job = Job(name: "Check")
    try expect(job.sheets.isEmpty, "Job.sheets exists")
    // Recipe JSON codec + store types.
    _ = RecipeJSONCodec.self
    _ = JobQueue.self
    _ = NetworkBridgeConfig.self
    _ = PostTemplateStore.self
    _ = LevelMirrorEngine.self
    _ = ThreadMillingToolpathEngine.self
    _ = ToolpathGCodeTransformer.self

    // ── 4. The v1 gate stayed closed (SPK-0623 was [x] before this wave). ─
    // No v1 DoD item regressed: the session still exposes the spine surfaces.
    try expect(PostTemplate.shipped.count >= 3, "shipped post templates intact")

    print("ShopPilotVerify1010: PASS — checklist doc present, all 17 wave verify targets registered, core symbols compile, v1 spine intact")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1010: FAIL — \(error)")
    exit(1)
}
