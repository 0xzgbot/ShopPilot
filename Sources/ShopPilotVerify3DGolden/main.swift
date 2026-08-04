import Foundation
import ShopPilotCore

/// SPK-Golden-3D verify (CLT machine, no XCTest).
///
/// Hand-checked golden G-code for the 3D rough + finish engines on a tiny
/// 3×3 heightfield fixture (cell center (1.5,1.5) peaks at 2mm, everything
/// else 0). Every expected line was derived BY HAND from the engine semantics
/// (z-level selection, run detection, bilinear surface Z) — not captured from
/// the engine. The CLT fails on ANY regression in 3D engine output.
///
///   1. ROUGH golden: stockAllowance 0.5 → stockTop 2.5, stepDown 1.0 →
///      levels [1.5, 0.5, 0.0] = 3 passes. Row 1 (y=1.5) skips the peak cell
///      at every level (surface 2 > level); rows 0/2 clear their full run.
///      Z = level − stockTop (plunge feed), runs at cut feed.
///   2. FINISH golden: stockTop = maxHeight = 2.0, 1mm raster → 3 rows;
///      Z = h − 2.0 (0 at the peak, −2.0 on the flat), first point of each
///      row positions with G0 then plunges.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// 3×3 grid at 1mm cells: center cell (i=1,j=1) = 2mm, all others 0.
func tinyRelief() -> HeightfieldData {
    HeightfieldData(
        width: 3, height: 3, cellSizeMm: 1.0, minX: 0, minY: 0,
        heights: [
            0, 0, 0,
            0, 2, 0,
            0, 0, 0,
        ]
    )
}

func expectGolden(
    _ actual: [String],
    _ expected: [String],
    _ label: String
) throws {
    try expect(actual.count == expected.count,
               "\(label): line count \(actual.count) != golden \(expected.count)")
    for (i, (a, e)) in zip(actual, expected).enumerated() {
        if a != e {
            let from = max(0, i - 3)
            let ctx = (from..<min(actual.count, i + 4)).map { idx in
                let marker = idx == i ? ">>" : "  "
                let golden = idx < expected.count ? expected[idx] : "<missing>"
                return "\(marker)[\(idx)] actual=\(actual[idx].debugDescription) golden=\(golden.debugDescription)"
            }.joined(separator: "\n")
            throw VerifyError.failed("\(label): line \(i) differs\n\(ctx)")
        }
    }
}

func main() throws {
    let hf = tinyRelief()
    try expect(abs(hf.maxHeight - 2.0) < 1e-9, "fixture peaks at 2mm")

    // ── 1. ROUGH golden. ───────────────────────────────────────────────────
    let roughParams = HeightfieldRoughParams(
        toolDiameterMm: 6.0, stepDownMm: 1.0, stepOverMm: 1.0,
        feedRateMmPerMin: 1200, plungeFeedRateMmPerMin: 300,
        safeZHeightMm: 5.0, stockAllowanceMm: 0.5
    )
    let rough = HeightfieldRoughEngine.compute(heightfield: hf, params: roughParams)
    // Hand-derived:
    //   stockTop = 2 + 0.5 = 2.5 → z-levels 1.5, 0.5, 0.0 (3 passes).
    //   Each pass: G0 Z5.0, then per row (y = 0.5, 1.5, 2.5) contiguous runs
    //   of cells with surface ≤ level. Rows 0/2 are all-0 → one full run
    //   x 0.5→2.5. Row 1 has surface 2 at x=1.5 > every level → two runs
    //   x 0.5→0.5 and x 2.5→2.5 (peak cell skipped).
    //   Z = level − stockTop → −1.0 / −2.0 / −2.5; plunge F300, cut F1200.
    //   Safe-Z rapids are formatted %.3f → G0 Z5.000.
    let roughGolden: [String] = [
        "%",
        "O=ROUGH_3D",
        "(Rough: 6.0mm, 3 z-levels)",
        "",
        "(Pass 1/3, Z=-1.000)",
        "G0 Z5.000",
        "G0 X0.500 Y0.500",
        "G1 Z-1.000 F300",
        "G1 X2.500 Y0.500 F1200",
        "G0 X0.500 Y1.500",
        "G1 Z-1.000 F300",
        "G1 X0.500 Y1.500 F1200",
        "G0 X2.500 Y1.500",
        "G1 Z-1.000 F300",
        "G1 X2.500 Y1.500 F1200",
        "G0 X0.500 Y2.500",
        "G1 Z-1.000 F300",
        "G1 X2.500 Y2.500 F1200",
        "",
        "(Pass 2/3, Z=-2.000)",
        "G0 Z5.000",
        "G0 X0.500 Y0.500",
        "G1 Z-2.000 F300",
        "G1 X2.500 Y0.500 F1200",
        "G0 X0.500 Y1.500",
        "G1 Z-2.000 F300",
        "G1 X0.500 Y1.500 F1200",
        "G0 X2.500 Y1.500",
        "G1 Z-2.000 F300",
        "G1 X2.500 Y1.500 F1200",
        "G0 X0.500 Y2.500",
        "G1 Z-2.000 F300",
        "G1 X2.500 Y2.500 F1200",
        "",
        "(Pass 3/3, Z=-2.500)",
        "G0 Z5.000",
        "G0 X0.500 Y0.500",
        "G1 Z-2.500 F300",
        "G1 X2.500 Y0.500 F1200",
        "G0 X0.500 Y1.500",
        "G1 Z-2.500 F300",
        "G1 X0.500 Y1.500 F1200",
        "G0 X2.500 Y1.500",
        "G1 Z-2.500 F300",
        "G1 X2.500 Y1.500 F1200",
        "G0 X0.500 Y2.500",
        "G1 Z-2.500 F300",
        "G1 X2.500 Y2.500 F1200",
        "",
        "M30",
        "%",
    ]
    try expectGolden(rough.gcodeLines, roughGolden, "3D Rough golden")
    try expect(rough.passCount == 3, "rough passCount == 3 (got \(rough.passCount))")

    // ── 2. FINISH golden. ──────────────────────────────────────────────────
    let finishParams = HeightfieldFinishParams(
        toolDiameterMm: 3.0, stepOverMm: 1.0,
        feedRateMmPerMin: 1000, plungeFeedRateMmPerMin: 300,
        safeZHeightMm: 5.0
    )
    let finish = HeightfieldFinishEngine.compute(heightfield: hf, params: finishParams)
    // Hand-derived:
    //   stockTop = maxHeight = 2.0 (no allowance). 1mm raster → 3 rows at
    //   y = 0.5, 1.5, 2.5. Z = h − 2.0: row 0/2 flat → −2.000 everywhere;
    //   row 1: −2.000 at x=0.5, 0.000 at the peak x=1.5, −2.000 at x=2.5.
    //   First point of each row: G0 position then G1 plunge (F300); rest cut
    //   (F1000). G0 Z5.000 at the top of every row (%.3f safe-Z).
    let finishGolden: [String] = [
        "%",
        "O=FINISH_3D",
        "(Finish: 3.0mm ball nose)",
        "",
        "(Pass 1, Y=0.500)",
        "G0 Z5.000",
        "G0 X0.500 Y0.500",
        "G1 Z-2.000 F300",
        "G1 X1.500 Y0.500 Z-2.000 F1000",
        "G1 X2.500 Y0.500 Z-2.000 F1000",
        "",
        "(Pass 2, Y=1.500)",
        "G0 Z5.000",
        "G0 X0.500 Y1.500",
        "G1 Z-2.000 F300",
        "G1 X1.500 Y1.500 Z-0.000 F1000",
        "G1 X2.500 Y1.500 Z-2.000 F1000",
        "",
        "(Pass 3, Y=2.500)",
        "G0 Z5.000",
        "G0 X0.500 Y2.500",
        "G1 Z-2.000 F300",
        "G1 X1.500 Y2.500 Z-2.000 F1000",
        "G1 X2.500 Y2.500 Z-2.000 F1000",
        "",
        "M30",
        "%",
    ]
    try expectGolden(finish.gcodeLines, finishGolden, "3D Finish golden")

    print("ShopPilotVerify3DGolden: PASS — hand-checked goldens: 3D rough (3 z-levels, peak-cell skip, run Z/feeds), 3D finish (surface Z incl. 0 at peak)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify3DGolden: FAIL — \(error)")
    exit(1)
}
