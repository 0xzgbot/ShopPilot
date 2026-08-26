import Foundation
import ShopPilotCore

// PHASE Y audit — differential param reachability.
//
// Motivated by SPK-2120b, where a param was persisted but never reached the
// engine, and a G-code section was emitted while cutting nothing. Marker and
// in-memory assertions both missed it. This audit asserts on EMITTED G-CODE:
// mutate one field, and if the output does not change, the field is dead
// (wired to the form/persistence but not to the engine).

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

/// A param is LIVE when mutating it changes the emitted G-code.
func live(_ name: String, _ base: [String], _ mutated: [String]) {
    expect(base != mutated, "\(name) reaches the G-code (dead param if FAIL)")
}

/// Every O= section that contains at least one real cutting move.
func cuttingSections(_ g: [String]) -> [String] {
    var section = "PREAMBLE", out: [String] = []
    for l in g {
        if l.hasPrefix("O=") { section = String(l.dropFirst(2)); continue }
        guard l.hasPrefix("G1"), l.contains("X") || l.contains("Y") else { continue }
        if out.last != section { out.append(section) }
    }
    return out
}

func cutCount(_ g: [String]) -> Int {
    g.filter { $0.hasPrefix("G1") && ($0.contains("X") || $0.contains("Y")) }.count
}

func word(_ l: String, _ w: Character) -> Double? {
    for p in l.split(separator: " ") where p.first == w { return Double(p.dropFirst()) }
    return nil
}

/// Cut segments within one O= section as ((x0,y0),(x1,y1)). Tracks the last
/// commanded XY so each G1's TRUE span is known — endpoint-only checks miss a
/// full-width row whose ends sit outside the region of interest.
func cutSegments(_ g: [String], section want: String) -> [((Double, Double), (Double, Double))] {
    var section = "", cx = 0.0, cy = 0.0
    var out: [((Double, Double), (Double, Double))] = []
    for l in g {
        if l.hasPrefix("O=") { section = String(l.dropFirst(2)); continue }
        guard l.hasPrefix("G0") || l.hasPrefix("G1") else { continue }
        let nx = word(l, "X") ?? cx, ny = word(l, "Y") ?? cy
        if l.hasPrefix("G1"), section == want, l.contains("X") || l.contains("Y") {
            out.append(((cx, cy), (nx, ny)))
        }
        cx = nx; cy = ny
    }
    return out
}

/// True when the segment passes through the rect (sampled along the span).
func segmentEntersRect(_ s: ((Double, Double), (Double, Double)),
                       minX: Double, maxX: Double, minY: Double, maxY: Double) -> Bool {
    let (a, b) = s
    for i in 0...200 {
        let t = Double(i) / 200.0
        let x = a.0 + (b.0 - a.0) * t, y = a.1 + (b.1 - a.1) * t
        if x > minX, x < maxX, y > minY, y < maxY { return true }
    }
    return false
}

/// No cutting may be stranded after the program end.
func programEndSane(_ g: [String], _ label: String) {
    guard let m30 = g.firstIndex(of: "M30") else {
        expect(false, "\(label): has an M30"); return
    }
    expect(g[(m30 + 1)...].filter { !$0.isEmpty } == ["%"], "\(label): nothing after M30 but %")
    expect(g.filter { $0 == "M30" }.count == 1, "\(label): exactly one M30")
}

/// Bowl-shaped relief so rough/finish/rest all have real work to do.
func bowl(_ n: Int = 40, cell: Double = 1.0) -> HeightfieldData {
    var h = [Double](repeating: 0, count: n * n)
    let c = Double(n - 1) / 2
    for iy in 0..<n {
        for ix in 0..<n {
            let dx = (Double(ix) - c) / c, dy = (Double(iy) - c) / c
            let r = min(1, (dx * dx + dy * dy).squareRoot())
            h[iy * n + ix] = 10.0 * (1 - r * r)   // dome, 0…10 mm
        }
    }
    return HeightfieldData(width: n, height: n, cellSizeMm: cell,
                           minX: 0, minY: 0, heights: h)
}

func main() {
    let hf = bowl()
    let square = VectorPath(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 30, y: 0),
        VectorPoint(x: 30, y: 20), VectorPoint(x: 0, y: 20),
    ], isClosed: true)

    // ── SPK-2100a/b/d — Finish 3D ────────────────────────────────────────
    print("\n── SPK-2100a/b/d Finish 3D ──")
    let fBase = HeightfieldFinishEngine.compute(heightfield: hf, params: HeightfieldFinishParams())
    expect(cutCount(fBase.gcodeLines) > 0, "finish baseline actually cuts")
    programEndSane(fBase.gcodeLines, "finish")

    var fStep = HeightfieldFinishParams(); fStep.stepOverMm = 2.0
    live("finish stepOverMm", fBase.gcodeLines,
         HeightfieldFinishEngine.compute(heightfield: hf, params: fStep).gcodeLines)

    var fTool = HeightfieldFinishParams(); fTool.toolDiameterMm = 8.0
    live("finish toolDiameterMm (drop-cutter)", fBase.gcodeLines,
         HeightfieldFinishEngine.compute(heightfield: hf, params: fTool).gcodeLines)

    // SPK-2100b — raster angle must actually rotate the lace.
    for a in [45.0, 90.0] {
        var p = HeightfieldFinishParams(); p.rasterAngleDegrees = a
        live("finish rasterAngleDegrees=\(Int(a))", fBase.gcodeLines,
             HeightfieldFinishEngine.compute(heightfield: hf, params: p).gcodeLines)
    }

    // SPK-2100d — rest finish must REMOVE work the previous ball already did.
    var fRest = HeightfieldFinishParams(); fRest.previousToolDiameterMm = 12.0
    let restG = HeightfieldFinishEngine.compute(heightfield: hf, params: fRest).gcodeLines
    live("finish previousToolDiameterMm (rest)", fBase.gcodeLines, restG)
    expect(cutCount(restG) < cutCount(fBase.gcodeLines),
           "rest finish cuts LESS than plain finish (\(cutCount(restG)) < \(cutCount(fBase.gcodeLines)))")
    expect(cutCount(restG) > 0, "rest finish still cuts the leftover cusps (not a no-op)")
    programEndSane(restG, "rest finish")

    // SELF-CHECK — the audit must be able to FAIL. Feed `live` two identical
    // outputs (a deliberately dead mutation) and confirm it reports dead.
    // Without this, an all-green audit could just mean the probe is inert.
    let selfCheckDetectsDead: Bool = {
        let before = failures
        live("SELF-CHECK sentinel (expected to trip)", fBase.gcodeLines, fBase.gcodeLines)
        let tripped = failures > before
        failures = before   // roll back the intentional trip
        return tripped
    }()
    expect(selfCheckDetectsDead,
           "SELF-CHECK: audit detects a dead param when one exists")

    // Rest finish OFF must stay byte-identical to plain (legacy stability).
    var fRest0 = HeightfieldFinishParams(); fRest0.previousToolDiameterMm = 0
    expect(HeightfieldFinishEngine.compute(heightfield: hf, params: fRest0).gcodeLines
           == fBase.gcodeLines, "previousToolDiameterMm=0 is byte-stable vs plain finish")

    // ── Rough 3D ─────────────────────────────────────────────────────────
    print("\n── Rough 3D ──")
    let rBase = HeightfieldRoughEngine.compute(heightfield: hf, params: HeightfieldRoughParams())
    expect(cutCount(rBase.gcodeLines) > 0, "rough baseline actually cuts")
    programEndSane(rBase.gcodeLines, "rough")

    var rStock = HeightfieldRoughParams(); rStock.stockAllowanceMm = 3.0
    live("rough stockAllowanceMm", rBase.gcodeLines,
         HeightfieldRoughEngine.compute(heightfield: hf, params: rStock).gcodeLines)

    var rStepDown = HeightfieldRoughParams(); rStepDown.stepDownMm = 5.0
    live("rough stepDownMm", rBase.gcodeLines,
         HeightfieldRoughEngine.compute(heightfield: hf, params: rStepDown).gcodeLines)

    var rInv = HeightfieldRoughParams(); rInv.inverseMill = true
    live("rough inverseMill", rBase.gcodeLines,
         HeightfieldRoughEngine.compute(heightfield: hf, params: rInv).gcodeLines)

    var rRest = HeightfieldRoughParams(); rRest.previousToolDiameterMm = 12.0
    live("rough previousToolDiameterMm (rest)", rBase.gcodeLines,
         HeightfieldRoughEngine.compute(heightfield: hf, params: rRest).gcodeLines)

    // ── SPK-2110a/b — Photo V-carve ──────────────────────────────────────
    print("\n── SPK-2110a/b Photo V-carve ──")
    let pBase = PhotoVCarveToolpathParams()
    let pBaseG = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: pBase).gcodeLines
    expect(cutCount(pBaseG) > 0, "photo baseline actually cuts")
    programEndSane(pBaseG, "photo")

    var pTip = PhotoVCarveToolpathParams(); pTip.tipDiameterMm = 2.0
    live("photo tipDiameterMm (groove width)", pBaseG,
         PhotoVCarveToolpathEngine.compute(heightfield: hf, params: pTip).gcodeLines)

    var pInv = PhotoVCarveToolpathParams(); pInv.invertLuminance = !pBase.invertLuminance
    live("photo invertLuminance", pBaseG,
         PhotoVCarveToolpathEngine.compute(heightfield: hf, params: pInv).gcodeLines)

    var pAng = PhotoVCarveToolpathParams(); pAng.rasterAngleDegrees = pBase.rasterAngleDegrees + 45
    live("photo rasterAngleDegrees", pBaseG,
         PhotoVCarveToolpathEngine.compute(heightfield: hf, params: pAng).gcodeLines)

    // SPK-2110b — two-pass must add a rough leg, i.e. strictly more cutting.
    var pTwo = PhotoVCarveToolpathParams(); pTwo.twoPass = true
    let twoG = PhotoVCarveToolpathEngine.compute(heightfield: hf, params: pTwo).gcodeLines
    live("photo twoPass", pBaseG, twoG)
    expect(cutCount(twoG) > cutCount(pBaseG),
           "two-pass cuts MORE than single pass (\(cutCount(twoG)) > \(cutCount(pBaseG)))")
    programEndSane(twoG, "photo two-pass")

    // ── SPK-2120a/b — V-carve tip Ø + inlay order ────────────────────────
    print("\n── SPK-2120a/b V-carve ──")
    var vBase = VCarveParams(); vBase.maxDepthOfCutMm = 6
    let vBaseG = VCarveEngine.compute(vectors: [square], params: vBase).gcodeLines
    expect(cutCount(vBaseG) > 0, "v-carve baseline actually cuts")
    programEndSane(vBaseG, "v-carve")

    var vTip = vBase; vTip.tipDiameterMm = 1.5
    live("v-carve tipDiameterMm", vBaseG,
         VCarveEngine.compute(vectors: [square], params: vTip).gcodeLines)

    var vCell = vBase; vCell.medialAxisCellMm = 0.3
    live("v-carve medialAxisCellMm (2120c preset)", vBaseG,
         VCarveEngine.compute(vectors: [square], params: vCell).gcodeLines)

    var vFlat = vBase; vFlat.flatAreaClearing = true
    live("v-carve flatAreaClearing", vBaseG,
         VCarveEngine.compute(vectors: [square], params: vFlat).gcodeLines)

    // The inlay floor must CUT, not merely announce itself (SPK-2120b bug 3).
    let inlay = InlayToolpathEngine.computePocket(
        paths: [square], params: InlayToolpathParams(inlayDepthMm: 3, vBitAngleDegrees: 60))
    expect(cuttingSections(inlay.gcodeLines) == ["V_CARVE_TOOLPATH", "VCARVE_CLEARANCE"],
           "inlay pocket cut order V-walls→floor — got \(cuttingSections(inlay.gcodeLines))")
    programEndSane(inlay.gcodeLines, "inlay pocket")

    // GAP MY OWN AUDIT MISSED (caught by Cursor, guarded here):
    // interior floor-filling must NOT apply to an ordinary sign board, or
    // vFirst would pocket out the letters. `inlayInteriorFloor` gates it and
    // only `computePocket` sets it. A lone-rect fixture cannot see this —
    // the board needs a letter strictly inside.
    let boardOutline = VectorPath(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 30, y: 0),
        VectorPoint(x: 30, y: 18), VectorPoint(x: 0, y: 18),
    ], isClosed: true)
    let letter = VectorPath(points: [
        VectorPoint(x: 12, y: 7), VectorPoint(x: 18, y: 7),
        VectorPoint(x: 18, y: 11), VectorPoint(x: 12, y: 11),
    ], isClosed: true)

    var signVFirst = VCarveParams()
    signVFirst.clearancePassEnabled = true
    signVFirst.vFirst = true            // interior floor NOT requested
    expect(signVFirst.inlayInteriorFloor == false,
           "inlayInteriorFloor defaults OFF (sign boards never interior-fill)")
    let signG = VCarveEngine.compute(vectors: [boardOutline, letter], params: signVFirst).gcodeLines
    expect(cuttingSections(signG) == ["V_CARVE_TOOLPATH", "VCARVE_CLEARANCE"],
           "sign board vFirst: V then AROUND-letter clearance — got \(cuttingSections(signG))")
    programEndSane(signG, "sign board vFirst")

    // The letter interior must survive. Endpoint proximity is NOT enough: a
    // full-width raster row at the letter's Y has endpoints far outside it and
    // would slip through. Reconstruct each cut SPAN (last commanded XY → G1
    // target) and test true overlap.
    let through = cutSegments(signG, section: "VCARVE_CLEARANCE").filter {
        segmentEntersRect($0, minX: 12, maxX: 18, minY: 7, maxY: 11)
    }
    expect(through.isEmpty,
           "sign board vFirst: no clearance SPAN enters the letter (\(through.count) violations)")

    // SELF-CHECK — the span guard must be able to FAIL. A synthetic full-width
    // row at the letter's Y (endpoints outside it) is exactly what an
    // endpoint-proximity check would wave through.
    let synthetic = ["O=VCARVE_CLEARANCE", "G0 X1.000 Y9.000", "G1 X29.000 Y9.000 F1000"]
    expect(cutSegments(synthetic, section: "VCARVE_CLEARANCE").contains {
        segmentEntersRect($0, minX: 12, maxX: 18, minY: 7, maxY: 11)
    }, "SELF-CHECK: span guard catches a full-width through-cut")

    // And the inlay path DOES fill its interior (the complementary case).
    var inlayInterior = VCarveParams()
    inlayInterior.clearancePassEnabled = true
    inlayInterior.vFirst = true
    inlayInterior.inlayInteriorFloor = true
    let fillG = VCarveEngine.compute(vectors: [square], params: inlayInterior).gcodeLines
    expect(cutCount(fillG) > cutCount(
        VCarveEngine.compute(vectors: [square], params: signVFirst).gcodeLines),
        "inlayInteriorFloor=true fills the interior (more cuts than around-mode)")

    print("")
    print(failures == 0
          ? "ShopPilotVerifyPhaseYAudit: PASS"
          : "ShopPilotVerifyPhaseYAudit: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

main()
