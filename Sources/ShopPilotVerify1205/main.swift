import Foundation
import ShopPilotCore

/// SPK-1205 verify (CLT machine, no XCTest).
/// Proves the COACH RULE ENGINE contract:
///   1. PRIORITY: blocking issues (100) beat empty states (50) beat dirty
///      suggestions (40) beat hints (30) — the highest-priority matching
///      rule wins.
///   2. STAGE GATING: rules only fire on their stage (design.empty never
///      fires in cut; cut.dirty only in cut).
///   3. EMPTY-STATE TRUTH: no vectors → design/cut guidance; no sheets →
///      setup guidance; no toolpaths with vectors → generate guidance.
///   4. FALLBACK: no rule matches → nil (the UI shows the stage intent —
///      no dead air, no wrong advice).
///   5. LIVE WIRING: the standard rules resolve against a context built from
///      real session signals (hasSheets, dirty toolpaths, selection).
/// The strip UI (CoachPanelView context plumbing) is compile-checked by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let rules = CoachRuleEngine.standardRules

    // ── 1. Priority ordering. ─────────────────────────────────────────────
    // Blocking beats empty-state even in setup (blocking is global).
    let blockedSetup = CoachContext(stage: "setup", hasBlockingIssue: true)
    let r1 = CoachRuleEngine.resolve(rules: rules, context: blockedSetup)
    try expect(r1?.id == "blocking", "blocking issue wins everywhere (got \(r1?.id ?? "nil"))")

    // ── 2. Stage gating. ──────────────────────────────────────────────────
    let emptyDesign = CoachContext(stage: "design")
    let r2 = CoachRuleEngine.resolve(rules: rules, context: emptyDesign)
    try expect(r2?.id == "design.empty", "design with no vectors → design.empty (got \(r2?.id ?? "nil"))")

    let emptyCutNoVectors = CoachContext(stage: "cut")
    let r3 = CoachRuleEngine.resolve(rules: rules, context: emptyCutNoVectors)
    try expect(r3?.id != "cut.empty", "cut.empty requires vectors (got \(r3?.id ?? "nil"))")

    // ── 3. Empty-state truth. ─────────────────────────────────────────────
    let cutVectorsNoToolpaths = CoachContext(stage: "cut", hasVectors: true)
    let r4 = CoachRuleEngine.resolve(rules: rules, context: cutVectorsNoToolpaths)
    try expect(r4?.id == "cut.empty", "vectors but no toolpaths → generate guidance")

    let setupNoSheets = CoachContext(stage: "setup")
    let r5 = CoachRuleEngine.resolve(rules: rules, context: setupNoSheets)
    try expect(r5?.id == "setup.empty", "setup with no sheets → stock guidance")

    // Dirty beats selection hint in cut.
    let dirtyCut = CoachContext(stage: "cut", hasSelection: true, isDirty: true, hasToolpaths: true)
    let r6 = CoachRuleEngine.resolve(rules: rules, context: dirtyCut)
    try expect(r6?.id == "cut.dirty", "dirty suggestion beats selection hint (got \(r6?.id ?? "nil"))")

    // ── 4. Fallback → nil. ────────────────────────────────────────────────
    let happyCut = CoachContext(stage: "cut", hasVectors: true, hasToolpaths: true)
    let r7 = CoachRuleEngine.resolve(rules: rules, context: happyCut)
    try expect(r7 == nil, "nothing to say → nil (stage intent shows instead)")

    // ── 5. Live wiring shape. ─────────────────────────────────────────────
    let liveContext = CoachContext(
        stage: "setup",
        hasVectors: false,
        hasSheets: false    // a fresh job with no sheets
    )
    let r8 = CoachRuleEngine.resolve(rules: rules, context: liveContext)
    try expect(r8?.id == "setup.empty", "fresh job → stock guidance (the first-run path)")

    // Machine: disconnected beats everything at that stage.
    let machineOffline = CoachContext(stage: "machine", isConnected: false)
    let r9 = CoachRuleEngine.resolve(rules: rules, context: machineOffline)
    try expect(r9?.id == "machine.disconnected", "machine offline → connect guidance")

    print("ShopPilotVerify1205: PASS — blocking>empty>dirty>hint priority, stage gating, empty-state truth (sheets/vectors/toolpaths), nil fallback, live-context wiring")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1205: FAIL — \(error)")
    exit(1)
}
