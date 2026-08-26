import Foundation
import ShopPilotCore

/// SPK-2100c verify (CLT machine, no XCTest).
///
/// Scallop-height leftover PREVIEW — honest formula tint vs the 0.02 mm shop
/// band:
///
///   1. FORMULA: `ScallopLeftoverTint.compute` reproduces hand math
///      h ≈ s²/(8R) exactly (s = step-over, R = ball radius = Ø/2).
///   2. SHOP BAND: 0.02 mm band classifies correctly — just-under is IN,
///      just-over is OUT; severity 1.0 sits exactly at the band edge.
///   3. LIVE STEPOVER: the verdict MOVES with step-over — halving s quarters
///      h (quadratic law), tint/severity change accordingly. This is what
///      makes the Preview update when the user edits step-over.
///   4. STOCK-TO-LEAVE: rough allowance is ADDED to the leftover; a finish
///      inside the band alone falls OUT of the band once a Rough 3D sibling's
///      0.5 mm allowance rides along; zero/negative allowances are ignored.
///   5. HONEST TINT: green strictly inside the band; the ramp past the band
///      is monotonic (red channel up, green down); saturates red at 5× the
///      band. Overlay rasters are uniform RGBA8888 washes (alpha < opaque),
///      not shaded-metal pixels. Legend text states inputs + band + totals.
///   6. PARAMS WIRING: `HeightfieldFinishParams().leftoverTint()` reads the
///      LIVE stored stepOverMm — editing it flips the verdict (this is the
///      code path the Preview legend renders).
///
/// Per board: the AC is greppable without launching the app — this CLT plus
/// the Sources grep for the overlay wiring IS the gate.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance {
        throw VerifyError.failed("\(msg) — expected \(b), got \(a)")
    }
}

// ══ 1. FORMULA: h ≈ s²/(8R) ══════════════════════════════════════════════
do {
    // 6 mm ball (Ø 6), 0.4 mm step-over: h = 0.16 / (8·3) = 0.00666…
    let t = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 6.0)
    try expectClose(t.scallopHeightMm, 0.4 * 0.4 / (8.0 * 3.0), "formula s²/(8R)")
    // 3.175 mm bit at the 10%-of-D default (0.3175): h ≈ 0.00794 mm.
    let def = ScallopLeftoverTint.compute(stepOverMm: 0.3175, toolDiameterMm: 3.175)
    try expectClose(def.scallopHeightMm, 0.3175 * 0.3175 / (8.0 * 1.5875), "default-stepover formula")
    print("1. FORMULA — s²/(8R) matches hand math ✓")
}

// ══ 2. SHOP BAND: 0.02 mm ════════════════════════════════════════════════
do {
    try expectClose(ScallopShopBand.shopQualityMm, 0.02, "band constant")
    // Step-over that lands EXACTLY on the band for Ø 3.175:
    // s = sqrt(band · 8R) = sqrt(0.02 · 12.7).
    let edgeS = (0.02 * 8.0 * 1.5875).squareRoot()
    let edge = ScallopLeftoverTint.compute(stepOverMm: edgeS, toolDiameterMm: 3.175)
    try expectClose(edge.severity, 1.0, "edge stepover sits at severity 1")
    try expect(edge.withinShopBand, "exactly-at-band counts as in-band")

    let under = ScallopLeftoverTint.compute(stepOverMm: edgeS * 0.9, toolDiameterMm: 3.175)
    let over = ScallopLeftoverTint.compute(stepOverMm: edgeS * 1.1, toolDiameterMm: 3.175)
    try expect(under.withinShopBand && under.severity < 1.0, "just under band → in")
    try expect(!over.withinShopBand && over.severity > 1.0, "just over band → out")
    print("2. SHOP BAND — 0.02 mm edge classification ✓ (edge s = \(String(format: "%.4f", edgeS)) mm)")
}

// ══ 3. LIVE STEPOVER — verdict moves when step-over changes ══════════════
do {
    let coarse = ScallopLeftoverTint.compute(stepOverMm: 0.8, toolDiameterMm: 3.175)
    let fine = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 3.175)
    try expect(coarse.withinShopBand == false, "legacy 0.8 stepover is OUT of band (the smoking gun)")
    try expect(fine.withinShopBand, "half the stepover is IN band")
    // Quadratic law: half s → quarter h.
    try expectClose(fine.scallopHeightMm * 4.0, coarse.scallopHeightMm, "halving s quarters h", tolerance: 1e-9)
    try expect(fine.severity < coarse.severity, "severity drops with stepover")
    print("3. LIVE STEPOVER — s=0.8 → h=\(String(format: "%.4f", coarse.scallopHeightMm)) OUT; s=0.4 → h=\(String(format: "%.4f", fine.scallopHeightMm)) IN; updates with edits ✓")
}

// ══ 4. ROUGH STOCK-TO-LEAVE honored ══════════════════════════════════════
do {
    let bare = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 3.175)
    try expect(bare.withinShopBand, "sanity: 0.4 on Ø3.175 fits the band alone")
    let withLeave = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 3.175, roughStockToLeaveMm: 0.5)
    try expectClose(withLeave.totalLeftoverMm, bare.scallopHeightMm + 0.5, "allowance adds to leftover")
    try expect(!withLeave.withinShopBand, "finish can't beat rough stock-to-leave → out of band")
    try expect(withLeave.legendText.contains("stock-to-leave"), "legend names the allowance")
    let zeroLeave = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 3.175, roughStockToLeaveMm: 0)
    let negLeave = ScallopLeftoverTint.compute(stepOverMm: 0.4, toolDiameterMm: 3.175, roughStockToLeaveMm: -0.3)
    try expectClose(zeroLeave.totalLeftoverMm, bare.scallopHeightMm, "zero allowance ignored")
    try expect(negLeave.roughStockToLeaveMm == 0 && negLeave.totalLeftoverMm == bare.scallopHeightMm,
               "negative allowance clamped to 0")
    print("4. STOCK-TO-LEAVE — rough allowance honored (+0.5 → OUT), 0/neg ignored ✓")
}

// ══ 5. HONEST TINT (not photoreal) ═══════════════════════════════════════
do {
    let inBand = ScallopLeftoverTint.compute(stepOverMm: 0.3, toolDiameterMm: 3.175)
    let g = inBand.tintRGB
    try expect(g.g > 0.6 && g.r < 0.4, "in-band tint is calm green")

    var lastRed = -1.0
    var lastGreen = 999.0
    var stepsChecked = 0
    var saturated = false
    for mult in stride(from: 1.0, through: 8.0, by: 0.5) {
        let t = ScallopLeftoverTint.compute(
            stepOverMm: (ScallopShopBand.shopQualityMm * 8.0 * 1.5875 * mult).squareRoot(),
            toolDiameterMm: 3.175)
        let c = t.tintRGB
        if t.severity >= ScallopShopBand.saturationSeverity { saturated = true }
        if stepsChecked > 0 {
            try expect(c.r >= lastRed - 1e-9, "red channel non-decreasing as leftover grows")
            try expect(c.g <= lastGreen + 1e-9, "green channel non-increasing as leftover grows")
        }
        lastRed = c.r
        lastGreen = c.g
        stepsChecked += 1
    }
    try expect(saturated, "ramp saturates at \(ScallopShopBand.saturationSeverity)× the band")

    let hot = ScallopLeftoverTint.compute(stepOverMm: 0.8, toolDiameterMm: 3.175)
    let px = hot.rgba8888
    try expect(px.count == 4, "rgba8888 is one RGBA pixel")
    try expect(px[3] == 200 && px[3] < 255, "overlay alpha stays translucent (a wash, not an opaque repaint)")
    let raster = hot.overlayPixels(width: 3, height: 2)
    try expect(raster.count == 3 * 2 * 4, "overlay raster size")
    try expect(raster.elementsEqual(hot.overlayPixels(width: 3, height: 2)), "overlay deterministic")
    let uniformExpected = Array(repeating: px, count: 6).flatMap { $0 }
    try expect(raster.elementsEqual(uniformExpected), "uniform tint across the raster")

    let legend = hot.legendText
    for needle in ["s=0.800", "Ø=3.175", "0.02"] {
        try expect(legend.contains(needle), "legend states inputs + band (missing \(needle)): \(legend)")
    }
    try expect(hot.verdictText == "Over shop band", "verdict word honest for hot case")
    try expect(inBand.verdictText == "In shop band", "verdict word honest for cool case")
    print("5. HONEST TINT — green in band, monotonic ramp to red, translucent uniform wash, full legend ✓")
}

// ══ 6. PARAMS WIRING — live off stored Finish 3D params ══════════════════
do {
    var params = HeightfieldFinishParams()   // init default: 10% of D
    let t1 = params.leftoverTint()
    try expectClose(t1.scallopHeightMm, params.stepOverMm * params.stepOverMm / (8.0 * params.toolDiameterMm * 0.5),
                    "leftoverTint reads live stepOverMm")
    params.stepOverMm = 0.8                  // legacy-coarse edit
    let t2 = params.leftoverTint()
    try expect(t1.withinShopBand && !t2.withinShopBand, "editing stepover flips the verdict (preview updates)")
    try expect(t2.severity > t1.severity, "coarser → more severe")
    // With a rough sibling carrying 0.5 mm, the same params go deep over.
    let t3 = params.leftoverTint(roughStockToLeaveMm: 0.5)
    try expect(t3.totalLeftoverMm == t2.totalLeftoverMm + 0.5, "params path honors stock-to-leave too")
    print("6. PARAMS WIRING — leftoverTint follows live params; verdict flips on stepover edit ✓")
}

print("")
print("ShopPilotVerify2100c: PASS — scallop h≈s²/(8R) vs 0.02 mm shop band, live stepover updates, stock-to-leave honor, honest formula tint.")
