import Foundation
import ShopPilotCore

// SPK-1502 verify (CLT executable, no XCTest).
// Proves the new coach rules for the remaining empty stages:
//   1. ≥3 NEW ids exist: model.empty, preview.empty, setup.next,
//      machine.connected (4 added).
//   2. MATCHING: model with no vectors → model.empty; preview with no
//      toolpaths → preview.empty; setup with sheets → setup.next; machine
//      connected → machine.connected (not machine.disconnected).
//   3. PRIORITY SANITY: connected machine resolves to machine.connected,
//      disconnected machine to machine.disconnected (mutually exclusive).
//   4. REGRESSION: the 1400j action rules still resolve (design.empty →
//      try_sample, cut.empty → cut_out, machine.disconnected →
//      connect_machine).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func resolved(_ context: CoachContext) -> String? {
    CoachRuleEngine.resolve(rules: CoachRuleEngine.standardRules, context: context)?.id
}

func main() throws {
    let rules = CoachRuleEngine.standardRules

    // 1. The four new ids exist.
    for id in ["model.empty", "preview.empty", "setup.next", "machine.connected"] {
        try expect(rules.contains(where: { $0.id == id }),
                   "catalog contains \(id)")
    }

    // 2. Matching.
    try expect(resolved(CoachContext(stage: "model")) == "model.empty",
               "model + no vectors → model.empty")
    try expect(resolved(CoachContext(stage: "preview")) == "preview.empty",
               "preview + no toolpaths → preview.empty")
    try expect(resolved(CoachContext(stage: "setup", hasSheets: true)) == "setup.next",
               "setup + sheets → setup.next (next-step, not setup.empty)")
    try expect(resolved(CoachContext(stage: "machine", isConnected: true)) == "machine.connected",
               "machine connected → machine.connected (zero/home next step)")
    try expect(resolved(CoachContext(stage: "machine")) == "machine.disconnected",
               "machine disconnected → machine.disconnected")

    // 3. Mutually exclusive machine states.
    let connected = CoachRuleEngine.resolve(rules: rules, context: CoachContext(stage: "machine", isConnected: true))
    let disconnected = CoachRuleEngine.resolve(rules: rules, context: CoachContext(stage: "machine"))
    try expect(connected?.id == "machine.connected" && disconnected?.id == "machine.disconnected",
               "machine rules are mutually exclusive")

    // 4. 1400j action rules still resolve.
    try expect(resolved(CoachContext(stage: "design")) == "design.empty",
               "design.empty still wins with no vectors")
    try expect(resolved(CoachContext(stage: "cut", hasVectors: true)) == "cut.empty",
               "cut.empty still wins with vectors + no toolpaths")
    let designRule = rules.first { $0.id == "design.empty" }
    let cutRule = rules.first { $0.id == "cut.empty" }
    let connectRule = rules.first { $0.id == "machine.disconnected" }
    try expect(designRule?.actionID == "try_sample" && designRule?.actionTitle == "Try a sample",
               "design.empty action intact (try_sample)")
    try expect(cutRule?.actionID == "cut_out" && cutRule?.actionTitle == "Cut out",
               "cut.empty action intact (cut_out)")
    try expect(connectRule?.actionID == "connect_machine" && connectRule?.actionTitle == "Connect",
               "machine.disconnected action intact (connect_machine)")

    print("1502: PASS — coach remaining empty rules")
    print("  model.empty / preview.empty / setup.next / machine.connected added; 1400j actions intact")
}

do {
    try main()
} catch {
    print("1502: FAIL — \(error)")
    exit(1)
}
