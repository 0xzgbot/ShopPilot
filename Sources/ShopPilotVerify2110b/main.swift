import Foundation
import ShopPilotCore

// SPK-2110b — Photo/litho two-pass + lithophane leftover-thickness warning.
// AC: Linked two-pass (rough ~50% / finish 8–12%); lithophane warning if
//     stock − maxDepth < minThickness.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

func main() throws {
    // ── 1. Lithophane leftover-thickness warning. ──────────────────────────
    let p = LithophaneParams()
    // stock 25 − maxDepth 2.5 = 22.5 leftover >= 0.5 → no warning.
    expect(LithophaneEngine.leftoverThicknessWarning(stockThicknessMm: 25.0, params: p) == nil,
           "thick stock: no warning")
    // stock 3 − maxDepth 2.5 = 0.5 leftover, NOT < 0.5 → no warning (boundary).
    expect(LithophaneEngine.leftoverThicknessWarning(stockThicknessMm: 3.0, params: p) == nil,
           "boundary leftover (== min): no warning")
    // stock 2.8 − maxDepth 2.5 = 0.3 leftover < 0.5 → warning.
    let w = LithophaneEngine.leftoverThicknessWarning(stockThicknessMm: 2.8, params: p)
    expect(w != nil && w!.contains("below minThickness"),
           "thin stock triggers leftover-thickness warning")
    // stock 1.0 − maxDepth 2.5 = negative leftover → warning.
    expect(LithophaneEngine.leftoverThicknessWarning(stockThicknessMm: 1.0, params: p) != nil,
           "stock thinner than maxDepth triggers warning")

    // ── 2. Two-pass engine: byte-stable when OFF. ──────────────────────────
    let hf = try HeightfieldData(width: 10, height: 10, cellSizeMm: 1,
                                  minX: 0, minY: 0,
                                  heights: (0..<100).map { Double($0 % 10) / 9.0 * 2.0 })
    let single = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: PhotoVCarveToolpathParams())
    var off = PhotoVCarveToolpathParams()
    off.twoPass = false
    let offRes = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: off)
    expect(single.gcodeLines == offRes.gcodeLines,
           "twoPass=false byte-identical to default single pass")
    expect(!single.gcodeLines.contains { $0.contains("ROUGH PASS") },
           "single pass has no rough/finish markers")

    // ── 3. Two-pass engine: emits both passes at different stepovers. ──────
    var tp = PhotoVCarveToolpathParams()
    tp.twoPass = true
    tp.rasterAngleDegrees = 0
    let tpRes = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: tp)
    expect(tpRes.gcodeLines.contains { $0.contains("ROUGH PASS") },
           "two-pass emits rough pass marker")
    expect(tpRes.gcodeLines.contains { $0.contains("FINISH PASS") },
           "two-pass emits finish pass marker")
    expect(tpRes.gcodeLines.contains { $0.contains("Two-pass: rough 50% / finish 10%") },
           "header announces rough/finish fractions")
    // Rough pass has MORE cuts than finish pass (wider stepover = fewer, wait —
    // wider stepover = FEWER cuts; rough is wider so rough has fewer, finish
    // has more). Net: total two-pass cuts > single-pass cuts.
    func g1Count(_ lines: [String]) -> Int {
        lines.filter { $0.hasPrefix("G1") }.count
    }
    expect(g1Count(tpRes.gcodeLines) > g1Count(single.gcodeLines),
           "two-pass emits more total cuts than single (\(g1Count(tpRes.gcodeLines)) > \(g1Count(single.gcodeLines)))")

    // ── 4. Two-pass with diagonal raster. ──────────────────────────────────
    var tp45 = PhotoVCarveToolpathParams()
    tp45.twoPass = true
    // rasterAngleDegrees defaults to 45
    let tp45Res = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: tp45)
    expect(tp45Res.gcodeLines.contains { $0.contains("ROUGH PASS") },
           "diagonal two-pass emits rough pass")
    expect(tp45Res.gcodeLines.contains { $0.contains("raster 45deg") },
           "diagonal two-pass uses 45° raster")

    print(failures == 0
          ? "ShopPilotVerify2110b: PASS"
          : "ShopPilotVerify2110b: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
