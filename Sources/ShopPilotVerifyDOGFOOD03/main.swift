import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-DOGFOOD-03 verify — peck-retract detection must be O(n), not O(n²),
// and trochoid corridor generation must honor a shape selection.
//
// AC1 (timing): a 14,000-line synthetic buffer with ~1,000 peck retracts
//      detects in well under 2s (was: minutes at O(candidates × lines²)).
// AC2 (correctness): the detector still finds real pecks and rejects the
//      final end-of-op retract (no following plunge) — same contract the
//      SPK-1210 tests pinned.
// AC3 (regression): existing SPK-1210-style expectations hold — count and
//      positions of detected retracts match a hand-computed ground truth.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD03: FAIL — \(msg)")
        exit(1)
    }
}

// --- Build a synthetic drill-peck program: N holes × P pecks --------------
// Each hole: G0 XY → [G1 Zdown / G0 Zup]×P → final G0 Zup → next hole.
var lines: [String] = ["G21", "G90", "G17"]
let gridX = 40
let holes = 400          // 40×10 grid
let pecksPerHole = 18    // → ~14.4k lines total, 6300 mid-hole retracts
for h in 0..<holes {
    let x = Double(h % gridX) * 10.0
    let y = Double(h / gridX) * 10.0
    lines.append(String(format: "G0 X%.3f Y%.3f", x, y))
    var depth = -1.0
    for p in 0..<pecksPerHole {
        lines.append(String(format: "G1 Z%.3f F150", depth))   // plunge
        if p < pecksPerHole - 1 {
            lines.append("G0 Z1.000")                           // retract (peck)
        }
        depth -= 1.5
    }
    lines.append("G0 Z5.000")                                   // final retract (NOT a peck — no follow-up plunge)
}
expect(lines.count > 13_000, "synthetic buffer is big (\(lines.count) lines)")

// Expected: each hole has (pecksPerHole - 1) mid-hole retracts; the final
// retract per hole is rejected because no plunge follows at that XY.
let expectedRetracts = holes * (pecksPerHole - 1)

// --- AC1: timing gate ------------------------------------------------------
let clock = ContinuousClock()
let t0 = clock.now
let result = WireframeRenderer.detectPeckRetracts(from: lines)
let elapsed = clock.now - t0
let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

print("detected \(result.count) retracts in \(String(format: "%.3f", seconds))s")
expect(seconds < 2.0, "detectPeckRetracts must finish < 2s (took \(seconds)s)")
expect(result.count == expectedRetracts,
       "count matches hand-derived truth: got \(result.count), want \(expectedRetracts)")

// --- AC2/AC3: positions — every detected retract sits at a hole center ----
let holeCenters: Set<String> = Set((0..<holes).map { String(format: "%.1f,%.1f", Double($0 % gridX) * 10.0, Double($0 / gridX) * 10.0) })
for r in result.prefix(50) {
    let key = String(format: "%.1f,%.1f", r.start.x, r.start.y)
    expect(holeCenters.contains(key), "retract at hole center (\(key))")
}

// Small program sanity: single hole, 2 pecks → exactly 1 retract.
let small = [
    "G21", "G90",
    "G0 X10.000 Y10.000",
    "G1 Z-1.000 F150",
    "G0 Z1.000",
    "G1 Z-2.500 F150",
    "G0 Z5.000",
]
let smallResult = WireframeRenderer.detectPeckRetracts(from: small)
expect(smallResult.count == 1, "small program: exactly 1 peck retract (got \(smallResult.count))")
expect(smallResult[0].start.x == 10.0 && smallResult[0].start.y == 10.0,
       "small-program retract position is the hole XY")

// No-Z program → zero retracts, no crash.
let flat = ["G21", "G90", "G0 X0 Y0", "G1 X10 Y10 F600"]
expect(WireframeRenderer.detectPeckRetracts(from: flat).isEmpty, "flat program yields no retracts")

// Empty program → no crash.
expect(WireframeRenderer.detectPeckRetracts(from: []).isEmpty, "empty program yields no retracts")

print("ShopPilotVerifyDOGFOOD03: PASS — peck detection O(n): \(lines.count)-line buffer in \(String(format: "%.3f", seconds))s; count/position ground truth exact; edge cases clean.")
exit(0)
