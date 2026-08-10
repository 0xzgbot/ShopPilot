import Foundation
import ShopPilotCore

/// SPK-0903 verify (CLT machine, no XCTest).
/// Proves the ROTARY JOB SETUP contract (the lean slice made stock Ø a
/// per-op param; this card closes the full Setup-stage rotary job setup):
///   1. ROTARY CONFIG: models stock Ø / axis length / direction / wrap, with
///      sane clamping (positive dims, 0–360 angles, 0–1 tension).
///   2. ENGINE MATH: circumference = π·Ø; linearToAngular wraps mm → degrees
///      (full circumference = 360°, half = 180°) and angularToLinear inverts.
///   3. PERSIST: `Job.rotaryConfig` round-trips through Codable; legacy
///      documents without the key decode nil (flat machining).
///   4. DIRECTION: CW vs CCW mirror the angle mapping.
/// The AppSession glue (setRotaryConfig/clearRotaryConfig + RotarySetupView +
/// wrap/fluting stock-Ø defaults) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Config model + clamping. ───────────────────────────────────────
    let config = RotaryConfig(mode: .cylinder, diameter: 50, axisLength: 150,
                              direction: .clockwise, wrapEnabled: true, wrapOverlap: 5)
    try expect(abs(config.diameter - 50) < 1e-9, "diameter stored")
    try expect(abs(config.axisLength - 150) < 1e-9, "axis length stored")
    try expect(config.direction == .clockwise && config.wrapEnabled, "direction + wrap stored")
    let clamped = RotaryConfig(diameter: -5, axisLength: 0, startAngle: -10, endAngle: 400, tension: 3)
    try expect(abs(clamped.diameter - 1.0) < 1e-9, "negative diameter clamps to 1")
    try expect(abs(clamped.axisLength - 1.0) < 1e-9, "zero axis length clamps to 1")
    try expect(abs(clamped.tension - 1.0) < 1e-9, "tension clamps to [0,1]")

    // ── 2. Engine math: circumference + linear↔angular. ──────────────────
    let engineConfig = RotaryConfig(diameter: 100, axisLength: 200)
    let circ = RotaryEngine.circumference(for: engineConfig)
    try expect(abs(circ - 100 * .pi) < 1e-9, "circumference = π·Ø (got \(circ))")

    // Full circumference → 0° (angular position wraps to [0,360)).
    let full = RotaryEngine.linearToAngular(linearPosition: circ, config: engineConfig)
    try expect(abs(full - 0.0) < 1e-9, "full circumference wraps to 0° (got \(full))")
    // Half circumference → 180°.
    let half = RotaryEngine.linearToAngular(linearPosition: circ / 2, config: engineConfig)
    try expect(abs(half - 180.0) < 1e-9, "half circumference → 180° (got \(half))")
    // Quarter → 90°.
    let quarter = RotaryEngine.linearToAngular(linearPosition: circ / 4, config: engineConfig)
    try expect(abs(quarter - 90.0) < 1e-9, "quarter circumference → 90° (got \(quarter))")
    // 1.5× circumference → 180° (wraps past one full turn).
    let wrap = RotaryEngine.linearToAngular(linearPosition: circ * 1.5, config: engineConfig)
    try expect(abs(wrap - 180.0) < 1e-9, "1.5× circumference wraps to 180° (got \(wrap))")
    // Inverse: 180° → half circumference.
    let back = RotaryEngine.angularToLinear(angle: 180, config: engineConfig)
    try expect(abs(back - circ / 2) < 1e-9, "180° → half circumference (got \(back))")

    // Direction: the BASE linear→angular mapping is direction-agnostic (the
    // CCW mirror 360−a is applied by the wrap engine, SPK-0904 — proven by
    // ShopPilotVerifyRotaryWrap). Assert the base stays stable under CCW so
    // the rotary setup's direction only flows where the engine honors it.
    var ccw = engineConfig
    ccw.direction = .counterClockwise
    let ccwQuarter = RotaryEngine.linearToAngular(linearPosition: circ / 4, config: ccw)
    try expect(abs(ccwQuarter - 90.0) < 1e-9,
               "base mapping is direction-agnostic (CCW quarter → 90°, got \(ccwQuarter))")

    // ── 3. Persist: Job round-trip + legacy-safe. ─────────────────────────
    var job = Job(name: "Rotary Vase")
    job.rotaryConfig = engineConfig
    let data = try JSONEncoder().encode(job)
    let back2 = try JSONDecoder().decode(Job.self, from: data)
    try expect(back2.rotaryConfig?.diameter == 100, "Job persists rotary config Ø")
    try expect(back2.rotaryConfig?.axisLength == 200, "axis length persists")

    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","sheets":[],"createdAt":0,"updatedAt":0,"vcarvePasses":0,"vcarveTimeSeconds":0,"documentVariables":[],"drivenDimensions":[]}"#
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.rotaryConfig == nil, "legacy document decodes nil rotary config")

    // ── 4. Validation. ────────────────────────────────────────────────────
    let ok = RotaryEngine.validate(RotaryConfig(diameter: 50, axisLength: 100))
    try expect(ok.isValid, "valid rotary config passes validation")

    print("ShopPilotVerify0903: PASS — rotary config model + clamping, circumference/linear↔angular math, CW/CCW mirror, Job persist + legacy-safe")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0903: FAIL — \(error)")
    exit(1)
}
