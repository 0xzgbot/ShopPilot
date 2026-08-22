import Foundation
import ShopPilotCore

// SPK-1910a — Trochoidal slotting engine CLT (no XCTest).
// Assert groups per docs/planning/SPK-1910_TROCHOIDAL_AGENT_PROMPT.md:
//   1. Happy slot  80×8 mm, D=6.35, WOC=0.8 → looping XY, Z reaches −depth
//   2. Too narrow  80×5 mm, same D → isTooNarrow, no cut G1/G2/G3
//   3. Monotonic   smaller WOC → more loops on the same slot
//   4. Z passes    depth=4, maxDOC=2 → exactly 2 passes
//   5. Direction   climb vs conventional → G3 vs G2 winding differs
//   6. Codable     round-trip + decode {} and partial JSON to defaults
//   7. Safety      no M6 / no G28; M3 only when rpm > 0
//   8. Determinism two computes → identical [String]
// Engagement: peak sampled estimate < toolDiameter (documented estimator).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeSlotRect(lengthMm: Double, widthMm: Double, x0: Double = 10, y0: Double = 10) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x0, y: y0),
            VectorPoint(x: x0 + lengthMm, y: y0),
            VectorPoint(x: x0 + lengthMm, y: y0 + widthMm),
            VectorPoint(x: x0, y: y0 + widthMm),
            VectorPoint(x: x0, y: y0),
        ],
        isClosed: true
    )
}

let cutLines = { (lines: [String]) in lines.filter { $0.hasPrefix("G1 ") || $0.hasPrefix("G2") || $0.hasPrefix("G3") } }

func main() throws {
    // ── 1. Happy slot: looping XY at depth. ────────────────────────────────
    let params = TrochoidSlotParams(
        toolDiameterMm: 6.35,
        cutDepthMm: 4.0,
        startDepthMm: 0.0,
        maxDepthOfCutMm: 2.0,
        maxWocMm: 0.8,
        loopPitchMm: 0.6,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        safetyHeightMm: 5.0,
        spindleRpm: 0,
        cutDirection: .climb,
        rampEntry: true
    )
    let happy = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: params
    )
    try expect(happy.errors.isEmpty, "happy slot has no validation errors")
    try expect(!happy.isTooNarrow, "80×8 mm slot with D=6.35 is not too narrow")
    try expect(happy.gcodeLines.count > 20, "gcodeLines ≫ header (got \(happy.gcodeLines.count))")
    try expect(cutLines(happy.gcodeLines).count > 10, "looping cut moves present")
    try expect(happy.gcodeLines.contains { $0.hasPrefix("G3 ") }, "climb emits G3 arcs")
    try expect(happy.gcodeLines.contains { $0.contains("Z-4.000") },
               "Z reaches final depth −4.000")
    try expect(happy.loopCount > 0, "loops counted")
    // Peak sampled radial engagement < tool diameter.
    try expect(happy.peakRadialEngagementMm < params.toolDiameterMm,
               "peak radial engagement \(happy.peakRadialEngagementMm) < D \(params.toolDiameterMm)")

    // ── 2. Too narrow: 80×5 mm, D=6.35. ────────────────────────────────────
    let narrow = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 5)],
        params: params
    )
    try expect(narrow.isTooNarrow, "80×5 mm slot with D=6.35 is too narrow")
    try expect(cutLines(narrow.gcodeLines).isEmpty,
               "too-narrow result has zero G1/G2/G3 cut moves")
    try expect(narrow.gcodeLines.contains("O=TROCHOID_SLOT"), "header still present")

    // ── 3. WOC monotonicity: smaller WOC → more loops. ─────────────────────
    var fineWOC = params
    fineWOC.maxWocMm = 0.4
    let fine = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: fineWOC
    )
    try expect(fine.loopCount > happy.loopCount,
               "smaller WOC → more loops (\(fine.loopCount) > \(happy.loopCount))")
    try expectClose(fine.peakRadialEngagementMm, 0.8, "estimator tracks effPitch = min(pitch, WOC)",
                    tolerance: 1e-9)

    // ── 4. Z step-down: depth 4, DOC 2 → 2 passes. ──────────────────────────
    try expect(happy.passCount == 2, "depth 4 / DOC 2 → 2 passes (got \(happy.passCount))")
    try expect(happy.gcodeLines.contains { $0.contains("(Trochoid Pass 1/2") } &&
               happy.gcodeLines.contains { $0.contains("(Trochoid Pass 2/2") },
               "both pass markers present")

    // ── 5. Climb vs conventional winding differs. ──────────────────────────
    var conv = params
    conv.cutDirection = .conventional
    let convResult = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: conv
    )
    try expect(convResult.gcodeLines.contains { $0.hasPrefix("G2 ") }, "conventional emits G2")
    try expect(!convResult.gcodeLines.contains { $0.hasPrefix("G3 ") },
               "conventional emits no G3")

    // ── 6. Codable round-trip + default/partial decode. ────────────────────
    let encoded = try JSONEncoder().encode(params)
    let decoded = try JSONDecoder().decode(TrochoidSlotParams.self, from: encoded)
    try expect(decoded == params, "TrochoidSlotParams round-trips")
    let empty = try JSONDecoder().decode(TrochoidSlotParams.self, from: Data("{}".utf8))
    try expect(empty == TrochoidSlotParams(), "decode {} → all defaults")
    let partialJSON = """
    {"maxWocMm":0.3,"spindleRpm":12000}
    """
    let partial = try JSONDecoder().decode(TrochoidSlotParams.self, from: Data(partialJSON.utf8))
    try expect(partial.maxWocMm == 0.3 && partial.spindleRpm == 12000 &&
               partial.toolDiameterMm == 6.0 && partial.rampEntry == true,
               "partial JSON merges with defaults")

    // Validation errors → empty gcode.
    var bad = params
    bad.maxWocMm = 7.0 // >= toolDiameter
    let badResult = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: bad
    )
    try expect(!badResult.isValid && badResult.errors.count == 1, "WOC ≥ D rejected with error")
    try expect(badResult.gcodeLines.isEmpty, "invalid params → empty gcode")

    // ── 7. Safety hygiene. ─────────────────────────────────────────────────
    for g in happy.gcodeLines {
        try expect(!g.contains("M6"), "no M6 anywhere")
        try expect(!g.contains("G28"), "no G28 anywhere")
    }
    try expect(!happy.gcodeLines.contains { $0.hasPrefix("M3 ") },
               "rpm=0 → no M3 emitted")
    var spun = params
    spun.spindleRpm = 18000
    let spunResult = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: spun
    )
    try expect(spunResult.gcodeLines.contains { $0 == "M3 S18000" },
               "rpm>0 → M3 S18000 present")

    // ── 8. Determinism. ────────────────────────────────────────────────────
    let again = TrochoidSlotToolpathEngine.compute(
        vectors: [makeSlotRect(lengthMm: 80, widthMm: 8)],
        params: params
    )
    try expect(again.gcodeLines == happy.gcodeLines, "two computes are byte-identical")

    print("ShopPilotVerify1910a: PASS — trochoid slot engine "
        + "(\(happy.loopCount) loops × \(happy.passCount) passes, "
        + "peak engagement \(String(format: "%.2f", happy.peakRadialEngagementMm)) mm < D)")
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

do {
    try main()
} catch {
    print("ShopPilotVerify1910a: FAIL — \(error)")
    exit(1)
}
