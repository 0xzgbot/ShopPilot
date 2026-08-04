import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1106a verify (CLT machines, no XCTest).
/// Proves the Sign recipe thin slice: one document flow of
/// text → curves → V-Carve toolpath node:
///   1. `SignRecipeManager.createSignJob` produces a job with text-on-curve
///      glyph vectors (Design stage content), a decorative border, and a
///      PRECOMPUTED V-Carve pass (passes + time + full G-code + params).
///   2. The recipe's V-Carve survives a Job Codable round-trip (persist).
///   3. Mirror of session `replaceJob` materialization: the precomputed
///      V-Carve becomes a real tree node — Cut stage sees it, the machine
///      handoff buffer carries it, the node is clean with stored params.
/// The NewJobView recipe picker glue is covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. One flow: text → curves → V-Carve in the recipe job. ─────────────
    let job = SignRecipeManager.createSignJob(
        jobName: "Test Sign",
        text: "HI",
        fontSize: 36,
        vBitAngle: 90,
        vCarveDepth: 0.5,
        feedRate: 1200
    )

    // Design content: text glyph vectors on the Text layer + border layer.
    let textVectors = job.sheets.first?.layers.first { $0.name == "Text" }?.vectors ?? []
    try expect(!textVectors.isEmpty, "recipe places text-on-curve glyph vectors on the Text layer")
    let sheetLayers = job.sheets.first?.layers.count ?? 0
    try expect(sheetLayers >= 2, "recipe builds Text + decorative border layers")

    // Precomputed V-Carve: stats + full G-code + params.
    try expect(job.vcarvePasses >= 1, "recipe precomputes V-Carve passes")
    try expect(job.vcarveTimeSeconds > 0, "recipe precomputes V-Carve time")
    guard let vcarveGCode = job.vcarveGCode, !vcarveGCode.isEmpty else {
        throw VerifyError.failed("recipe job carries the full V-Carve G-code")
    }
    try expect(vcarveGCode.contains("O=V_CARVE_TOOLPATH"), "precomputed pass is real engine G-code")
    try expect(vcarveGCode.contains { $0.hasPrefix("G1") }, "precomputed pass has cut moves")
    guard let paramsJSON = job.vcarveParamsJSON,
          let paramsData = paramsJSON.data(using: .utf8),
          let params = try? JSONDecoder().decode(VCarveParams.self, from: paramsData) else {
        throw VerifyError.failed("recipe job carries the V-Carve params")
    }
    try expect(params.vBitAngleDegrees == 90 && params.feedRateMmPerMin == 1200,
               "stored params match the recipe's settings")

    // ── 2. Persist: Job round-trip keeps the precomputed pass. ───────────────
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.vcarveGCode == job.vcarveGCode, "Job round-trip keeps the V-Carve G-code")
    try expect(decoded.vcarveParamsJSON == job.vcarveParamsJSON, "Job round-trip keeps the params")

    // ── 3. Mirror of session.replaceJob: materialize the tree node. ──────────
    let tree = ToolpathTreeManager()
    if let gcode = decoded.vcarveGCode, !gcode.isEmpty {
        let node = tree.addOperation("V-Carve 1 (Recipe)")
        node.toolpathResult = gcode.joined(separator: "\n")
        node.estimatedTimeSeconds = decoded.vcarveTimeSeconds
        node.paramsJSON = decoded.vcarveParamsJSON
        node.clearDirty()
    }
    let ops = tree.allNodes.filter { $0.isOperation }
    try expect(ops.count == 1 && ops[0].isVCarveOperation, "recipe V-Carve lands as a V-Carve tree node")
    try expect(!ops[0].isDirty, "recipe node starts clean (fresh engine result)")
    let buffer = tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    try expect(buffer.contains("O=V_CARVE_TOOLPATH"), "machine handoff buffer carries the recipe's V-Carve")
    try expect(buffer.contains { $0.hasPrefix("G1") }, "handoff buffer has real cut moves")

    print("ShopPilotVerify1106a: PASS — text→curves→V-Carve in one flow, persist round-trip, tree node materialized for Cut/handoff")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1106a: FAIL — \(error)")
    exit(1)
}
