import Foundation
import ShopPilotCore

/// SPK-1302 verify (CLT machine, no XCTest).
/// Proves the FEED-RATE OVERRIDE + SPINDLE COMMAND models (pure math/string):
///   1. FeedRateOverride clamps multiplier to [0.1, 2.0]; default is 1.0.
///   2. scaled() = feed × multiplier, never below 1.
///   3. gcode() emits the GRBL F word (rounded integer).
///   4. SpindleCommand.on/off/setRpm emit "M3 S<rpm>" / "M5" / "S<rpm>",
///      clamping rpm to 1000...30000 and rounding (not truncating).
///   5. validRpm exposes the clamped value.
/// The streamer wiring lives in the app; this model stays I/O-free.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Multiplier clamping. ────────────────────────────────────────────
    try expect(FeedRateOverride(multiplier: 2.5).multiplier == 2.0,
               "init(2.5) clamps to 2.0 (got \(FeedRateOverride(multiplier: 2.5).multiplier))")
    try expect(FeedRateOverride(multiplier: 0.05).multiplier == 0.1,
               "init(0.05) clamps to 0.1 (got \(FeedRateOverride(multiplier: 0.05).multiplier))")
    try expect(FeedRateOverride().multiplier == 1.0,
               "init() defaults to 1.0 (got \(FeedRateOverride().multiplier))")

    // ── 2. scaled(). ───────────────────────────────────────────────────────
    try expect(FeedRateOverride(multiplier: 1.25).scaled(400) == 500,
               "400 × 1.25 = 500 (got \(FeedRateOverride(multiplier: 1.25).scaled(400)))")
    try expect(FeedRateOverride(multiplier: 0.5).scaled(400) == 200,
               "400 × 0.5 = 200 (got \(FeedRateOverride(multiplier: 0.5).scaled(400)))")
    try expect(FeedRateOverride(multiplier: 0.1).scaled(5) == 1,
               "scaled clamps to >= 1 (got \(FeedRateOverride(multiplier: 0.1).scaled(5)))")

    // ── 3. gcode(). ────────────────────────────────────────────────────────
    try expect(FeedRateOverride(multiplier: 1.25).gcode(feed: 400) == "F500",
               "gcode 1.25×400 = F500 (got \(FeedRateOverride(multiplier: 1.25).gcode(feed: 400)))")
    try expect(FeedRateOverride(multiplier: 0.5).gcode(feed: 400) == "F200",
               "gcode 0.5×400 = F200 (got \(FeedRateOverride(multiplier: 0.5).gcode(feed: 400)))")

    // ── 4. Spindle commands. ───────────────────────────────────────────────
    try expect(SpindleCommand.on(rpm: 12000) == "M3 S12000",
               "on(12000) = M3 S12000 (got \(SpindleCommand.on(rpm: 12000)))")
    try expect(SpindleCommand.on(rpm: 500) == "M3 S1000",
               "on(500) clamps to M3 S1000 (got \(SpindleCommand.on(rpm: 500)))")
    try expect(SpindleCommand.on(rpm: 99999) == "M3 S30000",
               "on(99999) clamps to M3 S30000 (got \(SpindleCommand.on(rpm: 99999)))")
    try expect(SpindleCommand.off() == "M5",
               "off() = M5 (got \(SpindleCommand.off()))")
    try expect(SpindleCommand.setRpm(24000) == "S24000",
               "setRpm(24000) = S24000 (got \(SpindleCommand.setRpm(24000)))")
    try expect(SpindleCommand.on(rpm: 12345.6) == "M3 S12346",
               "on(12345.6) rounds to M3 S12346 (got \(SpindleCommand.on(rpm: 12345.6)))")

    // ── 5. validRpm. ───────────────────────────────────────────────────────
    try expect(SpindleCommand.validRpm(0) == 1000,
               "validRpm(0) = 1000 (got \(SpindleCommand.validRpm(0)))")
    try expect(SpindleCommand.validRpm(50000) == 30000,
               "validRpm(50000) = 30000 (got \(SpindleCommand.validRpm(50000)))")
    try expect(SpindleCommand.validRpm(18000) == 18000,
               "validRpm(18000) = 18000 (got \(SpindleCommand.validRpm(18000)))")

    print("ShopPilotVerify1302: PASS — feed-rate override clamp/scaled/F-word, spindle on/off/setRpm clamp + round")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1302: FAIL — \(error)")
    exit(1)
}
