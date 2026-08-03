import Foundation
import ShopPilotCore

/// SPK-1104c verify without XCTest (CLT-only machines).
/// Proves the PreflightGate blocks Run until every checklist item is
/// individually acknowledged, and that no auto-run / auto-ack exists on load.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let gate = PreflightGate.standard()

    // AC: Run disabled until preflight checklist items checked.
    try expect(gate.items.count == 5, "standard checklist has 5 items, got \(gate.items.count)")
    try expect(!gate.isRunAllowed, "Run must be blocked before any item is acknowledged")
    try expect(gate.acknowledgedCount == 0, "no auto-acknowledgment on load")

    // Acknowledging a subset still blocks Run.
    gate.acknowledge("work-zero")
    try expect(gate.acknowledgedCount == 1, "one item acknowledged")
    try expect(!gate.isRunAllowed, "Run stays blocked until ALL items acknowledged")

    gate.acknowledge("tool-loaded")
    gate.acknowledge("material-secured")
    gate.acknowledge("workspace-clear")
    try expect(!gate.isRunAllowed, "Run still blocked with 4/5 acknowledged")

    // All items acknowledged ⇒ Run allowed.
    gate.acknowledge("gcode-verified")
    try expect(gate.isRunAllowed, "Run allowed once every item is acknowledged")
    try expect(gate.acknowledgedCount == 5, "all 5 items acknowledged")

    // Toggling any item back off re-blocks Run (acknowledgment is per-item, not sticky).
    gate.toggle("gcode-verified")
    try expect(!gate.isRunAllowed, "Run re-blocked when an item is unchecked")
    gate.toggle("gcode-verified")
    try expect(gate.isRunAllowed, "Run re-allowed when the item is re-checked")

    // Duplicate acknowledge is idempotent.
    gate.acknowledge("gcode-verified")
    try expect(gate.acknowledgedCount == 5, "re-acknowledge keeps count at 5")

    // Reset clears everything — fresh connection requires a fresh checklist.
    gate.reset()
    try expect(gate.acknowledgedCount == 0, "reset clears all acknowledgments")
    try expect(!gate.isRunAllowed, "Run blocked after reset")

    // A fresh gate is always blocked (no auto-run on load).
    let fresh = PreflightGate.standard()
    try expect(!fresh.isRunAllowed, "fresh gate never auto-allows Run")

    // Per-item query matches acknowledged state.
    fresh.acknowledge("work-zero")
    try expect(fresh.isAcknowledged("work-zero"), "isAcknowledged reflects state")
    try expect(!fresh.isAcknowledged("gcode-verified"), "unacknowledged item reports false")

    print("SPK-1104c verification: PASS")
    print("  Run blocked until all 5 pre-flight items individually acknowledged")
    print("  unchecking any item re-blocks Run; reset clears; fresh gate never auto-runs")
}

do {
    try main()
} catch {
    fputs("SPK-1104c verification: FAIL — \(error)\n", stderr)
    exit(1)
}
