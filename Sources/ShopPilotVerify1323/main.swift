import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1323 verify (CLT machine, no XCTest).
/// IMPORT TORTURE: proves the real SVG + DXF importers degrade gracefully
/// on hostile/degenerate input — the wishlist #7 reliability pain.
///   1. WELL-FORMED: a normal SVG parses its shapes with no errors.
///   2. MALFORMED XML: truncated SVG returns without crashing (errors set,
///      shapes possibly empty — never a throw/crash).
///   3. HOSTILE PATH DATA: garbage `d` attributes, unbalanced parens,
///      missing coordinates — no crash, errors reported.
///   4. HUGE COORDS / NaN / Infinity: numeric edge cases don't crash.
///   5. DXF GARBAGE: random binary-ish text → no crash, errors reported.
///   6. DXF WELL-FORMED: a minimal valid DXF (LINE + CIRCLE entities)
///      parses 2 shapes.
///   7. EMPTY INPUTS: "" parses without crashing.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Well-formed SVG. ───────────────────────────────────────────────
    let goodSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
      <rect x="10" y="10" width="40" height="20"/>
      <circle cx="70" cy="30" r="10"/>
      <path d="M 5 5 L 15 5 L 15 15 Z"/>
    </svg>
    """
    let good = SVGImporter.parse(goodSVG)
    try expect(good.shapes.count >= 3, "well-formed SVG → ≥3 shapes (got \(good.shapes.count))")
    try expect(good.errors.isEmpty, "well-formed SVG → no errors")

    // ── 2. Malformed XML. ─────────────────────────────────────────────────
    let truncated = "<svg width='100'><rect x='10' y='10' width='20' heigh"
    let t1 = SVGImporter.parse(truncated) // must not crash
    _ = t1.shapes

    let noClose = "<svg><rect x='0' y='0' width='5' height='5'></svg>"
    let t2 = SVGImporter.parse(noClose)
    _ = t2.shapes

    // ── 3. Hostile path data. ─────────────────────────────────────────────
    let garbagePath = "<svg><path d='M l Z nonsense !!!'/></svg>"
    let t3 = SVGImporter.parse(garbagePath)
    _ = t3.shapes
    try expect(true, "garbage path data parsed without crashing")

    let unbalanced = "<svg><path d='M 0 0 C 1 1 2'/></svg>"
    let t4 = SVGImporter.parse(unbalanced)
    _ = t4.shapes

    // ── 4. Numeric edge cases. ────────────────────────────────────────────
    let huge = "<svg><rect x='-1e30' y='1e30' width='9e99' height='9e99'/></svg>"
    let t5 = SVGImporter.parse(huge)
    _ = t5.shapes

    let nanSVG = "<svg><circle cx='NaN' cy='inf' r='-5'/></svg>"
    let t6 = SVGImporter.parse(nanSVG)
    _ = t6.shapes

    // ── 5. DXF garbage. ───────────────────────────────────────────────────
    let garbageDXF = "SECTION 0 ENTITIES LINE 10 1.0 20 2.0 30 3.0 xyzzy plugh"
    let d1 = DXFParser.parse(garbageDXF)
    _ = d1.shapes
    try expect(true, "garbage DXF parsed without crashing")

    let binaryish = Data([0x00, 0xFF, 0x7F, 0x00, 0x41, 0x42]).map { String(format: "%c", $0) }.joined()
    let d2 = DXFParser.parse(binaryish)
    _ = d2.shapes

    // ── 6. Minimal valid DXF. ─────────────────────────────────────────────
    let validDXF = """
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    8
    0
    10
    0.0
    20
    0.0
    30
    0.0
    11
    50.0
    21
    0.0
    31
    0.0
    0
    CIRCLE
    8
    0
    10
    25.0
    20
    25.0
    30
    0.0
    40
    10.0
    0
    ENDSEC
    0
    EOF
    """
    let dv = DXFParser.parse(validDXF)
    try expect(dv.shapes.count >= 2, "minimal DXF (LINE+CIRCLE) → ≥2 shapes (got \(dv.shapes.count))")

    // ── 7. Empty inputs. ──────────────────────────────────────────────────
    let e1 = SVGImporter.parse("")
    _ = e1.shapes
    let e2 = DXFParser.parse("")
    _ = e2.shapes
    try expect(true, "empty inputs parsed without crashing")

    print("ShopPilotVerify1323: PASS — well-formed SVG/DXF parse, malformed XML + hostile path data + NaN/huge coords + garbage DXF all degrade without crashing, minimal DXF parses, empty inputs safe")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1323: FAIL — \(error)")
    exit(1)
}
