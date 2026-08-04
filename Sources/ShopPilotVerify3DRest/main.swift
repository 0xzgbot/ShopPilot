import Foundation
import ShopPilotCore

/// SPK-3D-rest verify (CLT machine, no XCTest).
/// Proves rest machining on the 3D rough engine.
///
/// Fixture (8×7, 1mm cells): row profile [2,2,2,2, 6,6, 2,2] — cols 0..3
/// surface 2 (WIDE low region, 4mm wide), cols 4..5 surface 6 (a wall, above
/// every level, never cut), cols 6..7 surface 2 (NARROW low region, 2mm
/// wide). Low cells (2) are cut at levels ≥ 2 → levels 4.5 and 2.5 only
/// (stockTop 6.5, stepDown 2 → [4.5, 2.5, 0.5, 0]).
///
/// REST semantics: a rest pass uses a SMALLER tool to clear only what the
/// previous LARGER tool could not reach. A low run at least as wide as the
/// previous tool's diameter was already cleared by it → skipped; a narrower
/// valley is the rest target → cut.
///
///   1. PLAIN ROUGH: both low runs cut at Z=-2.000 (regression guard).
///   2. REST after 3.5mm tool: wide run (4mm ≥ 3.5) SKIPPED, narrow run
///      (2mm < 3.5) CUT — the rest pass's whole job.
///   3. REST after 5mm tool: both runs (4mm, 2mm) < 5 → both cut again.
///      REST after 2mm tool: both runs ≥ 2 → nothing cut (cleared already).
///   4. Header documents "(Rest Rough: 2.0mm after Xmm, 4 z-levels)".
///   5. LEGACY paramsJSON (no key) decodes with previousToolDiameterMm == 0.
///   6. Persist round-trip keeps the rest field.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Row profile [2,2,2,2,6,6,2,2] tiled over 7 rows.
func valleyRelief() -> HeightfieldData {
    let profile = [2.0, 2.0, 2.0, 2.0, 6.0, 6.0, 2.0, 2.0]
    var h: [Double] = []
    for _ in 0..<7 {
        h.append(contentsOf: profile)
    }
    return HeightfieldData(width: 8, height: 7, cellSizeMm: 1.0, minX: 0, minY: 0, heights: h)
}

/// X-runs of cut G1 moves at a given pass depth. Engine format per run:
///   "G0 X<start> Y<cy]" then "G1 X<end> Y<cy> F<feed>"
/// (the G1 carries only the end; the start comes from the preceding G0).
func cutRuns(_ lines: [String], atDepth: String) -> [(x0: Double, x1: Double)] {
    var runs: [(Double, Double)] = []
    var inPass = false
    var pendingStart: Double? = nil
    for line in lines {
        if line.hasPrefix("(Pass") {
            inPass = line.contains("Z=\(atDepth)")
            pendingStart = nil
            continue
        }
        guard inPass else { continue }
        if line.hasPrefix("G0 X") {
            let comps = line.split(separator: " ")
            if comps.count >= 2, let x = Double(comps[1].dropFirst(1)) {
                pendingStart = x
            }
        } else if line.hasPrefix("G1 X"), !line.contains("Z=") {
            let comps = line.split(separator: " ")
            guard comps.count >= 2, let x1 = Double(comps[1].dropFirst(1)),
                  let x0 = pendingStart else { continue }
            runs.append((x0, x1))
            pendingStart = nil
        }
    }
    return runs
}

func hasRun(_ runs: [(x0: Double, x1: Double)], from x0: Double, to x1: Double) -> Bool {
    runs.contains { abs($0.x0 - x0) < 0.01 && abs($0.x1 - x1) < 0.01 }
}

func makeParams(previousTool: Double) -> HeightfieldRoughParams {
    HeightfieldRoughParams(
        toolDiameterMm: 2.0, stepDownMm: 2.0, stepOverMm: 1.0,
        feedRateMmPerMin: 1000, plungeFeedRateMmPerMin: 300,
        safeZHeightMm: 5.0, stockAllowanceMm: 0.5,
        previousToolDiameterMm: previousTool
    )
}

func main() throws {
    let hf = valleyRelief()
    try expect(abs(hf.maxHeight - 6.0) < 1e-9, "fixture peaks at 6mm (the wall)")
    // stockTop = 6.5, stepDown 2 → levels [4.5, 2.5, 0.5, 0] = 4 passes.
    // Low cells (surface 2) are cut at levels 4.5 (Z=-2.000) and 2.5 (Z=-4.000).

    // ── 1. Plain rough cuts both low runs (regression guard). ──────────────
    let plain = makeParams(previousTool: 0)
    try expect(!plain.isRestRough, "default params are NOT a rest rough")
    let plainResult = HeightfieldRoughEngine.compute(heightfield: hf, params: plain)
    try expect(plainResult.passCount == 4, "plain rough has 4 z-levels (got \(plainResult.passCount))")
    try expect(plainResult.gcodeLines.contains("(Rough: 2.0mm, 4 z-levels)"),
               "plain rough header unchanged")
    let plainRuns = cutRuns(plainResult.gcodeLines, atDepth: "-2.000")
    try expect(hasRun(plainRuns, from: 0.5, to: 3.5), "plain cuts the wide run 0.5→3.5")
    try expect(hasRun(plainRuns, from: 6.5, to: 7.5), "plain cuts the narrow run 6.5→7.5")

    // ── 2. Rest after a 3.5mm tool: wide run skipped, narrow run cut. ──────
    let rest = makeParams(previousTool: 3.5)
    try expect(rest.isRestRough, "params with previousToolDiameterMm ARE a rest rough")
    let restResult = HeightfieldRoughEngine.compute(heightfield: hf, params: rest)
    try expect(restResult.gcodeLines.contains("(Rest Rough: 2.0mm after 3.5mm, 4 z-levels)"),
               "rest header names both tools")
    let restRuns = cutRuns(restResult.gcodeLines, atDepth: "-2.000")
    try expect(!hasRun(restRuns, from: 0.5, to: 3.5),
               "rest SKIPS the 4mm-wide run (previous 3.5mm tool cleared it)")
    try expect(hasRun(restRuns, from: 6.5, to: 7.5),
               "rest CUTS the 2mm-wide valley (previous tool could not reach it)")
    try expect(restResult.passCount == 4, "rest keeps all z-levels (got \(restResult.passCount))")

    // ── 3. Previous-tool width drives how much rest re-cuts. ───────────────
    // 5mm previous: both runs narrower → both cut again.
    let restBig = makeParams(previousTool: 5.0)
    let restBigResult = HeightfieldRoughEngine.compute(heightfield: hf, params: restBig)
    let bigRuns = cutRuns(restBigResult.gcodeLines, atDepth: "-2.000")
    try expect(hasRun(bigRuns, from: 0.5, to: 3.5) && hasRun(bigRuns, from: 6.5, to: 7.5),
               "rest after 5mm re-cuts both runs (5mm tool cleared neither)")
    // 2mm previous: both runs ≥ 2mm → already cleared → nothing cut.
    let restTiny = makeParams(previousTool: 2.0)
    let restTinyResult = HeightfieldRoughEngine.compute(heightfield: hf, params: restTiny)
    let tinyRuns = cutRuns(restTinyResult.gcodeLines, atDepth: "-2.000")
    try expect(tinyRuns.isEmpty, "rest after 2mm cuts nothing (both runs already cleared)")

    // ── 4. Legacy params decode as plain rough. ────────────────────────────
    let legacyJSON = #"{"toolDiameterMm":6.0,"stepDownMm":2.0,"stepOverMm":1.5,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"safeZHeightMm":5.0,"stockAllowanceMm":0.5,"spindleRpm":0}"#
    let legacy = try JSONDecoder().decode(HeightfieldRoughParams.self, from: Data(legacyJSON.utf8))
    try expect(!legacy.isRestRough && legacy.previousToolDiameterMm == 0,
               "legacy paramsJSON decodes as plain rough")

    // ── 5. Persist round-trip. ─────────────────────────────────────────────
    let data = try JSONEncoder().encode(rest)
    let decoded = try JSONDecoder().decode(HeightfieldRoughParams.self, from: data)
    try expect(abs(decoded.previousToolDiameterMm - 3.5) < 1e-9 && decoded.isRestRough,
               "rest field round-trips Codable")

    print("ShopPilotVerify3DRest: PASS — rest rough cuts only valleys the previous tool missed "
          + "(width gate + header), plain rough unchanged, legacy decode safe, persist round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify3DRest: FAIL — \(error)")
    exit(1)
}
