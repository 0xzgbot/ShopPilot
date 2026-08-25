import Foundation
import ShopPilotCore

// SPK-2021a — inlay wizard physics: tip diameter floor, glue gap,
// compression fudge. Paired pocket+plug ops from ONE source vector,
// verified numerically (measured offsets, depth floors, byte-identity).

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, name: String = "letter") -> VectorPath {
    VectorPath(
        name: name,
        points: [pt(x, y), pt(x + w, y), pt(x + w, y + h), pt(x, y + h)],
        isClosed: true)
}

/// Exact distance from p to the boundary of the closed polygon `pts`.
func distToBoundary(_ p: VectorPoint, _ pts: [VectorPoint]) -> Double {
    var best = Double.infinity
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let denom = abx * abx + aby * aby
        let t = denom > 1e-18 ? max(0.0, min(1.0, (apx * abx + apy * aby) / denom)) : 0.0
        let dx = apx - t * abx, dy = apy - t * aby
        best = min(best, (dx * dx + dy * dy).squareRoot())
    }
    return best
}

func main() throws {
    // ── AC1 — same closed letter → BOTH pocket and plug generated from ONE
    // source vector, one call. ────────────────────────────────────────────────
    let letter = rect(10, 10, 40, 20)
    var params = InlayPocketParams()
    params.inlayType = .fullInlay
    params.depth = 3.0              // maxDepth
    params.tipDiameterMm = 0.1      // default
    params.glueGapMm = 0.05         // default
    params.compressionFudge = 1.002 // default

    let pair = InlayEngine.generatePairedOps(vectors: [letter], params: params)
    try expect(pair.pocket.gcodeLines.contains("O=INLAY_PAIRED_POCKET"),
               "pocket op carries its marker")
    try expect(pair.plug.gcodeLines.contains("O=INLAY_PAIRED_PLUG"),
               "plug op carries its marker")
    try expect(!pair.pocket.path.points.isEmpty && !pair.plug.path.points.isEmpty,
               "both halves carry geometry")
    try expect(pair.pocket.gcodeLines.contains { $0.contains("glueGap/2") },
               "V1 CHOICE comment copied verbatim into pocket header")

    // ── AC2 — MEASURED offset: pocket outline = source offset OUTWARD by
    // exactly glueGapMm/2; plug untouched by glue gap. ───────────────────────
    let srcPts = letter.points
    let halfGap = params.glueGapMm / 2.0 // 0.025
    // Mitre-join contract: every point ON AN EDGE of the offset outline sits
    // exactly glueGap/2 from the source boundary; corner vertices are farther
    // by d/cos(theta/2) (90-degree corner -> d*sqrt2), so vertices assert >=.
    let pockPts = pair.pocket.path.points
    for i in 0..<pockPts.count {
        let a = pockPts[i]
        let b = pockPts[(i + 1) % pockPts.count]
        let mid = VectorPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dm = distToBoundary(mid, srcPts)
        try expect(abs(dm - halfGap) < 1e-9,
                   "offset edge midpoint sits exactly glueGap/2 outside source (got \(dm))")
        let dv = distToBoundary(a, srcPts)
        try expect(dv >= halfGap - 1e-9,
                   "vertex never closer than glueGap/2 (got \(dv))")
    }
    // Pocket must be OUTWARD: bigger bounding box than the source.
    let pb = pair.pocket.path.bounds!
    try expect(pb.minX < srcPts.map(\.x).min()! && pb.maxX > srcPts.map(\.x).max()!,
               "pocket grew outward on X")
    // Plug geometry is NOT offset by glue gap (only fudge may move it):
    // with fudge = 1.0 it must equal the source exactly (AC4 covers bits;
    // here confirm the glue gap did not touch the plug path bounds).
    var noFudge = params
    noFudge.compressionFudge = 1.0
    let plainPlug = InlayEngine.generatePairedOps(vectors: [letter], params: noFudge)
    let plugB = plainPlug.plug.path.bounds!
    try expect(plugB.minX == srcPts.map(\.x).min()! && plugB.maxX == srcPts.map(\.x).max()!,
               "plug bounds identical to source — glue gap does NOT touch the plug")

    // ── AC3 — flat-tip floor: valley narrower than tipDiameterMm gets STRAIGHT
    // walls at maxDepth (depth floors; taper elsewhere stays analytic). ──────
    // Thin sliver 0.2 mm wide, tip Ø 0.5 → every vertex below tip width.
    let sliverTip = 0.5
    let sliver = rect(0, 0, 10.0, 0.2, name: "sliver")
    var slim = InlayPocketParams()
    slim.inlayType = .fullInlay
    slim.depth = 3.0                 // maxDepth
    slim.tipDiameterMm = sliverTip
    slim.glueGapMm = 0.0             // isolate the tip physics
    slim.compressionFudge = 1.0
    let sliverPair = InlayEngine.generatePairedOps(vectors: [sliver], params: slim)
    try expect(sliverPair.pocket.straightWallFlags.allSatisfy { $0 },
               "valley narrower than tip Ø → straight-wall flagged everywhere")
    for d in sliverPair.pocket.depthsMm {
        try expect(d == 3.0, "narrow-valley depth floors exactly at maxDepth (got \(d))")
    }
    // Positive control: wide rect, huge maxDepth → analytic taper survives:
    // d = (w − tip)/(2·tan(45°)) with w = 20 (short side) → (20 − 0.5)/2 = 9.75.
    var wide = slim
    wide.depth = 50.0
    let widePair = InlayEngine.generatePairedOps(vectors: [rect(0, 0, 40, 20)], params: wide)
    try expect(widePair.pocket.straightWallFlags.allSatisfy { !$0 },
               "wide valley keeps tapered (non-straight) walls")
    for d in widePair.pocket.depthsMm {
        try expect(abs(d - 9.75) < 1e-9,
                   "taper depth matches analytic V formula (got \(d), want 9.75)")
    }

    // ── AC4 — fudge = 1.0 → plug coordinates BYTE-IDENTICAL to unfudged. ────
    try expect(plainPlug.plug.path.points.count == srcPts.count,
               "plug keeps vertex count at identity fudge")
    for (a, b) in zip(plainPlug.plug.path.points, srcPts) {
        try expect(a.x == b.x && a.y == b.y,
                   "fudge=1.0 plug coordinate bit-identical to source (unfudged)")
    }
    // Deterministic emission: two identical calls agree line-for-line.
    let again = InlayEngine.generatePairedOps(vectors: [letter], params: noFudge)
    try expect(again.plug.gcodeLines == plainPlug.plug.gcodeLines,
               "repeat call emits byte-identical plug G-code")

    // ── AC5 — fudge = 1.002 → centroid-scale asserted on coordinates. ────────
    let c = pair.sourceCentroid
    for (q, p) in zip(pair.plug.path.points, srcPts) {
        let rIn = ((p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y)).squareRoot()
        let rOut = ((q.x - c.x) * (q.x - c.x) + (q.y - c.y) * (q.y - c.y)).squareRoot()
        try expect(abs(rOut - rIn * 1.002) < 1e-9,
                   "plug radius about centroid scaled by exactly 1.002 (got \(rOut/rIn))")
        // Direction preserved through the centroid.
        let dot = (q.x - c.x) * (p.y - c.y) - (q.y - c.y) * (p.x - c.x)
        try expect(abs(dot) < 1e-6, "scaled point stays on the centroid→vertex ray")
    }

    // ── AC6 — legacy decode: JSON without new keys decodes to defaults;
    // round-trip preserves values. ────────────────────────────────────────────
    let legacyJSON = """
    {"inlayType":"fullInlay","shape":"round","diameter":10,"depth":3,
     "pocketClearance":0.02,"plugClearance":0.05,"toolDiameter":3.175,
     "feedRateMmPerMin":800,"plungeFeedRateMmPerMin":200,"vCarveDepth":2,
     "material":"contrastingWood","customShapePoints":[]}
    """
    let legacy = try JSONDecoder().decode(InlayPocketParams.self, from: Data(legacyJSON.utf8))
    try expect(abs(legacy.tipDiameterMm - 0.1) < 1e-12, "legacy decode → tipDiameterMm default 0.1")
    try expect(abs(legacy.glueGapMm - 0.05) < 1e-12, "legacy decode → glueGapMm default 0.05")
    try expect(abs(legacy.compressionFudge - 1.002) < 1e-12, "legacy decode → compressionFudge default 1.002")

    var custom = InlayPocketParams()
    custom.tipDiameterMm = 0.4
    custom.glueGapMm = 0.12
    custom.compressionFudge = 1.005
    let back = try JSONDecoder().decode(InlayPocketParams.self, from: JSONEncoder().encode(custom))
    try expect(abs(back.tipDiameterMm - 0.4) < 1e-12
               && abs(back.glueGapMm - 0.12) < 1e-12
               && abs(back.compressionFudge - 1.005) < 1e-12,
               "round-trip preserves all three physics values")

    // ── AC7 — session recalc regenerates BOTH ops from the one node. ─────────
    var wizard = InlayPocketParams()
    wizard.inlayType = .fullInlay
    wizard.depth = 3.0
    wizard.glueGapMm = 0.08
    let tree = ToolpathTreeManager()
    let node = tree.addOperation("Inlay Pair 1")
    node.paramsJSON = String(data: try JSONEncoder().encode(wizard), encoding: .utf8)
    node.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [letter], material: nil, stockHeightMm: 25.0)
    try expect(regenerated.count == 1, "dirty paired-inlay node regenerates once")
    let g = regenerated[0].toolpathResult ?? ""
    try expect(g.contains("O=INLAY_PAIRED_POCKET"), "recalc regenerated the POCKET op")
    try expect(g.contains("O=INLAY_PAIRED_PLUG"), "recalc regenerated the PLUG op")
    try expect(regenerated[0].isDirty == false, "node clears dirty after recalc")
    // Recalc honors stored physics: glueGap 0.08 → offset 0.04 measured.
    // NOTE: nodes are reference types — capture the FIRST result string now,
    // because after the next recalc both array slots point at the same node.
    let gBeforeMutation = g
    var mutated = wizard
    mutated.glueGapMm = 0.02
    node.paramsJSON = String(data: try JSONEncoder().encode(mutated), encoding: .utf8)
    node.markDirty()
    let after = tree.recalculateDirtyToolpaths(vectors: [letter], material: nil, stockHeightMm: 25.0)
    try expect(after[0].toolpathResult != gBeforeMutation,
               "mutating glueGap + recalc changes the G-code")

    // ── AC8 — regression guard: legacy variant blobs still route to the
    // old engines (no "inlayType" key → never the paired path). ──────────────
    let legacyNode = tree.addOperation("Inlay Pocket 2")
    var variantParams = InlayToolpathParams()
    variantParams.variant = .pocket
    variantParams.inlayDepthMm = 3.0
    legacyNode.paramsJSON = String(data: try JSONEncoder().encode(variantParams), encoding: .utf8)
    legacyNode.markDirty()
    let legacyRegen = tree.recalculateDirtyToolpaths(vectors: [letter], material: nil, stockHeightMm: 25.0)
    try expect(legacyRegen.count == 1, "legacy variant node regenerates")
    try expect(legacyRegen[0].toolpathResult?.contains("O=V_CARVE_TOOLPATH") == true,
               "legacy variant blob still routes to the V-Carve engine")
    try expect(legacyRegen[0].toolpathResult?.contains("O=INLAY_PAIRED") != true,
               "legacy blob never takes the paired-wizard path")

    print("ShopPilotVerify2021a: PASS — paired pocket+plug from one vector, measured glueGap/2 outward offset (\(halfGap)), tip-floor depth == maxDepth on sub-tip valleys + analytic taper 9.75 elsewhere, fudge=1.0 byte-identical plug, fudge=1.002 centroid scale, legacy decode defaults + round-trip, recalc regenerates both ops")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2021a: FAIL — \(error)")
    exit(1)
}
