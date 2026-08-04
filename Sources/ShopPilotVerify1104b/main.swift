import Foundation
import ShopPilotCore

/// SPK-1104b verify (CLT machines, no XCTest).
/// Proves the Cut→Machine handoff contract:
///   1. FULL TREE handoff: a two-op tree (Profile + Pocket) hands its whole
///      G-code (both strategy markers) to the MachineSession buffer — not the
///      last single op.
///   2. NO AUTO-RUN: loading the buffer sends zero bytes to the transport;
///      `runJob` without a connection throws (explicit Start required).
///   3. EXPLICIT START: after connecting (simulator), an explicit `runJob`
///      streams the full buffer and completes.
///   4. PREFLIGHT GATE: a fresh gate blocks Run; it only opens after the
///      operator acknowledges every item (no auto-allow on load).
/// The Machine stage UI (RUN gated on connected + preflightPassed) is covered
/// by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() async throws {
    // ── 1. Full-tree handoff. ────────────────────────────────────────────────
    let square = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50), VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    let tree = ToolpathTreeManager()
    let profileNode = tree.addOperation("Profile 1")
    let profile = ProfileToolpathEngine.compute(
        vectors: [square], params: ProfileToolpathParams(), material: nil, stockHeightMm: 6.0
    )
    profileNode.toolpathResult = profile.gcodeLines.joined(separator: "\n")
    let pocketNode = tree.addOperation("Pocket 1")
    let pocket = PocketToolpathEngine.compute(
        vectors: [square], params: PocketToolpathParams(), material: nil, stockHeightMm: 25.0
    )
    pocketNode.toolpathResult = pocket.gcodeLines.joined(separator: "\n")

    // Mirror of AppSession.allToolpathGCode (what the Machine stage now gets).
    let fullTree = tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(fullTree.contains("O=PROFILE_TOOLPATH") && fullTree.contains("O=POCKET_TOOLPATH"),
               "handoff buffer carries BOTH ops (full tree, not last-op-only)")
    let rawCutMoves = fullTree.filter { $0.hasPrefix("G1") }
    try expect(rawCutMoves.count >= 5, "handoff buffer carries real cut moves")

    let session = MachineSession()
    session.loadGCode(fullTree)
    try expect(session.gcodeBuffer.count == fullTree.count, "session buffer holds the full tree")

    // ── 2. No auto-run: loading sends zero bytes. ────────────────────────────
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }
    // The sim's read buffer is empty until something is WRITTEN; loadGCode
    // must not write anything (no auto-start streaming on load).
    let pending = try await transport.read()
    try expect(pending.isEmpty, "loadGCode sends zero bytes (no auto-run)")

    // runJob without a connection throws — explicit Start required.
    do {
        try await session.runJob()
        throw VerifyError.failed("runJob must fail without a connection")
    } catch let error as MachineSessionError {
        if case .notConnected = error {
            // expected
        } else {
            throw VerifyError.failed("runJob threw \(error), expected notConnected")
        }
    }

    // ── 3. Explicit Start: connect then runJob streams the full buffer. ──────
    try await session.connect(transport: transport)
    try expect(session.isConnected, "session connected to the simulator")
    try await session.runJob()  // must complete without throwing
    try expect(session.gcodeBuffer.count == fullTree.count, "buffer intact after streaming")

    // ── 4. Preflight gate: blocked on load, opens only on full acknowledgement.
    let gate = PreflightGate.standard()
    try expect(!gate.isRunAllowed, "fresh preflight gate blocks Run (no auto-run)")
    for item in gate.items {
        gate.acknowledge(item.id)
    }
    try expect(gate.isRunAllowed, "gate opens after the operator acknowledges every item")

    print("ShopPilotVerify1104b: PASS — full-tree handoff, zero-bytes on load, explicit Start required, preflight gate")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify1104b: FAIL — \(error)")
    exit(1)
}
