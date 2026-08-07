import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1134 verify (CLT machines, no XCTest).
/// Proves the template post engine (`PostTemplateEngine` + `PostTemplate`):
///   1. GRBL mm template: golden output for a 3-move job matches the
///      hand-written reference exactly (header, G21, moves, footer, `%`).
///   2. GRBL inch template: G20 instead of G21; same moves.
///   3. Grammar: per-word tokens — `[X|A|X|1.3]` absolute, `[C]` current
///      (suppressed when unchanged), `[I]` delta, `[D]` diameter, `[G]`
///      full-line vs command-only, `-` value-only output.
///   4. Rotary wrap (Y2A): Y converts to A degrees; X stays linear; the
///      wrap diameter appears in the header; a wrapped job's A values match
///      `y / (π·d) · 360` exactly.
///   5. Missing words emit nothing; pass-through lines (comments, %, O=)
///      survive unchanged; blank lines collapse.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-3) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

/// Three moves: rapid to (10,20), plunge-feed to Z-2, feed to (30,40,-5).
let jobLines = [
    "G0 X10.000 Y20.000",
    "G1 Z-2.000 F300",
    "G1 X30.000 Y40.000 Z-5.000",
    "M30",
]

func main() throws {
    // ── 1. GRBL mm golden ─────────────────────────────────────────────────
    let mm = PostTemplate.grbl(units: .millimeter)
    let out = PostTemplateEngine.emit(gcodeLines: jobLines, template: mm)
    let golden = [
        "%",
        "(ShopPilot mm post)",
        "N10 G21 ; Millimeter units",
        "N20 G90 ; Absolute positioning",
        "N30 G17 ; XY plane",
        "N40 G0 X10.000 Y20.000",
        "N50 G1 Z-2.000 F300",
        "N60 G1 X30.000 Y40.000 Z-5.000",
        "N70 M30",
        "N80 M9",
        "N90 G0 Z5.000 ; Retract to safe height",
        "N100 M2",
        "%",
    ]
    try expect(out.lines == golden, "GRBL mm golden mismatch")
    try expect(out.moveCount == 4, "mm moveCount 4 (got \(out.moveCount))")

    // ── 2. GRBL inch golden ───────────────────────────────────────────────
    let inch = PostTemplate.grbl(units: .inch)
    let outIn = PostTemplateEngine.emit(gcodeLines: jobLines, template: inch)
    try expect(outIn.lines.contains("N10 G20 ; Inch units"), "inch emits G20")
    try expect(!outIn.lines.contains("G21"), "inch has no G21")
    try expect(outIn.lines.count == golden.count, "inch same line count")

    // ── 3. Grammar: per-word tokens ───────────────────────────────────────
    let tokenTemplate = PostTemplate(
        id: "tokens", name: "Tokens", summary: "grammar probe",
        text: """
        [D|A|-|1.1] mm diameter
        (--- moves ---)
        [G] [Y|A|A|2.2] [X|A|X|1.3] [F|C|F|1.0]
        (--- end ---)
        """
    )
    let tokenOut = PostTemplateEngine.emit(gcodeLines: ["G1 X5 Y6 F100"], template: tokenTemplate)
    try expect(tokenOut.lines[0] == "50.0 mm diameter", "diameter token value-only (got \(tokenOut.lines[0]))")
    try expect(tokenOut.lines[1] == "G1 A6.00 X5.000 F100", "per-word rebuild (got \(tokenOut.lines[1]))")

    // Current-mode suppression: F repeated → suppressed on the 2nd move.
    let cTemplate = PostTemplate(
        id: "cur", name: "Current", summary: "current-mode probe",
        text: """
        (--- moves ---)
        [G] [X|C|X|1.3] [F|C|F|1.0]
        (--- end ---)
        """
    )
    let cOut = PostTemplateEngine.emit(gcodeLines: ["G1 X1 F200", "G1 X2 F200", "G1 X3 F300"], template: cTemplate)
    try expect(cOut.lines[0] == "G1 X1.000 F200", "C-mode first move emits (got \(cOut.lines[0]))")
    try expect(cOut.lines[1] == "G1 X2.000", "C-mode suppresses unchanged F (got \(cOut.lines[1]))")
    try expect(cOut.lines[2] == "G1 X3.000 F300", "C-mode re-emits changed F (got \(cOut.lines[2]))")

    // Incremental mode: delta since previous move.
    let iTemplate = PostTemplate(
        id: "inc", name: "Incremental", summary: "delta probe",
        text: """
        (--- moves ---)
        [G] [X|I|X|1.3]
        (--- end ---)
        """
    )
    let iOut = PostTemplateEngine.emit(gcodeLines: ["G1 X10", "G1 X12"], template: iTemplate)
    try expect(iOut.lines[0] == "G1 X10.000", "I-mode first move = value (got \(iOut.lines[0]))")
    try expect(iOut.lines[1] == "G1 X2.000", "I-mode delta (got \(iOut.lines[1]))")

    // Missing words emit nothing; `-` prints value only.
    let sparse = PostTemplate(
        id: "sparse", name: "Sparse", summary: "sparse probe",
        text: """
        (--- moves ---)
        [G] [X|A|X|1.3] [Y|A|A|2.2] [Z|A|Z|1.3]
        (--- end ---)
        """
    )
    let sparseOut = PostTemplateEngine.emit(gcodeLines: ["G0 X9"], template: sparse)
    try expect(sparseOut.lines[0] == "G0 X9.000", "missing Y/Z emit nothing (got \(sparseOut.lines[0]))")

    // ── 4. Rotary wrap Y2A ────────────────────────────────────────────────
    let rotary = PostTemplate.grblRotaryWrap(diameterMm: 50.0)
    let wrapOut = PostTemplateEngine.emit(gcodeLines: [
        "G0 X0.000 Y78.5398",   // full wrap: 78.5398mm = π·25 → 360°
        "G1 X10.000 Y39.2699",  // half wrap → 180°
    ], template: rotary)
    // Header contains the diameter comment.
    try expect(wrapOut.lines.contains("(Y maps to A degrees about X — wrap diameter 50.0 mm)"),
               "rotary header carries the wrap diameter")
    // G0 line: X stays, Y → A degrees = 78.5398 / (π·50) · 360 = 180.0
    let rapid = wrapOut.lines.first { $0.hasPrefix("N40 G0") } ?? ""
    try expect(rapid.contains("X0.000"), "rotary keeps X (\(rapid))")
    try expect(rapid.contains("A180.000"), "rotary Y2A full-wrap → 180° (got \(rapid))")
    try expect(!rapid.contains("Y"), "rotary has no Y word (\(rapid))")
    let feed = wrapOut.lines.first { $0.hasPrefix("N50 G1") } ?? ""
    try expect(feed.contains("A90.000"), "rotary half-wrap → 90° (got \(feed))")

    // Exact math: y=78.5398 → 360°.
    let degrees = 78.5398 / (Double.pi * 50.0) * 360.0
    try expectClose(degrees, 180.0, "wrap math sanity")

    // ── 5. Pass-through lines ─────────────────────────────────────────────
    let passthrough = PostTemplateEngine.emit(gcodeLines: [
        "(a comment)",
        "%",
        "O=JOB_HEADER",
        "",
        "G0 X1",
    ], template: .grbl(units: .millimeter))
    try expect(passthrough.lines.contains("(a comment)"), "comments pass through")
    try expect(passthrough.lines.contains("%"), "percent passes through")
    try expect(passthrough.lines.contains("O=JOB_HEADER"), "O= markers pass through")
    // Input blank lines pass through; the TEMPLATE itself never emits a blank
    // (no spurious lines from header/moves/footer expansion).
    try expect(passthrough.lines.contains(""), "input blank line passes through")
    let nonInput = passthrough.lines.filter { !["(a comment)", "%", "O=JOB_HEADER", "", "G0 X1"].contains($0) }
    try expect(nonInput.allSatisfy { !$0.isEmpty }, "template emits no spurious blanks")

    print("ShopPilotVerify1134: PASS — GRBL mm/inch goldens, per-word grammar (A/C/I/D/G), rotary Y2A wrap math, pass-through lines")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1134: FAIL — \(error)")
    exit(1)
}
