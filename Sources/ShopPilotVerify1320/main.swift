import Foundation
import ShopPilotCore

/// SPK-1320 verify (CLT machine, no XCTest).
/// Proves the ACCELERATION-AWARE TIME ESTIMATION contract:
///   1. TRAPEZOID: 100mm @ 6000mm/min (v=100mm/s), accel 1000 → accel 0.1s
///      (5mm) + cruise 0.9s (90mm) + decel 0.1s (5mm) = 1.1s.
///   2. TRIANGLE: 2mm @ v=100mm/s, accel 1000 → never reaches v;
///      t = 2·sqrt(d/a) ≈ 0.089s.
///   3. GUARDS: distance 0 and negative → 0 seconds.
///   4. ESTIMATE: G0 X50 (travel) + G1 X100 + G1 X150 (cut) → travel > 0,
///      cutting > 0, total == travel + cutting, total > 0.
///   5. MALFORMED: garbage/empty/M30 lines mixed in → skipped, no crash,
///      identical totals.
///   6. ACCEL-AWARE BEATS NAIVE: the same move at low accel takes LONGER
///      than at high accel, and longer than the constant-speed estimate.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double) throws {
    if abs(a - b) > tolerance {
        throw VerifyError.failed("\(msg) (got \(a), expected \(b) ± \(tolerance))")
    }
}

func main() throws {
    // ── 1. Trapezoid profile (reaches vMax, cruises). ─────────────────────
    let trapezoid = AccelTimeEstimator.moveTime(
        distanceMm: 100, feedRateMmPerMin: 6000, accelMmPerSec2: 1000, decelMmPerSec2: 1000
    )
    // v = 100 mm/s; tAccel = tDecel = 0.1s over 5mm each; cruise 90mm @ 100 = 0.9s.
    try expectClose(trapezoid, 1.1, "trapezoid 100mm @ v=100 accel=1000 ≈ 1.1s", tolerance: 0.05)

    // ── 2. Triangle profile (never reaches vMax). ─────────────────────────
    let triangle = AccelTimeEstimator.moveTime(
        distanceMm: 2, feedRateMmPerMin: 6000, accelMmPerSec2: 1000, decelMmPerSec2: 1000
    )
    let expectedTriangle = 2 * (2.0 / 1000.0).squareRoot()  // ≈ 0.0894s
    try expectClose(triangle, expectedTriangle, "triangle 2mm ≈ 2·sqrt(d/a) ≈ 0.089s", tolerance: 0.01)
    try expect(triangle > 0.08, "triangle time is nonzero and sane (got \(triangle))")

    // ── 3. Zero / negative distance guards. ───────────────────────────────
    try expect(
        AccelTimeEstimator.moveTime(distanceMm: 0, feedRateMmPerMin: 6000, accelMmPerSec2: 1000, decelMmPerSec2: 1000) == 0,
        "distance 0 → 0 seconds"
    )
    try expect(
        AccelTimeEstimator.moveTime(distanceMm: -5, feedRateMmPerMin: 6000, accelMmPerSec2: 1000, decelMmPerSec2: 1000) == 0,
        "negative distance → 0 seconds"
    )

    // ── 4. estimate(): G0 travel + G1 cutting split. ──────────────────────
    let program = ["G0 X50", "G1 X100", "G1 X150"]
    let est = AccelTimeEstimator.estimate(gcodeLines: program, feedRateMmPerMin: 6000)
    try expect(est.travelTimeSeconds > 0, "G0 X50 counts as travel (got \(est.travelTimeSeconds))")
    try expect(est.cuttingTimeSeconds > 0, "G1 moves count as cutting (got \(est.cuttingTimeSeconds))")
    try expect(est.totalTimeSeconds == est.travelTimeSeconds + est.cuttingTimeSeconds, "total == travel + cutting")
    try expect(est.totalTimeSeconds > 0, "total time > 0 (got \(est.totalTimeSeconds))")

    // ── 5. Malformed lines are skipped, never crash. ──────────────────────
    let messy = ["garbage", "", "M30", "(comment)", "%", "G0 X50", "G1 X100", "G1 X150", "F6000"]
    let messyEst = AccelTimeEstimator.estimate(gcodeLines: messy, feedRateMmPerMin: 6000)
    try expect(messyEst.totalTimeSeconds.isFinite && messyEst.totalTimeSeconds > 0, "malformed mix still yields a valid total")
    try expect(messyEst.travelTimeSeconds == est.travelTimeSeconds, "malformed lines skipped → travel matches clean program")
    try expect(messyEst.cuttingTimeSeconds == est.cuttingTimeSeconds, "malformed lines skipped → cutting matches clean program")
    try expect(messyEst.totalTimeSeconds == est.totalTimeSeconds, "malformed lines skipped → total matches clean program")

    // ── 6. Accel-aware beats naive constant-speed. ────────────────────────
    let lowAccel = AccelTimeEstimator.moveTime(distanceMm: 50, feedRateMmPerMin: 6000, accelMmPerSec2: 50, decelMmPerSec2: 50)
    let highAccel = AccelTimeEstimator.moveTime(distanceMm: 50, feedRateMmPerMin: 6000, accelMmPerSec2: 5000, decelMmPerSec2: 5000)
    let naive = 50.0 / (6000.0 / 60.0)  // 0.5s constant-speed
    try expect(lowAccel > highAccel, "same move at accel 50 takes longer than at accel 5000 (\(lowAccel) > \(highAccel))")
    try expect(lowAccel > naive, "accel-aware (2.0s) beats naive constant-speed (0.5s): \(lowAccel) > \(naive)")

    // ── 7. Profile clamping + grblDefault. ────────────────────────────────
    let clamped = MachineAccelProfile(name: "clamped", accelMmPerSec2: 1, decelMmPerSec2: 99999, rapidAccelMmPerSec2: -7)
    try expect(clamped.accelMmPerSec2 == 10, "accel clamps to floor 10 (got \(clamped.accelMmPerSec2))")
    try expect(clamped.decelMmPerSec2 == 10000, "decel clamps to ceiling 10000 (got \(clamped.decelMmPerSec2))")
    try expect(clamped.rapidAccelMmPerSec2 == 10, "rapid clamps to floor 10 (got \(clamped.rapidAccelMmPerSec2))")
    try expect(MachineAccelProfile.grblDefault.name == "GRBL Default", "grblDefault name")
    try expect(MachineAccelProfile.grblDefault.accelMmPerSec2 == 300
               && MachineAccelProfile.grblDefault.decelMmPerSec2 == 300
               && MachineAccelProfile.grblDefault.rapidAccelMmPerSec2 == 500,
               "grblDefault accel values 300/300/500")

    // ── 8. Codable round-trip. ────────────────────────────────────────────
    let data = try JSONEncoder().encode(MachineAccelProfile.grblDefault)
    let decoded = try JSONDecoder().decode(MachineAccelProfile.self, from: data)
    try expect(decoded == MachineAccelProfile.grblDefault, "Codable round-trip preserves the profile")

    print("ShopPilotVerify1320: PASS — trapezoid + triangle moveTime, zero/negative guards, G-code travel/cut estimate, malformed-line tolerance, accel-aware beats naive")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1320: FAIL — \(error)")
    exit(1)
}
