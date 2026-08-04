import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-FM-R016+R017 verify (CLT machine, no XCTest).
/// Proves the MACHINE-START PREFLIGHT rules (FM-09 → R016, FM-10 → R017):
///   R016 — Z0/datum contract:
///   1. `PreflightGate.standard()` carries the required "datum-z0" item
///      (operator confirms Z0 = material surface + XY datum matches the job
///      setup) — a fresh gate blocks Start until it (and the rest) are
///      acknowledged, and `reset()` re-blocks: the acknowledgment is required
///      for EVERY job start, never carried over.
///   R017 — thickness drift:
///   2. `MachineStartPreflight.thicknessDrift`: |measured − job| > 0.25mm
///      (≈0.01″) → warning issue with plain copy and a "Use Measured Value"
///      CTA; drift within tolerance → no issue; no measured value → no issue.
///   3. `MachineProfile.measuredThicknessMm` round-trips Codable and legacy
///      profiles (no key) decode as nil (unknown → no drift check).
/// The session/UI glue (R017 appended to the save-preflight alert with the
/// Use Measured Value button; datum-z0 row on the machine panel checklist) is
/// compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── R016: Z0/datum contract on the standard machine gate. ──────────────
    let gate = PreflightGate.standard()
    guard let datum = gate.items.first(where: { $0.id == "datum-z0" }) else {
        throw VerifyError.failed("standard gate carries the R016 datum-z0 item")
    }
    try expect(datum.required, "datum-z0 is a required item (blocks Start)")
    try expect(datum.title.contains("material surface"), "item confirms Z0 = material surface: \(datum.title)")
    try expect(!gate.isRunAllowed, "fresh gate blocks Start (no acknowledgments)")

    for item in gate.items { gate.acknowledge(item.id) }
    try expect(gate.isRunAllowed, "acknowledging every item arms Start")
    try expect(gate.isAcknowledged("datum-z0"), "datum-z0 was acknowledged like the rest")

    gate.reset()
    try expect(!gate.isRunAllowed, "reset re-blocks Start — the R016 contract is per-job, never carried over")

    // ── R017: thickness drift engine. ──────────────────────────────────────
    guard let drift = MachineStartPreflight.thicknessDrift(jobThicknessMm: 6.0, measuredThicknessMm: 5.0) else {
        throw VerifyError.failed("1.0mm drift must warn")
    }
    try expect(drift.ruleID == "R017", "rule id is R017")
    try expect(drift.severity == .warning, "drift is a warning (does not block)")
    try expect(drift.message.contains("differs"), "plain-English copy names the drift: \(drift.message)")
    try expect(drift.fix.isUseMeasuredValueFix, "fix CTA is Use Measured Value")

    try expect(MachineStartPreflight.thicknessDrift(jobThicknessMm: 6.0, measuredThicknessMm: 6.1) == nil,
               "0.1mm drift is within the 0.25mm tolerance — no warning")
    try expect(MachineStartPreflight.thicknessDrift(jobThicknessMm: 6.0, measuredThicknessMm: 6.26) != nil,
               "0.26mm drift crosses the tolerance — warns")
    try expect(MachineStartPreflight.thicknessDrift(jobThicknessMm: 6.0, measuredThicknessMm: nil) == nil,
               "unknown measured thickness → no drift check")

    // ── R017: profile persistence (round-trip + legacy decode). ────────────
    let profile = MachineProfile(
        name: "Caliper Rig",
        config: .simulator,
        isSimulator: true,
        measuredThicknessMm: 5.42
    )
    let back = try JSONDecoder().decode(MachineProfile.self, from: try JSONEncoder().encode(profile))
    try expect(back.measuredThicknessMm != nil && abs((back.measuredThicknessMm ?? 0) - 5.42) < 1e-9,
               "measuredThicknessMm survives the profile round-trip")

    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Legacy","config":{"baudRate":115200,"portName":"/dev/ttyUSB0","dataBits":8,"parity":"none","stopBits":"one"},"isSimulator":false,"machineType":"grbl","units":"millimeter","createdAt":0,"updatedAt":0}
    """
    let legacy = try JSONDecoder().decode(MachineProfile.self, from: Data(legacyJSON.utf8))
    try expect(legacy.measuredThicknessMm == nil, "legacy profile without the key decodes measuredThicknessMm = nil")

    print("ShopPilotVerifyFMR016: PASS — R016 datum-z0 gate item (block/ack/reset per job), R017 drift engine (trigger/suppress/nil), MachineProfile round-trip + legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyFMR016: FAIL — \(error)")
    exit(1)
}
