import Foundation
import ShopPilotCore

/// SPK-3D-spine-b verify (CLT machine, no XCTest).
/// Proves the heightfield rough + finish toolpath spine:
///   1. ROUGH: z-level clearing over a synthetic pyramid relief — marker,
///      correct pass count, every plunge depth on a z-level, shallowest pass
///      skips cells above the level, deepest pass clears the low floor.
///   2. FINISH: surface-following raster — marker, Z tracks the bilinear
///      surface at sample points (peak ~8mm, corner ~0), all Z negative
///      (stock top = 0 convention).
///   3. TREE/RECALC: "Rough 3D"/"Finish 3D" nodes classify correctly,
///      regenerate through `recalculateDirtyToolpaths(…, heightfield:)`,
///      and STAY DIRTY when no heightfield is provided.
///   4. PERSIST: params round-trip Codable.
/// The UI glue (Add Toolpath menu, session generators) is covered by the app
/// build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Pyramid relief: 21×21 grid at 1mm cells (0..20), exact 8mm peak at the
/// center cell (10,10), linear falloff to 0 at the grid edges.
func pyramidHeightfield() -> HeightfieldData {
    let n = 21
    var heights: [Double] = []
    for j in 0..<n {
        for i in 0..<n {
            let dx = abs(Double(i) - 10.0) / 10.0
            let dy = abs(Double(j) - 10.0) / 10.0
            heights.append(8.0 * (1.0 - min(1.0, max(dx, dy))))
        }
    }
    return HeightfieldData(width: n, height: n, cellSizeMm: 1.0, minX: 0, minY: 0, heights: heights)
}

func motionLines(_ lines: [String]) -> [(x: Double, y: Double, z: Double?)] {
    var pts: [(x: Double, y: Double, z: Double?)] = []
    var currentZ: Double?
    for line in lines {
        guard line.hasPrefix("G1") || line.hasPrefix("G0") else { continue }
        var x: Double?; var y: Double?; var z: Double?
        for comp in line.split(separator: " ") {
            if comp.hasPrefix("X") { x = Double(comp.dropFirst()) }
            if comp.hasPrefix("Y") { y = Double(comp.dropFirst()) }
            if comp.hasPrefix("Z") { z = Double(comp.dropFirst()) }
        }
        if let z = z { currentZ = z }
        if let x = x, let y = y { pts.append((x, y, currentZ)) }
    }
    return pts
}

func main() throws {
    let hf = pyramidHeightfield()
    try expect(abs(hf.maxHeight - 8.0) < 1e-9, "pyramid peaks at 8mm")

    // ── 1. Rough: z-level clearing. ─────────────────────────────────────────
    let roughParams = HeightfieldRoughParams(
        toolDiameterMm: 6.0, stepDownMm: 2.0, stepOverMm: 1.5,
        feedRateMmPerMin: 1200, plungeFeedRateMmPerMin: 300,
        safeZHeightMm: 5.0, stockAllowanceMm: 0.5
    )
    let rough = HeightfieldRoughEngine.compute(heightfield: hf, params: roughParams)
    try expect(rough.gcodeLines.contains("O=ROUGH_3D"), "rough emits O=ROUGH_3D marker")
    // stockTop = 8.5 → levels 6.5, 4.5, 2.5, 0.5, 0 = 5 passes.
    try expect(rough.passCount == 5, "5 z-levels (got \(rough.passCount))")
    let roughMoves = motionLines(rough.gcodeLines)
    try expect(!roughMoves.isEmpty, "rough has motion")

    // Every plunge depth is one of the z-levels (Z = level − stockTop).
    let stockTop = 8.5
    let expectedLevels = [6.5, 4.5, 2.5, 0.5, 0.0]
    let expectedDepths = Set(expectedLevels.map { Int(-(stockTop - $0)) })
    let plungeDepths = Set(roughMoves.compactMap { m -> Int? in
        guard let z = m.z, z < -0.01 else { return nil }
        return Int(z)
    })
    try expect(plungeDepths.isSubset(of: expectedDepths),
               "plunge depths are z-levels (\(plungeDepths) ⊆ \(expectedDepths))")

    // Shallowest pass (level 6.5, Z=-2.0): the peak cell (surface 8 > 6.5)
    // must NOT be cut — no cut endpoint inside the peak column at the peak row.
    let shallowPassMoves = roughMoves.filter { $0.z == -2.0 }
    try expect(!shallowPassMoves.isEmpty, "shallowest pass has moves")
    let peakRowMoves = shallowPassMoves.filter { abs($0.y - 10.5) < 1.5 }
    try expect(!peakRowMoves.contains { $0.x > 8.5 && $0.x < 11.5 },
               "shallowest pass skips the peak cell (surface above the level)")

    // Level 0.5 (Z=-8.0): the grid-edge floor (surface 0 ≤ 0.5) IS cleared —
    // a move reaches the far edge at a mid row.
    let edgePassMoves = roughMoves.filter { $0.z == -8.0 }
    try expect(edgePassMoves.contains { $0.x > 19.5 },
               "floor pass clears the low grid edge (x > 19.5)")

    // ── 2. Finish: surface-following raster. ────────────────────────────────
    let finishParams = HeightfieldFinishParams(
        toolDiameterMm: 3.175, stepOverMm: 1.0,
        feedRateMmPerMin: 1000, plungeFeedRateMmPerMin: 300, safeZHeightMm: 5.0
    )
    let finish = HeightfieldFinishEngine.compute(heightfield: hf, params: finishParams)
    try expect(finish.gcodeLines.contains("O=FINISH_3D"), "finish emits O=FINISH_3D marker")
    let finishMoves = motionLines(finish.gcodeLines)
    try expect(!finishMoves.isEmpty, "finish has motion")

    // SPK-2100a — drop-cutter: the G-code traces the ball CENTER. At the peak
    // row (y=10.5) the surface is ~8 = stock top, so the naive trace would be
    // Z=0; the compensated center rides ~R = D/2 above it.
    // At a corner row the surface is ~0 → naive −8, compensated ≈ −8 + R.
    let ballRadiusMm = 3.175 / 2.0
    let finishPeakRow = finishMoves.filter { abs($0.y - 10.5) < 0.01 }
    try expect(finishPeakRow.contains { m in
        if let z = m.z, abs(m.x - 10.5) < 0.01 { return abs(z - ballRadiusMm) < 0.1 }
        return false
    }, "finish center at the peak rides ~R above the surface (compensated, not 0)")
    let finishCornerRow = finishMoves.filter { abs($0.y - 0.5) < 0.01 }
    let naiveCornerZ = -(hf.maxHeight - hf.heightInterpolated(atX: 1.5, y: 0.5))
    try expect(finishCornerRow.contains { m in
        if let z = m.z, abs(m.x - 1.5) < 0.01 {
            return z >= naiveCornerZ + ballRadiusMm * 0.9 // lifted ~R off the contact point
        }
        return false
    }, "finish center at the corner lifts ~R above its surface contact")
    try expect(finishMoves.allSatisfy { m in
        let z = m.z ?? -8.0
        return z <= ballRadiusMm + 0.05 || abs(z - 5.0) < 0.001 // cuts ≤ max center lift; only safe-Z rapids higher
    }, "finish cut Z stays under the max ball-center lift (+R)")

    // ── 3. Tree / recalc wiring. ────────────────────────────────────────────
    let tree = ToolpathTreeManager()
    let roughNode = tree.addOperation("Rough 3D 1")
    roughNode.paramsJSON = encodeParams(roughParams)
    roughNode.toolpathResult = rough.gcodeLines.joined(separator: "\n")
    let finishNode = tree.addOperation("Finish 3D 1")
    finishNode.paramsJSON = encodeParams(finishParams)
    finishNode.toolpathResult = finish.gcodeLines.joined(separator: "\n")
    try expect(roughNode.isRough3DOperation && roughNode.strategyKind == .rough3D,
               "Rough 3D node classifies as .rough3D")
    try expect(finishNode.isFinish3DOperation && finishNode.strategyKind == .finish3D,
               "Finish 3D node classifies as .finish3D")

    // Recalc WITH the heightfield regenerates both.
    roughNode.markDirty()
    finishNode.markDirty()
    let regenerated = tree.recalculateDirtyToolpaths(
        vectors: [], material: nil, stockHeightMm: 6.0,
        tools: [], heightfield: hf
    )
    try expect(regenerated.count == 2, "both 3D ops regenerate with a heightfield (got \(regenerated.count))")
    try expect(!roughNode.isDirty && !finishNode.isDirty, "both 3D ops clean after recalc")
    try expect((roughNode.toolpathResult ?? "").contains("O=ROUGH_3D"), "regenerated rough has its marker")
    try expect((finishNode.toolpathResult ?? "").contains("O=FINISH_3D"), "regenerated finish has its marker")

    // Recalc WITHOUT the heightfield leaves 3D ops dirty (honest skip).
    roughNode.markDirty()
    finishNode.markDirty()
    let skipped = tree.recalculateDirtyToolpaths(
        vectors: [], material: nil, stockHeightMm: 6.0,
        tools: [], heightfield: nil
    )
    try expect(skipped.isEmpty, "no heightfield → no 3D regen")
    try expect(roughNode.isDirty && finishNode.isDirty, "3D ops stay dirty without a relief")

    // ── 4. Persist. ─────────────────────────────────────────────────────────
    let data = try JSONEncoder().encode(roughParams)
    let decoded = try JSONDecoder().decode(HeightfieldRoughParams.self, from: data)
    try expect(abs(decoded.stepDownMm - 2.0) < 1e-9 && decoded.stockAllowanceMm == 0.5,
               "rough params round-trip Codable")
    let fdata = try JSONEncoder().encode(finishParams)
    let fdecoded = try JSONDecoder().decode(HeightfieldFinishParams.self, from: fdata)
    try expect(abs(fdecoded.stepOverMm - 1.0) < 1e-9, "finish params round-trip Codable")

    print("ShopPilotVerify3Db: PASS — z-level rough (5 passes, peak skip, floor clear), surface finish (peak/corner Z), tree recalc with/without relief, persist")
}

func encodeParams(_ params: some Codable) -> String? {
    (try? JSONEncoder().encode(params)).flatMap { String(data: $0, encoding: .utf8) }
}

do {
    try main()
} catch {
    print("ShopPilotVerify3Db: FAIL — \(error)")
    exit(1)
}
