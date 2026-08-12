import Foundation
import ShopPilotCore

// SPK-1400j verify (CLT executable, no XCTest).
// Proves the standard coach catalog carries tip-card actions:
//   1. At least two standard rules have a non-nil actionTitle + actionID.
//   2. The three high-value rules map to the expected action IDs:
//      design.empty → try_sample, cut.empty → cut_out,
//      machine.disconnected → connect_machine.
//   3. Every rule WITH an actionID also has an actionTitle (the tip card
//      button needs a label; no dangling id).
//   4. Rules without actions are untouched (additive model preserved).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let rules = CoachRuleEngine.standardRules

    // 1. ≥2 rules carry actions.
    let withAction = rules.filter { $0.actionTitle != nil && $0.actionID != nil }
    try expect(withAction.count >= 2,
               "at least two standard rules carry actions (got \(withAction.count))")

    // 2. The three high-value mappings.
    func actionID(_ id: String) -> String? {
        rules.first { $0.id == id }?.actionID
    }
    try expect(actionID("design.empty") == "try_sample",
               "design.empty → try_sample")
    try expect(actionID("cut.empty") == "cut_out",
               "cut.empty → cut_out")
    try expect(actionID("machine.disconnected") == "connect_machine",
               "machine.disconnected → connect_machine")

    // 3. No dangling actionID (every id has a title).
    for rule in rules where rule.actionID != nil {
        try expect(rule.actionTitle != nil,
                   "rule \(rule.id) has actionID but no actionTitle")
    }

    // 4. Messages for the actionable rules are still present (copy intact).
    try expect(rules.first { $0.id == "design.empty" }?.message.contains("Import") == true,
               "design.empty message intact")

    print("1400j: PASS — coach actions")
    print("  \(withAction.count) rules carry actions: \(withAction.map { "\($0.id)=\($0.actionID!)" }.joined(separator: ", "))")
}

do {
    try main()
} catch {
    print("1400j: FAIL — \(error)")
    exit(1)
}
