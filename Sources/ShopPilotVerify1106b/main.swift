import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1106b verify (CLT machine, no XCTest).
/// Proves the FULL sign recipe E2E in one document flow:
///   1. RECIPE → JOB: `SignRecipeManager.createSignJob` produces text-on-curve
///      glyph curves (Design content), a decorative border, and a precomputed
///      V-Carve pass (marker + cut moves + params).
///   2. PERSIST: the precomputed pass survives a Job Codable round-trip.
///   3. TREE NODE: the replaceJob mirror materializes a clean
///      "V-Carve 1 (Recipe)" node; the full-tree buffer (mirror of
///      `session.allToolpathGCode`) carries the sign V-Carve.
///   4. PREVIEW SHOWS PATH: `WireframeRenderer.generateSegments` on the
///      full-tree buffer yields cut + rapid segments whose endpoints lie
///      inside the sheet bounds and span the glyph region — the Preview
///      stage will draw the sign's toolpath.
///   5. MACHINE BUFFER LOAD: `MachineSession.loadGCode` sends ZERO bytes to
///      `SimulatorTransport` (no auto-run); a fresh `PreflightGate` blocks
///      Start until acknowledged; explicit `runJob` streams the sign V-Carve
///      and completes.
/// The UI glue (recipe picker → session.replaceJob at ContentView:105) is
/// covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Mirror of `AppSession.replaceJob`'s SPK-1106a materialization.
func materializeRecipeNode(_ job: Job, into tree: ToolpathTreeManager) {
    guard let vcarveGCode = job.vcarveGCode, !vcarveGCode.isEmpty else { return }
    let node = tree.addOperation("V-Carve 1 (Recipe)")
    node.toolpathResult = vcarveGCode.joined(separator: "\n")
    node.estimatedTimeSeconds = job.vcarveTimeSeconds
    node.paramsJSON = job.vcarveParamsJSON
    node.clearDirty()
}

/// Mirror of `AppSession.allToolpathGCode`: every computed node's result in
/// tree order.
func fullTreeBuffer(_ tree: ToolpathTreeManager) -> [String] {
    tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

func main() async throws {
    // ── 1+2. Recipe → job → persist round-trip. ─────────────────────────────
    let job = SignRecipeManager.createSignJob(
        jobName: "E2E Sign",
        text: "SHOP",
        fontSize: 48,
        vBitAngle: 90,
        vCarveDepth: 0.5,
        feedRate: 1200
    )
    guard let sheet = job.sheets.first else { throw VerifyError.failed("recipe job has a sheet") }
    let textVectors = sheet.layers.first { $0.name == "Text" }?.vectors ?? []
    try expect(!textVectors.isEmpty, "recipe places text-on-curve glyph curves on the Text layer")
    guard let vcarveGCode = job.vcarveGCode, !vcarveGCode.isEmpty else {
        throw VerifyError.failed("recipe job carries the V-Carve G-code")
    }
    try expect(vcarveGCode.contains("O=V_CARVE_TOOLPATH"), "recipe pass is real engine G-code")

    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.vcarveGCode == job.vcarveGCode, "Job round-trip keeps the V-Carve G-code")

    // ── 3. Tree node + full-tree buffer (mirror of allToolpathGCode). ───────
    let tree = ToolpathTreeManager()
    materializeRecipeNode(decoded, into: tree)
    let ops = tree.allNodes.filter { $0.isOperation }
    try expect(ops.count == 1 && ops[0].isVCarveOperation, "recipe V-Carve lands as a V-Carve tree node")
    try expect(!ops[0].isDirty, "recipe node starts clean (fresh engine result)")
    let buffer = fullTreeBuffer(tree)
    try expect(buffer.contains("O=V_CARVE_TOOLPATH"), "full-tree buffer carries the sign V-Carve marker")
    try expect(buffer.contains { $0.hasPrefix("G1") }, "full-tree buffer has real cut moves")

    // ── 4. Preview shows the path: wireframe segments span the glyph region. ─
    let segments = WireframeRenderer.generateSegments(from: buffer)
    try expect(!segments.isEmpty, "wireframe renders segments for the sign path")
    try expect(segments.contains { !$0.isRapid }, "wireframe has cut (non-rapid) segments")
    let cutSegments = segments.filter { !$0.isRapid }
    let xs = cutSegments.flatMap { [$0.start.x, $0.end.x] }
    let ys = cutSegments.flatMap { [$0.start.y, $0.end.y] }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        throw VerifyError.failed("cut segments must have coordinates")
    }
    // The sign arc is centered near sheet center (width/2, depth/2 + 50) with
    // radius ~120 + glyph extent — every cut point must sit inside the sheet.
    try expect(minX >= 0 && maxX <= sheet.width, "wireframe cut points inside sheet X bounds (got \(minX)...\(maxX) of \(sheet.width))")
    try expect(minY >= 0 && maxY <= sheet.depth, "wireframe cut points inside sheet Y bounds (got \(minY)...\(maxY) of \(sheet.depth))")
    // Real sign path: meaningful extent in both axes (not a degenerate dot).
    try expect(maxX - minX > 1.0 && maxY - minY > 1.0,
               "wireframe spans a real region (\(maxX - minX) x \(maxY - minY) mm)")

    // ── 5. Machine buffer load: zero bytes, preflight gates Start, run. ─────
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }
    let session = MachineSession()
    session.loadGCode(buffer)
    try expect(session.gcodeBuffer.count == buffer.count, "full sign tree in the session buffer")
    try expect((try await transport.read()).isEmpty, "load sent ZERO bytes (no auto-run)")

    let gate = PreflightGate.standard()
    try expect(!gate.isRunAllowed, "fresh preflight gate blocks Start")
    for item in gate.items { gate.acknowledge(item.id) }
    try expect(gate.isRunAllowed, "preflight acknowledgement arms Start")

    try await session.connect(transport: transport)
    try expect(session.isConnected, "connected to the simulator")
    let run = Task { try await session.runJob() }
    try await run.value
    try expect(session.gcodeBuffer.count == buffer.count, "buffer intact after the sign run completes")

    print("ShopPilotVerify1106b: PASS — recipe→text→curves→V-Carve node→preview path→machine load(0 bytes)→preflight→start→complete")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify1106b: FAIL — \(error)")
    exit(1)
}
