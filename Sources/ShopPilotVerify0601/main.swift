import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0601 verify (CLT machine, no XCTest).
/// Proves the SIGN JOB E2E on the simulator — the v1 differentiator flow:
///   1. RECIPE → JOB: `SignRecipeManager.createSignJob` produces a Text layer
///      of text-on-curve glyph curves (named per character), a decorative
///      Border layer fully inside the stock (20mm margin), and a precomputed
///      V-Carve pass (marker + cut moves + params).
///   2. PERSIST: the precomputed pass survives a Job Codable round-trip
///      (gcode, params JSON, time).
///   3. TREE NODE: the `replaceJob` mirror materializes a clean
///      "V-Carve 1 (Recipe)" node; its stored params JSON decodes back to the
///      recipe's VCarveParams (feed 1200, 90° V-bit); marking it dirty blocks
///      export (no silent auto-recalc) and clearing unblocks — the SPK-0603
///      contract holds on a recipe node too.
///   4. PREVIEW SHOWS PATH: `WireframeRenderer.generateSegments` on the
///      full-tree buffer yields cut segments whose endpoints lie inside the
///      sheet and span the glyph region — the Preview stage draws the sign.
///   5. MACHINE BUFFER LOAD: `MachineSession.loadGCode` sends ZERO bytes to
///      `SimulatorTransport` (no auto-run); a fresh `PreflightGate` blocks
///      Start until acknowledged; explicit `runJob` streams the sign V-Carve
///      and completes.
/// The UI glue (recipe picker → session.replaceJob at NewJobView:133) is
/// covered by the app build. Human G1 screen captures stay open (SPK-0623).

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
    // ── 1. Recipe → job: full sign structure. ───────────────────────────────
    let job = SignRecipeManager.createSignJob(
        jobName: "E2E Sign",
        text: "SHOP",
        fontSize: 48,
        vBitAngle: 90,
        vCarveDepth: 0.5,
        feedRate: 1200
    )
    guard let sheet = job.sheets.first else { throw VerifyError.failed("recipe job has a sheet") }
    try expect(abs(sheet.width - 457.2) < 0.001 && abs(sheet.depth - 609.6) < 0.001 && abs(sheet.height - 19.05) < 0.001,
               "recipe sheet is the sign stock (457.2 x 609.6 x 19.05)")

    guard let textLayer = sheet.layers.first(where: { $0.name == "Text" }) else {
        throw VerifyError.failed("recipe has a Text layer")
    }
    try expect(!textLayer.vectors.isEmpty, "recipe places text-on-curve glyph curves on the Text layer")
    try expect(textLayer.vectors.contains { $0.name.hasPrefix("Glyph ") },
               "glyphs are named per character (Glyph S/H/O/P)")
    let glyphPoints = textLayer.vectors.flatMap { $0.points }
    try expect(glyphPoints.allSatisfy { $0.x >= 0 && $0.x <= sheet.width && $0.y >= 0 && $0.y <= sheet.depth },
               "glyph curves sit inside the stock bounds")

    guard let borderLayer = sheet.layers.first(where: { $0.name == "Border" }) else {
        throw VerifyError.failed("recipe has a Border layer")
    }
    try expect(borderLayer.vectors.count == 1, "recipe places the decorative border")
    let border = borderLayer.vectors[0]
    try expect(border.isClosed, "decorative border is a closed vector")
    try expect(border.points.allSatisfy { $0.x >= 20 && $0.x <= sheet.width - 20 && $0.y >= 20 && $0.y <= sheet.depth - 20 },
               "border sits inside the stock with a ~20mm margin")

    guard let vcarveGCode = job.vcarveGCode, !vcarveGCode.isEmpty else {
        throw VerifyError.failed("recipe job carries the V-Carve G-code")
    }
    try expect(vcarveGCode.contains("O=V_CARVE_TOOLPATH"), "recipe pass is real engine G-code")
    try expect(vcarveGCode.contains { $0.hasPrefix("G1") }, "recipe pass has real cut moves")
    try expect(job.vcarvePasses > 0, "recipe records pass count")

    // ── 2. Persist: Job Codable round-trip keeps the pass + params. ─────────
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.vcarveGCode == job.vcarveGCode, "Job round-trip keeps the V-Carve G-code")
    try expect(decoded.vcarveParamsJSON == job.vcarveParamsJSON, "Job round-trip keeps the V-Carve params JSON")
    try expect(abs(decoded.vcarveTimeSeconds - job.vcarveTimeSeconds) < 0.001,
               "Job round-trip keeps the time estimate")

    // ── 3. Tree node: recipe V-Carve lands clean; stored params decode. ─────
    let tree = ToolpathTreeManager()
    materializeRecipeNode(decoded, into: tree)
    let ops = tree.allNodes.filter { $0.isOperation }
    try expect(ops.count == 1 && ops[0].isVCarveOperation, "recipe V-Carve lands as a V-Carve tree node")
    try expect(ops[0].name == "V-Carve 1 (Recipe)", "recipe node carries the recipe name")
    try expect(!ops[0].isDirty, "recipe node starts clean (fresh engine result)")

    if let paramsJSON = ops[0].paramsJSON,
       let paramsData = paramsJSON.data(using: .utf8),
       let stored = try? JSONDecoder().decode(VCarveParams.self, from: paramsData) {
        try expect(abs(stored.feedRateMmPerMin - 1200) < 0.001, "stored params keep the recipe feed rate (F1200)")
        try expect(abs(stored.vBitAngleDegrees - 90) < 0.001, "stored params keep the 90° V-bit")
        try expect(abs(stored.maxDepthOfCutMm - 0.5) < 0.001, "stored params keep the carve depth")
    } else {
        throw VerifyError.failed("recipe node params JSON decodes to VCarveParams")
    }

    // Dirty/export gate contract on a recipe node (SPK-0603 semantics).
    let blocker = ExportBlocker(treeManager: tree)
    ops[0].markDirty()
    try expect(blocker.validateForExport().requiresOverride, "dirty recipe node blocks export (no silent auto-recalc)")
    ops[0].clearDirty()
    try expect(blocker.validateForExport().canExport, "clean recipe node exports freely")

    let buffer = fullTreeBuffer(tree)
    try expect(buffer.contains("O=V_CARVE_TOOLPATH"), "full-tree buffer carries the sign V-Carve marker")
    try expect(buffer.contains { $0.hasPrefix("G1") }, "full-tree buffer has real cut moves")

    // ── 4. Preview shows the path: wireframe spans the glyph region in-sheet. ─
    let segments = WireframeRenderer.generateSegments(from: buffer)
    try expect(!segments.isEmpty, "wireframe renders segments for the sign path")
    try expect(segments.contains { !$0.isRapid }, "wireframe has cut (non-rapid) segments")
    let cutSegments = segments.filter { !$0.isRapid }
    let xs = cutSegments.flatMap { [$0.start.x, $0.end.x] }
    let ys = cutSegments.flatMap { [$0.start.y, $0.end.y] }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        throw VerifyError.failed("cut segments must have coordinates")
    }
    try expect(minX >= 0 && maxX <= sheet.width, "wireframe cut points inside sheet X bounds (got \(minX)...\(maxX) of \(sheet.width))")
    try expect(minY >= 0 && maxY <= sheet.depth, "wireframe cut points inside sheet Y bounds (got \(minY)...\(maxY) of \(sheet.depth))")
    try expect(maxX - minX > 1.0 && maxY - minY > 1.0,
               "wireframe spans a real sign region (\(maxX - minX) x \(maxY - minY) mm)")

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

    print("ShopPilotVerify0601: PASS — recipe→glyphs→border→V-Carve node(params decode, dirty gate)→preview in-sheet→machine load(0 bytes)→preflight→start→complete")
}

do {
    try await main()
} catch {
    print("ShopPilotVerify0601: FAIL — \(error)")
    exit(1)
}
