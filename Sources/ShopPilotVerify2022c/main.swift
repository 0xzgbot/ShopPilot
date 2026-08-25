import Foundation
import ShopPilotCore

// SPK-2022c verify — skip-first-M6 send-time filter.
//
// AC1: with the filter ON, a fixture program carrying two M6s (the first
//      followed by a dwell) loses EXACTLY the first M6 + its dwell; the
//      second M6 is intact; the line count drops by exactly the suppressed
//      count (2).
// AC2: with the filter OFF the output is byte-identical to the input —
//      toggling off restores the full program.
// AC3: an empty program and a no-M6 program pass through unchanged with zero
//      suppression.
// AC4: a first M6 with NO following pause suppresses only the M6 line itself;
//      comment-only "M6" mentions never count as tool changes; later M6s are
//      never touched; the string-text overload agrees with the lines overload.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2022c: FAIL — \(msg)")
        exit(1)
    }
}

@MainActor
func run() async {
    // --- Fixture: two M6s, dwell directly after the first -------------------
    let fixture: [String] = [
        "G21 G90",
        "G0 Z5",
        "M6 T1",
        "G4 P2.0",
        "M3 S12000",
        "G0 X10 Y10",
        "G1 Z-1 F300",
        "M5",
        "M6 T2",
        "M3 S18000",
        "G0 X50 Y50",
        "G1 Z-2 F300",
        "M5",
        "M30",
    ]

    // AC1: filter ON — exactly the first M6 + its dwell vanish.
    let on = SendTimeM6Filter.apply(fixture, skipEnabled: true)
    expect(on.suppressedCount == 2, "exactly 2 lines suppressed (got \(on.suppressedCount))")
    expect(on.lines.count == fixture.count - on.suppressedCount,
           "line count drops by exactly the suppressed count (\(fixture.count) → \(on.lines.count), suppressed \(on.suppressedCount))")
    expect(!on.lines.contains("M6 T1"), "first M6 (M6 T1) gone")
    expect(!on.lines.contains("G4 P2.0"), "the dwell that followed the first M6 gone")
    expect(on.lines.contains("M6 T2"), "second M6 (M6 T2) intact")
    expect(on.lines.first == fixture.first, "program still opens with its original first line")
    expect(on.lines.last == fixture.last, "program still ends with its original last line")

    // The surviving program is the input minus exactly those two lines, in order.
    let expected = fixture.filter { $0 != "M6 T1" && $0 != "G4 P2.0" }
    expect(on.lines == expected, "output is the input minus exactly the first M6 + its dwell, order preserved")

    // AC2: filter OFF — byte-identical to the input.
    let off = SendTimeM6Filter.apply(fixture, skipEnabled: false)
    expect(off.lines == fixture, "filter OFF returns the full program unchanged")
    expect(off.suppressedCount == 0, "filter OFF suppresses nothing")
    // Purity: the ON pass must not have mutated the caller's array — with
    // the toggle OFF the send path streams this same untouched buffer.
    expect(fixture.contains("M6 T1") && fixture.contains("G4 P2.0") && fixture.contains("M6 T2"),
           "input program untouched by the ON pass — OFF restores the full send")

    // String overload agrees.
    let textIn = fixture.joined(separator: "\n") + "\n"
    let textOn = SendTimeM6Filter.apply(textIn, skipEnabled: true)
    expect(textOn.suppressedCount == 2, "string overload reports 2 suppressed")
    expect(textOn.text == on.lines.joined(separator: "\n") + "\n",
           "string output matches lines output")
    let textOff = SendTimeM6Filter.apply(textIn, skipEnabled: false)
    expect(textOff.text == textIn && textOff.suppressedCount == 0,
           "string overload OFF is byte-identical to the input")

    // AC3: empty / no-M6 programs unchanged.
    let emptyOn = SendTimeM6Filter.apply([String](), skipEnabled: true)
    expect(emptyOn.lines.isEmpty && emptyOn.suppressedCount == 0, "empty program unchanged")
    let noM6: [String] = ["G21 G90", "G0 X0 Y0", "G1 Z-1 F300", "M30"]
    let noM6On = SendTimeM6Filter.apply(noM6, skipEnabled: true)
    expect(noM6On.lines == noM6 && noM6On.suppressedCount == 0, "no-M6 program unchanged")

    // AC4a: first M6 with NO following pause → only the M6 line suppressed.
    let noDwell: [String] = [
        "G21 G90",
        "M6 T1",
        "M3 S12000",
        "M6 T2",
        "M30",
    ]
    let noDwellOn = SendTimeM6Filter.apply(noDwell, skipEnabled: true)
    expect(noDwellOn.suppressedCount == 1, "no-dwell first M6 suppresses only itself (got \(noDwellOn.suppressedCount))")
    expect(noDwellOn.lines == ["G21 G90", "M3 S12000", "M6 T2", "M30"],
           "second M6 survives when the first had no dwell")

    // AC4b: pause two lines after the M6 (within window) is caught…
    let gapFixture: [String] = ["M6 T1", "(comment)", "M0", "G0 X1"]
    let gapOn = SendTimeM6Filter.apply(gapFixture, skipEnabled: true)
    expect(gapOn.suppressedCount == 2 && !gapOn.lines.contains("M0"),
           "pause one line past a comment still counts as directly-following (suppressed \(gapOn.suppressedCount))")

    // …but a pause three lines out is NOT part of the suppression.
    let tooFar: [String] = ["M6 T1", "M3 S12000", "G0 X0", "M0", "M30"]
    let tooFarOn = SendTimeM6Filter.apply(tooFar, skipEnabled: true)
    expect(tooFarOn.suppressedCount == 1 && tooFarOn.lines.contains("M0"),
           "pause beyond the 1–2 line window passes through untouched")

    // AC4c: comment-only M6 mentions are not tool changes.
    let commented: [String] = [
        "(M6 T7 loads next)",
        "; M6 here would pause",
        "M3 S12000",
        "M6 T2",
        "M30",
    ]
    let commentedOn = SendTimeM6Filter.apply(commented, skipEnabled: true)
    expect(commentedOn.suppressedCount == 1 && !commentedOn.lines.contains("M6 T2"),
           "comment 'M6' mentions don't count; the real M6 T2 is the first change… suppressed once")
    expect(commentedOn.lines == ["(M6 T7 loads next)", "; M6 here would pause", "M3 S12000", "M30"],
           "only the active M6 line vanished; comments untouched")

    // AC4d: M06 spelling and other M-codes classified correctly.
    expect(SendTimeM6Filter.isToolChange("M06 T3"), "M06 spelling counts as a tool change")
    expect(!SendTimeM6Filter.isToolChange("M60 P1"), "M60 is not M6")
    expect(!SendTimeM6Filter.isToolChange("M16"), "M16 is not M6")
    expect(!SendTimeM6Filter.isToolChange("M3 S12000"), "M3 is not M6")
    expect(SendTimeM6Filter.isPauseOrDwell("M00"), "M00 counts as pause")
    expect(SendTimeM6Filter.isPauseOrDwell("M01"), "M01 counts as pause")
    expect(SendTimeM6Filter.isPauseOrDwell("G04 P500"), "G04 counts as dwell")
    expect(!SendTimeM6Filter.isPauseOrDwell("G41 D1"), "G41 cutter comp is not G4")

    print("ShopPilotVerify2022c: PASS — send-time filter suppresses EXACTLY the first M6 + its immediate dwell, second M6 intact, OFF restores the program byte-for-byte, empty/no-M6 programs unchanged.")
    exit(0)
}

Task { @MainActor in
    await run()
}
RunLoop.main.run()
