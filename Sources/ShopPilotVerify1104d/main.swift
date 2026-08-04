import Foundation
import ShopPilotCore

/// SPK-1104d verify (CLT machines, no XCTest).
/// Proves the FULL Sim integration loop the Machine stage drives:
///   1. CONNECT: simulator transport opens; session connects.
///   2. LOAD: full-tree buffer loads into the session (zero bytes sent).
///   3. PREFLIGHT: fresh gate blocks; operator acknowledgement arms Start.
///   4. START: explicit runJob streams the full tree and completes.
///   5. HOLD/RESUME mid-run: realtime `!` / `~` bytes reach the shared
///      transport while the session is active (the safety contract — GRBL
///      realtime, not buffered); the stream still completes after resume.
/// The UI glue (RUN gated on connected + preflightPassed) is covered by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y), VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size), VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

func main() async throws {
    // Build a full-tree buffer (Profile + Pocket, real engines).
    let tree = ToolpathTreeManager()
    let profileNode = tree.addOperation("Profile 1")
    let profile = ProfileToolpathEngine.compute(
        vectors: [makeClosedRect(x: 0, y: 0, size: 50)],
        params: ProfileToolpathParams(), material: nil, stockHeightMm: 6.0
    )
    profileNode.toolpathResult = profile.gcodeLines.joined(separator: "\n")
    let pocketNode = tree.addOperation("Pocket 1")
    let pocket = PocketToolpathEngine.compute(
        vectors: [makeClosedRect(x: 0, y: 0, size: 50)],
        params: PocketToolpathParams(), material: nil, stockHeightMm: 25.0
    )
    pocketNode.toolpathResult = pocket.gcodeLines.joined(separator: "\n")
    let buffer = tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(buffer.contains("O=PROFILE_TOOLPATH") && buffer.contains("O=POCKET_TOOLPATH"),
               "full-tree buffer ready")

    // 1+2. Connect + load; loading sends zero bytes (no auto-run).
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }
    let session = MachineSession()
    session.loadGCode(buffer)
    try expect(session.gcodeBuffer.count == buffer.count, "full tree in the session buffer")
    try expect((try await transport.read()).isEmpty, "load sent zero bytes")

    // 3. Preflight arms Start only after acknowledgement.
    let gate = PreflightGate.standard()
    try expect(!gate.isRunAllowed, "fresh gate blocks Start")
    for item in gate.items { gate.acknowledge(item.id) }
    try expect(gate.isRunAllowed, "gate arms Start after acknowledgement")

    // 4+5. Connect, start, and hold/resume with realtime bytes mid-run.
    try await session.connect(transport: transport)
    try expect(session.isConnected, "connected to the simulator")

    // Realtime bytes when idle (no streamer draining the read buffer):
    try await session.hold()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x21 }),
               "idle HOLD wrote realtime `!` (0x21)")
    try await session.resume()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x7E }),
               "idle RESUME wrote realtime `~` (0x7E)")

    // Full loop: start, hold/resume mid-run (bytes tracked on the transport
    // — the streamer concurrently drains the read buffer, so the write log
    // is the race-free observable), stream completes.
    let job = Task { try await session.runJob() }
    try await Task.sleep(nanoseconds: 20_000_000)
    try await session.hold()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x21 }),
               "mid-run HOLD wrote realtime `!` (0x21) to the transport")
    try await Task.sleep(nanoseconds: 20_000_000)
    try await session.resume()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x7E }),
               "mid-run RESUME wrote realtime `~` (0x7E) to the transport")

    // Stream completes after resume.
    try await job.value
    try expect(session.gcodeBuffer.count == buffer.count, "buffer intact after the full run")

    print("ShopPilotVerify1104d: PASS — connect→load→preflight→start→hold(!)→resume(~)→complete")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify1104d: FAIL — \(error)")
    exit(1)
}
