import Foundation
import ShopPilotCore

/// SPK-1303 verify (CLT machine, no XCTest).
/// Proves the TOUCH-OFF / ZERO-PLATE PROBING PLANNER contract:
///   1. plan() clamps: probeSpeed 5000 → 2000, maxDepth 0.2 → 1,
///      retractHeight out-of-range → clamped, plateThickness 0 → 0.1;
///      defaults produce (120, 10, 5, plateThickness).
///   2. gcode() emits the 4-line safe probe sequence with exact strings:
///      G90 / G0 Z<retract> / G38.2 Z-<maxDepth> F<probeSpeed> / G0 Z<retract>.
///   3. Custom plan (speed 300, maxDepth 8, retract 10) → exact line 2 + 3.
///   4. zOffset(): hit at Z=-30, 3mm plate → 33; -10, 1.5 → 11.5; 0, 0.1 → 0.1.
///   5. Number formatting: no trailing ".0" anywhere in emitted G-code.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg) (got \(a), want \(b))") }
}

func main() throws {
    // ── 1. Clamping. ───────────────────────────────────────────────────────
    let clamped = TouchOff.plan(
        plateThickness: 0,
        probeSpeed: 5000,
        maxDepth: 0.2,
        retractHeight: 99
    )
    try expect(clamped.probeSpeed == 2000, "probeSpeed 5000 clamps to 2000 (got \(clamped.probeSpeed))")
    try expect(clamped.maxDepth == 1, "maxDepth 0.2 clamps to 1 (got \(clamped.maxDepth))")
    try expect(clamped.retractHeight == 50, "retractHeight 99 clamps to 50 (got \(clamped.retractHeight))")
    try expect(clamped.plateThickness == 0.1, "plateThickness 0 clamps to 0.1 (got \(clamped.plateThickness))")

    // Lower bounds hold too: tiny inputs don't go below the floor.
    let floored = TouchOff.plan(plateThickness: 5, probeSpeed: 3, maxDepth: 0.5, retractHeight: -2)
    try expect(floored.probeSpeed == 10, "probeSpeed 3 floors at 10 (got \(floored.probeSpeed))")
    try expect(floored.maxDepth == 1, "maxDepth 0.5 floors at 1 (got \(floored.maxDepth))")
    try expect(floored.retractHeight == 0, "retractHeight -2 floors at 0 (got \(floored.retractHeight))")
    try expect(floored.plateThickness == 5, "plateThickness 5 passes through unchanged")

    // Defaults.
    let defaults = TouchOff.plan(plateThickness: 6)
    try expect(defaults.probeSpeed == 120, "default probeSpeed 120 (got \(defaults.probeSpeed))")
    try expect(defaults.maxDepth == 10, "default maxDepth 10 (got \(defaults.maxDepth))")
    try expect(defaults.retractHeight == 5, "default retractHeight 5 (got \(defaults.retractHeight))")
    try expect(defaults.plateThickness == 6, "default keeps plateThickness 6")

    // ── 2. Default gcode sequence. ─────────────────────────────────────────
    let lines = TouchOff.gcode(defaults)
    try expect(lines.count == 4, "gcode emits 4 lines (got \(lines.count))")
    try expect(lines[0] == "G90", "line 0 is G90 (got \(lines[0]))")
    try expect(lines[1].hasPrefix("G0 Z"), "line 1 rapids to safe Z (got \(lines[1]))")
    try expect(lines[2].hasPrefix("G38.2 Z-"), "line 2 probes down (got \(lines[2]))")
    try expect(lines[2].contains("F120"), "line 2 uses default probe speed F120 (got \(lines[2]))")
    try expect(lines[3] == "G0 Z5", "line 3 retracts to Z5 (got \(lines[3]))")

    // ── 3. Custom plan exact lines. ────────────────────────────────────────
    let custom = TouchOff.plan(plateThickness: 1.5, probeSpeed: 300, maxDepth: 8, retractHeight: 10)
    let customLines = TouchOff.gcode(custom)
    try expect(customLines[2] == "G38.2 Z-8 F300", "custom probe line (got \(customLines[2]))")
    try expect(customLines[3] == "G0 Z10", "custom retract line (got \(customLines[3]))")

    // ── 4. G54 Z work offset. ──────────────────────────────────────────────
    try expectClose(TouchOff.zOffset(probeHitZ: -30, plateThickness: 3), 33, "hit -30, 3mm plate → 33")
    try expectClose(TouchOff.zOffset(probeHitZ: -10, plateThickness: 1.5), 11.5, "hit -10, 1.5mm plate → 11.5")
    try expectClose(TouchOff.zOffset(probeHitZ: 0, plateThickness: 0.1), 0.1, "hit 0, 0.1mm plate → 0.1")

    // ── 5. No trailing ".0" in emitted G-code. ─────────────────────────────
    let joined = TouchOff.gcode(defaults).joined(separator: "\n") + "\n" + TouchOff.gcode(custom).joined(separator: "\n")
    try expect(!joined.contains(".0"), "no \".0\" trailing zeros in gcode output")

    print("ShopPilotVerify1303: PASS — touch-off probe planner: clamping, 4-line G38.2 sequence, custom exact lines, G54 zOffset math, no trailing zeros")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1303: FAIL — \(error)")
    exit(1)
}
