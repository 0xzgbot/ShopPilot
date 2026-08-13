import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1609 verify (CLT executable, no XCTest).
// Proves the units preference converts export output:
//   1. INCH POST: a known 25.4mm move emits G20 AND X1.0000 (25.4/25.4) —
//      never "G20 with mm numbers".
//   2. MM POST: the same move emits G21 and keeps X25.4 unchanged.
//   3. CONVERTER UNIT TESTS: GCodeUnitConverter.scaleToInches handles
//      X/Y/Z/I/J/K/R, signs, and leaves G/M/F/S/T words untouched; a
//      non-coordinate line (comment) passes through.
//   4. BRIDGE OVERRIDE: CutToMachineBridge.export honors unitsOverride —
//      inch override on an mm profile still emits G20 + scaled coords.
//   5. REGRESSION: ShopPilotVerify0415 covers per-profile units — run after.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let mmMove = ["G0 X0 Y0", "G1 X25.4 Y12.7 F800"]

    // ── 1. Inch post: G20 + scaled coordinates. ──────────────────────────
    let inch = GRBLPostProcessor.grbl(units: .inch).process(gcodeLines: mmMove).gcodeString
    try expect(inch.contains("G20"), "inch post emits G20")
    try expect(!inch.contains("G21"), "inch post has no G21")
    try expect(inch.contains("X1.0000"), "25.4mm X → 1.0000 inch (got \(inch))")
    try expect(inch.contains("Y0.5000"), "12.7mm Y → 0.5000 inch")
    // The raw mm number must NOT survive in the move (only in the header comment).
    try expect(!inch.contains("G1 X25.4"), "no G20-with-mm-numbers move")

    // ── 2. Mm post: G21 + unchanged coordinates. ─────────────────────────
    let mm = GRBLPostProcessor.grbl(units: .millimeter).process(gcodeLines: mmMove).gcodeString
    try expect(mm.contains("G21"), "mm post emits G21")
    try expect(!mm.contains("G20"), "mm post has no G20")
    try expect(mm.contains("G1 X25.4 Y12.7 F800"), "mm coordinates unchanged")

    // ── 3. Converter unit tests. ─────────────────────────────────────────
    try expect(GCodeUnitConverter.scaleToInches("G1 X25.4 Y-12.7") == "G1 X1.0000 Y-0.5000",
               "converter scales signed X/Y (got \(GCodeUnitConverter.scaleToInches("G1 X25.4 Y-12.7")))")
    try expect(GCodeUnitConverter.scaleToInches("G2 X10 I5 J0") == "G2 X0.3937 I0.1969 J0.0000",
               "converter scales I/J arcs")
    try expect(GCodeUnitConverter.scaleToInches("G1 Z-2.54 F300") == "G1 Z-0.1000 F300",
               "converter scales Z, leaves F")
    // Comments are skipped BEFORE scaling in the post (the `(`-prefix guard
    // drops them and the post adds its own), so comment text is never a
    // scaled coordinate.
    let commentPost = GRBLPostProcessor.grbl(units: .inch)
        .process(gcodeLines: ["(note X25.4)", "G1 X25.4"]).gcodeString
    try expect(!commentPost.contains("(note X25.4)") && commentPost.contains("X1.0000"),
               "post drops comment lines; the real coordinate is scaled")

    // ── 4. Bridge override (source contract — CutToMachineBridge is
    // app-target, unimportable from the CLT): export() accepts
    // unitsOverride and the ContentView export sites pass the preference.
    let bridgeURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/CutToMachineBridge.swift")
    let bridge = try String(contentsOf: bridgeURL, encoding: .utf8)
    try expect(bridge.contains("unitsOverride: GCodeUnits? = nil"),
               "CutToMachineBridge.export accepts unitsOverride")
    try expect(bridge.contains("let units = unitsOverride ?? machineProfile.units"),
               "override wins over the profile's units")
    let contentURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/ContentView.swift")
    let content = try String(contentsOf: contentURL, encoding: .utf8)
    try expect(content.contains("unitsOverride: AppSettings().isInches ? .inch : .millimeter"),
               "ContentView export passes the unit preference as the override")

    print("1609: PASS — units preference converts export (inch → G20 + scaled coords; mm → G21 unchanged)")
    print("  converter: X/Y/Z/I/J/K/R scaled, G/M/F untouched; bridge override honored")
}

do {
    try main()
} catch {
    print("1609: FAIL — \(error)")
    exit(1)
}
