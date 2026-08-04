import Foundation
import ShopPilotCore

/// SPK-0600 verify (CLT machine, no XCTest).
/// Proves the CALIBRATION JOB E2E on the simulator — the whole v1 product
/// spine in one flow:
///   1. DESIGN: a closed 50x50 calibration rectangle.
///   2. CUT: a real Profile engine run lands in the tree (marker + cut moves),
///      with the strategy's stored params (feed 1500) on the node.
///   3. DIRTY/RECALC: a design change marks the node dirty → export is BLOCKED
///      → `recalculateDirtyToolpaths` regenerates with the REAL engine and the
///      STORED params (F1500 reaches the G-code) → export unblocked.
///   4. PREVIEW: the full-tree buffer renders wireframe segments spanning the
///      rectangle, and the sheet-aware material sim carves the cells the
///      cutter passes through (edges) while interior/outside stock stays.
///   5. MACHINE: connect(sim) → loadGCode sends ZERO bytes (no auto-run) →
///      a fresh PreflightGate blocks Start → acknowledgement arms it →
///      explicit runJob streams the calibration job and completes.
/// The UI glue (canvas create tools, Cut recalc button, Preview Simulate,
/// Machine RUN) is covered by the app build.

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

func fullTreeBuffer(_ tree: ToolpathTreeManager) -> [String] {
    tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

func encodeParams(_ params: ProfileToolpathParams) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

func sample(_ samples: [(x: Double, y: Double, z: Double)], _ x: Double, _ y: Double) -> Double? {
    samples.first(where: { abs($0.x - x) < 0.001 && abs($0.y - y) < 0.001 })?.z
}

func main() async throws {
    // ── 1. DESIGN: closed calibration rectangle. ────────────────────────────
    let calibrationRect = makeClosedRect(x: 10, y: 10, size: 50)
    try expect(calibrationRect.isClosed && calibrationRect.points.count == 5,
               "calibration shape is a closed rectangle")

    // ── 2. CUT: Profile engine into the tree, stored params on the node. ────
    var params = ProfileToolpathParams()
    params.feedRateMmPerMin = 1500
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Profile Calibration")
    node.paramsJSON = encodeParams(params)
    let result = ProfileToolpathEngine.compute(
        vectors: [calibrationRect],
        params: params,
        material: nil,
        stockHeightMm: 6.0
    )
    node.toolpathResult = result.gcodeLines.joined(separator: "\n")
    node.estimatedTimeSeconds = result.estimatedTimeSeconds
    node.clearDirty()
    guard let gcode = node.toolpathResult else { throw VerifyError.failed("profile result landed on the node") }
    try expect(gcode.contains("O=PROFILE_TOOLPATH"), "profile node is real engine G-code")
    try expect(gcode.split(separator: "\n").contains { $0.hasPrefix("G1") }, "profile node has cut moves")
    try expect(!node.isDirty, "fresh profile node is clean")

    // ── 3. DIRTY/RECALC: design change → block → regen → unblock. ──────────
    let blocker = ExportBlocker(treeManager: tree)
    node.markDirty()
    try expect(blocker.validateForExport().requiresOverride, "dirty node blocks export (no silent auto-recalc)")
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [calibrationRect],
        material: nil,
        stockHeightMm: 6.0
    )
    try expect(regenerated.count == 1 && regenerated[0].id == node.id, "recalc regenerated the calibration node")
    try expect(!node.isDirty, "recalc cleared the dirty badge")
    try expect(blocker.validateForExport().canExport, "export unblocked after recalc")
    try expect((node.toolpathResult ?? "").contains("F1500"),
               "recalc honored the stored params (F1500 in regenerated G-code)")

    // ── 4. PREVIEW: wireframe + sheet-aware material sim. ───────────────────
    let buffer = fullTreeBuffer(tree)
    let segments = WireframeRenderer.generateSegments(from: buffer)
    try expect(!segments.isEmpty, "preview wireframe renders segments")
    let cutSegments = segments.filter { !$0.isRapid }
    try expect(!cutSegments.isEmpty, "preview wireframe has cut segments")
    let xs = cutSegments.flatMap { [$0.start.x, $0.end.x] }
    let ys = cutSegments.flatMap { [$0.start.y, $0.end.y] }
    try expect((xs.min() ?? -1) >= 0 && (xs.max() ?? 101) <= 100, "wireframe inside sheet X")
    try expect((ys.min() ?? -1) >= 0 && (ys.max() ?? 101) <= 100, "wireframe inside sheet Y")
    try expect(((xs.max() ?? 0) - (xs.min() ?? 0)) >= 40, "wireframe spans the 50mm rectangle")

    let sim = ToolpathSimulator.materialSimulation(
        from: buffer,
        sheetWidthMm: 100, sheetDepthMm: 100, stockTopMm: 6.0,
        cellSizeMm: 1.0
    )
    try expect(!sim.isCancelled, "material sim completed")
    let onEdge = try sample(sim.samples, 30, 10) ?? { throw VerifyError.failed("missing sample on profile edge") }()
    let interior = try sample(sim.samples, 30, 30) ?? { throw VerifyError.failed("missing sample interior") }()
    let outside = try sample(sim.samples, 90, 90) ?? { throw VerifyError.failed("missing sample outside") }()
    try expect(onEdge < 5.999, "cutter path cells are carved (edge z \(onEdge))")
    try expect(abs(interior - 6.0) < 0.001, "interior stock untouched by the profile cut")
    try expect(abs(outside - 6.0) < 0.001, "stock outside the job untouched")

    // ── 5. MACHINE: connect → load (zero bytes) → preflight → run. ──────────
    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }
    let machine = MachineSession()
    machine.loadGCode(buffer)
    try expect(machine.gcodeBuffer.count == buffer.count, "calibration job in the machine buffer")
    try expect((try await transport.read()).isEmpty, "load sent ZERO bytes (no auto-run)")

    let gate = PreflightGate.standard()
    try expect(!gate.isRunAllowed, "fresh preflight gate blocks Start")
    for item in gate.items { gate.acknowledge(item.id) }
    try expect(gate.isRunAllowed, "preflight acknowledgement arms Start")

    try await machine.connect(transport: transport)
    try expect(machine.isConnected, "connected to the simulator")
    let run = Task { try await machine.runJob() }
    try await run.value
    try expect(machine.gcodeBuffer.count == buffer.count, "buffer intact after the calibration run completes")

    print("ShopPilotVerify0600: PASS — design→cut→dirty/recalc→preview(wireframe+material)→machine(0 bytes, preflight, run) calibration E2E")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify0600: FAIL — \(error)")
    exit(1)
}
