import Foundation
@testable import ShopPilotCore

// MARK: - ShopPilotVerify1102i
//
// Verifies SPK-1102i: peck-drill params produce multiple Z plunge/retract
// lines in the generated G-code — one plunge (G1 Z-…) per peck, a retract
// (G0 Z+…) after every non-final peck, and an exact final plunge to the
// point's full depth. Also proves the zero-peck-depth edge case no longer
// divides by zero (falls back to a single pass).

func assert(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
    print("PASS: \(message)")
}

// Runs the engine for a single point and returns the raw gcode lines.
func drillLines(zDepth: Double, cycle: DrillCycleType, peckDepth: Double) -> [String] {
    let params = DrillToolpathParams(
        cycleType: cycle,
        feedRateMmPerMin: 1000,
        plungeFeedRateMmPerMin: 300,
        retractHeightMm: 5.0,
        peckDepthMm: peckDepth,
        toolDiameterMm: 6.0,
        safetyHeightMm: 10.0
    )
    let result = DrillToolpathEngine.compute(
        points: [DrillPoint(x: 10, y: 10, zDepthMm: zDepth)],
        params: params,
        material: nil,
        stockHeightMm: 25.0
    )
    return result.gcodeLines
}

// The peck cycle proper: from the first plunge through the final plunge
// (positioning rapids and the post-cycle safety rapid are excluded).
func cycleLines(_ lines: [String]) -> [String] {
    guard let first = lines.firstIndex(where: { $0.hasPrefix("G1 Z") }),
          let last = lines.lastIndex(where: { $0.hasPrefix("G1 Z") })
    else { return [] }
    return Array(lines[first...last])
}

let plunge = { (lines: [String]) in lines.filter { $0.hasPrefix("G1 Z") } }
let retract = { (lines: [String]) in lines.filter { $0.hasPrefix("G0 Z") } }

// ── Test 1: peckDrill, 10mm deep, 2mm peck → 5 plunges + 4 retracts ─────────
let t1 = drillLines(zDepth: -10, cycle: .peckDrill, peckDepth: 2.0)
let t1Cycle = cycleLines(t1)
let expectedT1 = [
    "G1 Z-2.000 F300",
    "G0 Z5.0",
    "G1 Z-4.000 F300",
    "G0 Z5.0",
    "G1 Z-6.000 F300",
    "G0 Z5.0",
    "G1 Z-8.000 F300",
    "G0 Z5.0",
    "G1 Z-10.000 F300",
]
assert(t1Cycle == expectedT1,
       "peckDrill 10mm/2mm emits 5 plunges interleaved with 4 retracts (got: \(t1Cycle))")
assert(plunge(t1).count == 5, "10mm/2mm produces 5 plunge lines")
assert(retract(t1Cycle).count == 4, "10mm/2mm peck cycle produces 4 retract lines (all at retractHeight 5.0)")
assert(retract(t1Cycle).allSatisfy { $0 == "G0 Z5.0" },
       "peckDrill retracts to retractHeight, not safety height")
assert(t1Cycle.last == "G1 Z-10.000 F300", "final plunge lands exactly on the point's depth")

// ── Test 2: non-divisible depth 5mm / 2mm peck → 3 plunges, exact final ─────
let t2 = drillLines(zDepth: -5, cycle: .peckDrill, peckDepth: 2.0)
let expectedT2 = [
    "G1 Z-2.000 F300",
    "G0 Z5.0",
    "G1 Z-4.000 F300",
    "G0 Z5.0",
    "G1 Z-5.000 F300",
]
assert(cycleLines(t2) == expectedT2,
       "5mm/2mm yields 2 intermediate pecks + exact final plunge to -5.000 (got: \(cycleLines(t2)))")

// ── Test 3: shallow hole (depth < peck depth) → single exact plunge ─────────
let t3 = drillLines(zDepth: -1, cycle: .peckDrill, peckDepth: 2.0)
assert(cycleLines(t3) == ["G1 Z-1.000 F300"],
       "hole shallower than one peck still plunges exactly to depth (got: \(cycleLines(t3)))")

// ── Test 4: deepHolePeck retracts to safety height, same peck cadence ───────
let t4 = drillLines(zDepth: -10, cycle: .deepHolePeck, peckDepth: 2.0)
let expectedT4 = [
    "G1 Z-2.000 F300",
    "G0 Z10.0",
    "G1 Z-4.000 F300",
    "G0 Z10.0",
    "G1 Z-6.000 F300",
    "G0 Z10.0",
    "G1 Z-8.000 F300",
    "G0 Z10.0",
    "G1 Z-10.000 F300",
]
assert(cycleLines(t4) == expectedT4,
       "deepHolePeck emits 5 plunges + 4 full retracts to safety height (got: \(cycleLines(t4)))")

// ── Test 5: zero peck depth must not divide by zero (single-pass fallback) ──
let t5 = drillLines(zDepth: -10, cycle: .peckDrill, peckDepth: 0.0)
assert(cycleLines(t5) == ["G1 Z-10.000 F300"],
       "peckDepth 0 falls back to a single exact plunge instead of trapping (got: \(cycleLines(t5)))")

// ── Test 6: every point in a multi-point job gets its own peck sequence ─────
let params6 = DrillToolpathParams(
    cycleType: .peckDrill,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    retractHeightMm: 5.0,
    peckDepthMm: 2.0,
    toolDiameterMm: 6.0,
    safetyHeightMm: 10.0
)
let result6 = DrillToolpathEngine.compute(
    points: [
        DrillPoint(x: 0, y: 0, zDepthMm: -6),
        DrillPoint(x: 20, y: 0, zDepthMm: -6),
    ],
    params: params6,
    material: nil,
    stockHeightMm: 25.0
)
let t6Plunges = plunge(result6.gcodeLines)
assert(t6Plunges.count == 6, "two 6mm holes at 2mm peck → 6 plunges total (got \(t6Plunges.count))")
assert(t6Plunges.filter { $0 == "G1 Z-6.000 F300" }.count == 2,
       "each point ends with its own exact final plunge")

print("\nAll checks passed.")
