import Foundation
import ShopPilotCore

/// SPK-1400f verify (CLT machine, no XCTest).
/// Proves the ADDITIVE coach-action model on top of the SPK-1205 engine:
///   1. DEFAULT NIL: a rule constructed with the original signature
///      (priority/id/message/matches) has `actionID == nil` and
///      `actionTitle == nil` — no call site is forced to change.
///   2. EXISTING RULES UNCHANGED: every `standardRules` entry still
///      constructs with nil action fields, and the engine still resolves the
///      same priority/stage contract (spot-checked against the 1205 rules).
///   3. RESOLVED RULE CAN CARRY AN ACTION: a rule built with an
///      actionTitle/actionID keeps both through `resolve(...)`; the engine
///      still picks the highest-priority match regardless of actions.
///   4. TITLE-OPTIONAL: an action id without a title still survives
///      resolution (the tip card falls back to a default label).
/// The card chrome (CoachPanelView icon + message + optional Button) is
/// compile-checked by the app target build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let rules = CoachRuleEngine.standardRules
    try expect(!rules.isEmpty, "standardRules is not empty")

    // ── 1. Additive default: old signature → action fields nil. ───────────
    let plain = CoachRule(priority: 30, id: "plain", message: "No action here.") { _ in true }
    try expect(plain.actionID == nil, "old-signature rule has nil actionID (got \(String(describing: plain.actionID)))")
    try expect(plain.actionTitle == nil, "old-signature rule has nil actionTitle (got \(String(describing: plain.actionTitle)))")

    // ── 2. Existing standard rules construct unchanged (nil actions). ─────
    for rule in rules {
        try expect(rule.actionID == nil, "standard rule '\(rule.id)' carries no actionID (additive model)")
        try expect(rule.actionTitle == nil, "standard rule '\(rule.id)' carries no actionTitle (additive model)")
    }

    // The engine contract from SPK-1205 still holds on the same rules.
    let blockedSetup = CoachContext(stage: "setup", hasBlockingIssue: true)
    let rBlocked = CoachRuleEngine.resolve(rules: rules, context: blockedSetup)
    try expect(rBlocked?.id == "blocking", "blocking still wins everywhere (got \(rBlocked?.id ?? "nil"))")

    let emptyDesign = CoachContext(stage: "design")
    let rDesign = CoachRuleEngine.resolve(rules: rules, context: emptyDesign)
    try expect(rDesign?.id == "design.empty", "design.empty still resolves with no vectors")

    let happyCut = CoachContext(stage: "cut", hasVectors: true, hasToolpaths: true)
    try expect(CoachRuleEngine.resolve(rules: rules, context: happyCut) == nil, "nil fallback unchanged")

    // ── 3. A resolved rule can carry an action. ───────────────────────────
    let actionRules = [
        CoachRule(priority: 40, id: "cut.dirty", message: "Some toolpaths are stale — Recalc All updates them in one click.") {
            $0.stage == "cut" && $0.isDirty && $0.hasToolpaths
        },
        CoachRule(priority: 50, id: "setup.action", message: "Start with your stock: pick a material and set sheet dimensions.",
                  actionTitle: "Add sheets", actionID: "open.sheets") {
            $0.stage == "setup" && !$0.hasSheets
        },
    ]
    let actedContext = CoachContext(stage: "setup", hasSheets: false)
    let rAction = CoachRuleEngine.resolve(rules: actionRules, context: actedContext)
    try expect(rAction?.id == "setup.action", "action rule resolves (got \(rAction?.id ?? "nil"))")
    try expect(rAction?.actionTitle == "Add sheets", "actionTitle survives resolution (got \(String(describing: rAction?.actionTitle)))")
    try expect(rAction?.actionID == "open.sheets", "actionID survives resolution (got \(String(describing: rAction?.actionID)))")

    // Priority still governs when an action is present: 100 beats the
    // action-carrying 50, and the action fields follow the winner.
    let competing = [
        CoachRule(priority: 50, id: "low.withAction", message: "lower priority with action",
                  actionTitle: "Go", actionID: "low.go") { _ in true },
        CoachRule(priority: 100, id: "high.plain", message: "higher priority, no action") { _ in true },
    ]
    let rCompeting = CoachRuleEngine.resolve(rules: competing, context: CoachContext(stage: "setup"))
    try expect(rCompeting?.id == "high.plain", "highest priority still wins over an action rule (got \(rCompeting?.id ?? "nil"))")
    try expect(rCompeting?.actionID == nil, "winner without action keeps nil actionID")

    // ── 4. Title-optional: action id alone survives resolution. ───────────
    let titleless = CoachRule(priority: 20, id: "preview.peek", message: "Hover a cut layer to highlight its path.",
                              actionTitle: nil, actionID: "preview.focus") {
        $0.stage == "preview" && $0.hasToolpaths
    }
    let rTitleless = CoachRuleEngine.resolve(rules: [titleless], context: CoachContext(stage: "preview", hasToolpaths: true))
    try expect(rTitleless?.actionID == "preview.focus", "actionID without title survives (got \(String(describing: rTitleless?.actionID)))")
    try expect(rTitleless?.actionTitle == nil, "actionTitle stays nil when not provided")

    print("1400f: PASS — coach tip card")
}

do {
    try main()
} catch {
    print("1400f: FAIL — \(error)")
    exit(1)
}
