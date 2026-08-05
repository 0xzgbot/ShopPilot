import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-SHAKEg verify (CLT): Preview + Machine sim + Hold/Resume/Reset.
///
/// Extends the 1103e/1104d coverage with the missing RESET leg and bundles
/// the preview gates in one matrix:
///   1. Wireframe preview non-blank: real-engine G-code → segments exist and
///      stay inside the sheet.
///   2. Draft sim cancellable: an immediately-true probe aborts with
///      `isCancelled`; the no-probe pass equals the plain pass (not lossy).
///   3. Machine sim loop: connect → load (ZERO bytes, no auto-run) →
///      fresh preflight blocks Start → ack arms → runJob → mid-run HOLD `!` →
///      RESUME `~` → RESET 0x18 → job ends, reset byte observable on the
///      transport (1104d covered hold/resume only).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y),
            VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size),
            VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

var total = 0
func ok(_ name: String) { total += 1; print("  ok   \(name)") }

func main() async throws {
    // Shared fixture: real Profile + Pocket G-code on a 200×200 sheet.
    let sheet = (w: 200.0, d: 200.0, h: 18.0)
    let square = makeClosedRect(x: 25, y: 25, size: 50)
    let profile = ProfileToolpathEngine.compute(
        vectors: [square], params: ProfileToolpathParams(), material: nil,
        stockHeightMm: sheet.h
    )
    let pocket = PocketToolpathEngine.compute(
        vectors: [square], params: PocketToolpathParams(), material: nil,
        stockHeightMm: sheet.h
    )
    let buffer = (profile.gcodeLines + pocket.gcodeLines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    // ── 1. Preview: wireframe non-blank, bounded by the sheet. ──────────────
    print("== Preview wireframe ==")
    let segments = WireframeRenderer.generateSegments(from: buffer)
    try expect(segments.count >= 10, "wireframe has real segments (got \(segments.count))")
    let inSheet = segments.allSatisfy { seg in
        seg.start.x >= -0.001 && seg.start.x <= sheet.w + 0.001 &&
        seg.start.y >= -0.001 && seg.start.y <= sheet.d + 0.001 &&
        seg.end.x >= -0.001 && seg.end.x <= sheet.w + 0.001 &&
        seg.end.y >= -0.001 && seg.end.y <= sheet.d + 0.001
    }
    try expect(inSheet, "every segment endpoint inside the sheet bounds")
    try expect(segments.contains { !$0.isRapid }, "at least one cut segment (not all rapid)")
    ok("wireframe: \(segments.count) segments, all in-sheet, cut moves present")

    // ── 2. Draft sim cancellable. ───────────────────────────────────────────
    print("== Draft sim cancel ==")
    let cancelled = WireframeRenderer.generateSegmentsCancellable(from: buffer, shouldCancel: { true })
    try expect(cancelled.isCancelled, "immediately-true probe aborts the pass")
    let plain = WireframeRenderer.generateSegments(from: buffer)
    let full = WireframeRenderer.generateSegmentsCancellable(from: buffer)
    try expect(!full.isCancelled, "no-probe pass runs to completion")
    try expect(full.segments.count == plain.count, "no-probe pass is not lossy (equals plain)")
    ok("draft sim: cancel aborts; full pass equals plain pass")

    // ── 3. Machine sim loop incl. RESET (0x18) mid-run. ─────────────────────
    print("== Machine sim loop ==")
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }

    let session = MachineSession()
    session.loadGCode(buffer)
    try expect(session.gcodeBuffer.count == buffer.count, "full buffer loaded")
    try expect((try await transport.read()).isEmpty, "load sent ZERO bytes (no auto-run)")
    ok("load: zero bytes, no auto-run")

    let gate = PreflightGate.standard()
    try expect(!gate.isRunAllowed, "fresh preflight blocks Start")
    for item in gate.items { gate.acknowledge(item.id) }
    try expect(gate.isRunAllowed, "acknowledged preflight arms Start")
    ok("preflight: blocks fresh, arms after ack")

    try await session.connect(transport: transport)
    try expect(session.isConnected, "connected to the simulator")

    // Mid-run: hold → resume → reset, bytes observed on the transport.
    let job = Task { try await session.runJob() }
    try await Task.sleep(nanoseconds: 30_000_000)
    try await session.hold()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x21 }),
               "mid-run HOLD wrote `!` (0x21)")
    try await Task.sleep(nanoseconds: 20_000_000)
    try await session.resume()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x7E }),
               "mid-run RESUME wrote `~` (0x7E)")
    try await Task.sleep(nanoseconds: 20_000_000)
    try await session.reset()
    try expect(await transport.writtenBytesSnapshot.contains(where: { $0 == 0x18 }),
               "mid-run RESET wrote 0x18")

    // Reset aborts the stream: the runJob task must end (no hang).
    let outcome = await job.result
    _ = outcome
    ok("hold(!) → resume(~) → reset(0x18) → job ended")

    print("\nRESULT: SPK-SHAKEg \(total) checks — PASS")
}

do {
    try await main()
} catch {
    print("FAIL: \(error)")
    exit(1)
}
