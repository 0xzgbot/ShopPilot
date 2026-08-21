// SPK-1900a — verify CLT for LithophaneEngine (ShopPilotCore).
// Run via ./scripts/verify_locked.sh ShopPilotVerify1900a from repo root.

import Foundation
import ShopPilotCore

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func approxEqual(_ a: Double, _ b: Double, tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol
}

func main() throws {
    // ------------------------------------------------------------------
    // Fixture: 4x2 luminance grid (non-square). Row 0 dark, row 1 bright.
    // ------------------------------------------------------------------
    var lum: [[Double]] = [
        [0.1, 0.1, 0.9, 0.9],
        [0.1, 0.1, 0.9, 0.9],
    ]

    // (5) Grid dims match requested resolution × derived rows.
    let params = LithophaneParams(mode: .lithophaneThickness, gridResolution: 40)
    let hf = LithophaneEngine.generateHeightfield(luminance: lum, params: params)
    try expect(hf.width == 40, "width should be gridResolution (got \(hf.width))")
    try expect(hf.height == 20, "derived rows should be 40 * 2/4 = 20 (got \(hf.height))")
    try expect(hf.heights.count == hf.width * hf.height, "heights count mismatch")
    try expect(approxEqual(hf.cellSizeMm, 100.0 / 40.0), "cellSize should be maxWidth/cols")

    // (1) Thickness mode: dark cell thicker than bright; both in range.
    let base = params.baseThicknessMm      // 0.8
    let depth = params.maxDepthMm          // 2.5
    let darkZ = hf.heights[0]              // luminance 0.1 region
    let brightZ = hf.heights[39]           // luminance 0.9 region (row-major last col)
    try expect(darkZ > brightZ,
               "thickness mode must invert: dark(\(darkZ)) must be thicker than bright(\(brightZ))")
    for z in hf.heights {
        try expect(z >= base - 1e-12 && z <= base + depth + 1e-12,
                   "thickness Z \(z) outside [base, base+maxDepth]")
    }
    try expect(approxEqual(brightZ, base + depth * (1 - 0.9), tol: 1e-6),
               "bright Z should be base + maxDepth*(1-v), got \(brightZ)")

    // (2) Relief mode preserves direction: bright taller.
    let reliefParams = LithophaneParams(mode: .grayscaleRelief, maxWidthMm: 100, gridResolution: 40)
    let rf = LithophaneEngine.generateHeightfield(luminance: lum, params: reliefParams)
    try expect(rf.heights[39] > rf.heights[0],
               "relief mode: bright(\(rf.heights[39])) must be taller than dark(\(rf.heights[0]))")
    try expect(approxEqual(rf.heights[39], 0.9 * reliefParams.maxDepthMm, tol: 1e-6),
               "relief bright Z should be v * maxDepth")
    for z in rf.heights {
        try expect(z >= 0 && z <= reliefParams.maxDepthMm + 1e-12, "relief Z out of range: \(z)")
    }

    // (3) gamma / invert / contrast actually change output.
    func flatLum() -> [[Double]] {
        [[0.4, 0.7], [0.4, 0.7]]
    }
    let neutral = LithophaneEngine.generateHeightfield(
        luminance: flatLum(),
        params: LithophaneParams(gridResolution: 8))
    let gammaP = LithophaneEngine.generateHeightfield(
        luminance: flatLum(),
        params: LithophaneParams(gridResolution: 8, gamma: 2.2))
    let invertP = LithophaneEngine.generateHeightfield(
        luminance: flatLum(),
        params: LithophaneParams(gridResolution: 8, invert: true))
    let contrastP = LithophaneEngine.generateHeightfield(
        luminance: flatLum(),
        params: LithophaneParams(gridResolution: 8, contrast: 3.0))
    try expect(neutral.heights != gammaP.heights, "gamma must change output")
    try expect(neutral.heights != invertP.heights, "invert must change output")
    try expect(neutral.heights != contrastP.heights, "contrast must change output")
    // Invert sanity: flipping light/dark also flips which cells are thick —
    // the formerly-bright cell (now dark, v=0.3) becomes the thicker one.
    try expect(invertP.heights[7] > invertP.heights[0],
               "inverted thickness mode should flip which cells are thick")

    // (4) Aspect preserved on non-square input.
    var tallLum: [[Double]] = []
    for _ in 0..<16 { tallLum.append([0.5, 0.5, 0.5, 0.5]) } // 16 rows x 4 cols
    let tallHF = LithophaneEngine.generateHeightfield(
        luminance: tallLum,
        params: LithophaneParams(maxWidthMm: 80, gridResolution: 32))
    try expect(tallHF.width == 8, "tall input: short side (cols) derive as 32*4/16=8 (got \(tallHF.width))")
    try expect(tallHF.height == 32, "tall input: long side (rows) gets resolution (got \(tallHF.height))")
    let aspectCells = Double(tallHF.width) / Double(tallHF.height)
    let aspectSrc = Double(4) / Double(16)
    try expect(abs(aspectCells - aspectSrc) < 1e-9, "aspect ratio not preserved")
    try expect(approxEqual(tallHF.cellSizeMm, 80.0 / 32.0), "long side should equal maxWidthMm")

    // (6) Adversarial values: all heights finite and >= 0.
    let adversarial: [[Double]] = [
        [-0.3, 1.7, Double.nan, 0.5],
        [Double.infinity, -Double.infinity, Double.nan, 0.25],
    ]
    let advThickness = LithophaneEngine.generateHeightfield(
        luminance: adversarial,
        params: LithophaneParams(mode: .lithophaneThickness, gridResolution: 8))
    let advRelief = LithophaneEngine.generateHeightfield(
        luminance: adversarial,
        params: LithophaneParams(mode: .grayscaleRelief, gridResolution: 8))
    for z in advThickness.heights + advRelief.heights {
        try expect(z.isFinite, "adversarial input produced non-finite height \(z)")
        try expect(z >= 0, "adversarial input produced negative height \(z)")
    }
    // NaN treated as 0 → thickest in thickness mode, thinnest in relief mode.
    // Sampling: outCols=8 over srcCols=4 → sx = col/2; NaN lives at output col 4.
    let nanT = advThickness.heights[4]
    let zeroT = base + depth             // expected for v=0
    try expect(approxEqual(nanT, zeroT, tol: 1e-6) && nanT >= advThickness.heights.max()! - 1e-9,
               "NaN luminance must be treated as 0 (thickness max)")
    let nanR = advRelief.heights[4]
    try expect(approxEqual(nanR, 0, tol: 1e-9) && nanR <= advRelief.heights.min()! + 1e-9,
               "NaN luminance must be treated as 0 (relief min)")
    // Over-bright 1.7 clamps to 1 → thinnest possible in thickness mode (col 2).
    try expect(approxEqual(advThickness.heights[2], base, tol: 1e-6),
               "1.7 clamps to 1 → Z = base")

    // (7) Params Codable round-trip.
    let original = LithophaneParams(
        mode: .grayscaleRelief, maxWidthMm: 120, maxHeightMm: 60,
        gridResolution: 150, maxDepthMm: 3.0, minThicknessMm: 0.6,
        brightness: 0.05, contrast: 1.4, gamma: 1.8, invert: true, baseThicknessMm: 1.0)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(LithophaneParams.self, from: data)
    let redata = try encoder.encode(decoded)
    try expect(data == redata, "params Codable round-trip mismatch")
    try expect(decoded.mode == original.mode && decoded.maxWidthMm == original.maxWidthMm
               && decoded.maxHeightMm == original.maxHeightMm
               && decoded.gridResolution == original.gridResolution
               && decoded.invert == original.invert, "decoded params differ")
    // Defaults decode fine too.
    let defaultDecoded = try JSONDecoder().decode(
        LithophaneParams.self, from: try encoder.encode(LithophaneParams()))
    try expect(defaultDecoded.gridResolution == 200 && defaultDecoded.maxDepthMm == 2.5,
               "default params round-trip broken")

    // (8) Determinism: two runs byte-equal heights.
    let runA = LithophaneEngine.generateHeightfield(
        luminance: lum, params: LithophaneParams(gridResolution: 64, gamma: 1.5, invert: true))
    let runB = LithophaneEngine.generateHeightfield(
        luminance: lum, params: LithophaneParams(gridResolution: 64, gamma: 1.5, invert: true))
    try expect(runA.heights.count == runB.heights.count, "determinism: count differs")
    try expect(runA.heights.elementsEqual(runB.heights) { $0.bitPattern == $1.bitPattern },
               "determinism: heights differ between identical runs")
}

do {
    try main()
} catch {
    print("FAIL — \(error)")
    exit(1)
}

print("ShopPilotVerify1900a: PASS — lithophane engine")
