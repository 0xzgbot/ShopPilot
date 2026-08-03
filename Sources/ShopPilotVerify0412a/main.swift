import Foundation
import ShopPilotCore

/// SPK-0412a verify without XCTest (CLT-only machines).
/// Proves the PreflightChecklist model REQUIRES spindle and work-zero items:
/// the checklist is incomplete (Run gated) until both are acknowledged, and
/// required items can never be bypassed.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let gate = PreflightGate.standard()

    // AC: the standard checklist must contain spindle AND work-zero items.
    let itemIDs = Set(gate.items.map(\.id))
    try expect(itemIDs.contains("spindle"), "standard checklist must contain a 'spindle' item")
    try expect(itemIDs.contains("work-zero"), "standard checklist must contain a 'work-zero' item")

    // Both are mandatory safety items (required = true), never optional.
    for id in ["spindle", "work-zero"] {
        guard let item = gate.items.first(where: { $0.id == id }) else {
            throw VerifyError.failed("missing required item \(id)")
        }
        try expect(item.required, "'\(id)' must be a required item, got required=\(item.required)")
    }
    try expect(gate.requiredIDs.contains("spindle"), "requiredIDs includes spindle")
    try expect(gate.requiredIDs.contains("work-zero"), "requiredIDs includes work-zero")

    // Checklist is incomplete until spindle+workzero acknowledged.
    try expect(!gate.isChecklistComplete, "checklist incomplete before any acknowledgment")
    try expect(!gate.isRunAllowed, "Run gated before any acknowledgment")

    // Acknowledging everything EXCEPT spindle still leaves the checklist incomplete.
    for id in gate.items.map(\.id) where id != "spindle" {
        gate.acknowledge(id)
    }
    try expect(!gate.isChecklistComplete, "checklist incomplete until spindle acknowledged")
    try expect(gate.missingRequiredIDs.contains("spindle"), "spindle reported missing")
    try expect(!gate.isRunAllowed, "Run stays gated until spindle acknowledged")

    // Now acknowledge spindle, but toggle work-zero off — still incomplete.
    gate.acknowledge("spindle")
    gate.toggle("work-zero")
    try expect(!gate.isChecklistComplete, "checklist incomplete until work-zero acknowledged")
    try expect(gate.missingRequiredIDs.contains("work-zero"), "work-zero reported missing")
    try expect(!gate.isRunAllowed, "Run stays gated until work-zero acknowledged")

    // Re-acknowledge work-zero → every item checked → Run allowed.
    gate.acknowledge("work-zero")
    try expect(gate.isChecklistComplete, "checklist complete once all required items acknowledged")
    try expect(gate.missingRequiredIDs.isEmpty, "no required item missing")
    try expect(gate.isRunAllowed, "Run allowed once every item acknowledged")

    // Toggling spindle back off re-blocks Run (required items are per-item, not sticky).
    gate.toggle("spindle")
    try expect(!gate.isRunAllowed, "unchecking spindle re-blocks Run")
    try expect(!gate.isChecklistComplete, "unchecking spindle makes checklist incomplete again")
    gate.toggle("spindle")
    try expect(gate.isRunAllowed, "re-checking spindle re-allows Run")

    // reset() clears required items too — fresh checklist re-gates Run.
    gate.reset()
    try expect(!gate.isRunAllowed, "Run gated after reset")
    try expect(gate.missingRequiredIDs == gate.requiredIDs, "reset leaves all required items missing")

    // A custom gate that declares only spindle+workzero required still gates on them.
    let custom = PreflightGate(items: [
        PreflightChecklistItem(id: "spindle", title: "Spindle verified", detail: "Spindle safe"),
        PreflightChecklistItem(id: "work-zero", title: "Work zero set", detail: "WCS correct"),
        PreflightChecklistItem(id: "optional-note", title: "Optional note", detail: "Nice to have", required: false),
    ])
    try expect(custom.isChecklistComplete == false, "custom gate starts incomplete")
    custom.acknowledge("optional-note")
    try expect(!custom.isChecklistComplete, "optional items alone do not complete the checklist")
    custom.acknowledge("spindle")
    custom.acknowledge("work-zero")
    try expect(custom.isChecklistComplete, "required spindle+workzero acknowledged ⇒ checklist complete")
    try expect(custom.isRunAllowed, "custom gate allows Run once required items acknowledged")
    custom.toggle("work-zero")
    try expect(!custom.isRunAllowed, "custom gate re-blocks Run when work-zero unchecked")

    print("SPK-0412a verification: PASS")
    print("  standard checklist requires spindle + work-zero items (required=true)")
    print("  checklist incomplete / Run gated until both acknowledged; unchecking re-gates")
}

do {
    try main()
} catch {
    fputs("SPK-0412a verification: FAIL — \(error)\n", stderr)
    exit(1)
}
