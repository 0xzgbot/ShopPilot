import Foundation
import ShopPilotCore

/// SPK-0702 verify (CLT machines, no XCTest).
/// Proves the dynamic component-props engine (`ComponentModifierEngine`) and
/// its wiring:
///   1. Height scale multiplies heights (clamped ≥ 0); identity returns the
///      same grid.
///   2. Tilt rotates the relief about the grid center — the peak cell moves
///      to the expected rotated cell; 0° is a no-op; the grid stays the same
///      size (grid-preserving).
///   3. Fade ramps heights 1.0 → (1−amount) across the direction; 0 amount is
///      a no-op; centerOut/radial fade the edges, keeping the center full.
///   4. `ReliefComponent.modifiedHeightfield` applies scale → tilt → fade in
///      order; `ComponentCompositor.composite` folds modified components.
///   5. Persist: component props survive a Job round-trip and legacy JSON
///      without the new keys decodes (nil props = unmodified).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

/// A 5×5 grid, cell 1mm, minX=minY=0, with a single 10mm peak at cell (2,2).
func makeFixture() -> HeightfieldData {
    var heights = [Double](repeating: 0, count: 25)
    heights[2 * 5 + 2] = 10.0
    return HeightfieldData(width: 5, height: 5, cellSizeMm: 1.0, minX: 0, minY: 0, heights: heights)
}

func main() throws {
    let hf = makeFixture()

    // ── 1. Height scale ───────────────────────────────────────────────────
    let scaled = ComponentModifierEngine.heightScaled(hf, by: 2.0)
    try expectClose(scaled.heights[2 * 5 + 2], 20.0, "scale ×2 doubles the peak")
    try expectClose(scaled.maxHeight, 20.0, "scaled maxHeight")
    try expect(scaled.width == hf.width && scaled.height == hf.height, "scale keeps grid dims")

    let halved = ComponentModifierEngine.heightScaled(hf, by: 0.5)
    try expectClose(halved.heights[2 * 5 + 2], 5.0, "scale ×0.5 halves the peak")

    let identity = ComponentModifierEngine.heightScaled(hf, by: 1.0)
    try expect(identity.heights == hf.heights, "scale 1.0 is a no-op (same heights)")

    // Negative scale clamps at 0.
    let neg = ComponentModifierEngine.heightScaled(hf, by: -1.0)
    try expectClose(neg.heights[2 * 5 + 2], 0.0, "negative scale clamps to 0")

    // ── 2. Tilt ───────────────────────────────────────────────────────────
    let noTilt = ComponentModifierEngine.tilted(hf, by: 0)
    try expect(noTilt.heights == hf.heights, "0° tilt is a no-op")

    // 90° CCW about center (world +y up): the peak at cell (2,2) — grid
    // center — stays at (2,2) for a centered peak. Use an OFF-CENTER peak to
    // prove rotation: peak at cell (4,1) → world (4.5, 1.5); center (2.5, 2.5);
    // inverse-rotating each output cell samples the input at
    // (cx + dx·cos + dy·sin, cy − dx·sin + dy·cos); the output cell whose
    // sample lands on (4.5, 1.5) is cell (3,4) → index 4·5+3 = 23.
    var offCenter = [Double](repeating: 0, count: 25)
    offCenter[1 * 5 + 4] = 10.0
    let offHF = HeightfieldData(width: 5, height: 5, cellSizeMm: 1.0, minX: 0, minY: 0, heights: offCenter)
    let rotated = ComponentModifierEngine.tilted(offHF, by: 90)
    let maxIndex = rotated.heights.firstIndex(of: rotated.heights.max() ?? 0) ?? -1
    try expect(maxIndex == 4 * 5 + 3, "90° tilt moves the off-center peak to cell (3,4) (got \(maxIndex / 5),\(maxIndex % 5))")
    try expectClose(rotated.heights[maxIndex], 10.0, "tilt preserves the peak height")
    try expect(rotated.width == offHF.width && rotated.height == offHF.height, "tilt keeps grid dims")

    // ── 3. Fade ───────────────────────────────────────────────────────────
    let fadeLTR = ComponentModifierEngine.faded(hf, amount: 0.5, direction: .leftToRight)
    // Peak at (2,2): factor = 1 − 0.5·(2/4) = 0.75 → 7.5
    try expectClose(fadeLTR.heights[2 * 5 + 2], 7.5, "leftToRight fade 0.5 at center column")
    // Column 4 factor = 1 − 0.5·(4/4) = 0.5; column 0 factor = 1.0.
    let col0 = ComponentModifierEngine.faded(hf, amount: 0.5, direction: .leftToRight)
    try expectClose(col0.heights[0], 0.0, "col0 flat cell stays 0")
    let col4 = ComponentModifierEngine.faded(hf, amount: 0.5, direction: .leftToRight)
    try expectClose(col4.heights[2 * 5 + 4], 0.0, "col4 flat cell stays 0 (was 0)")

    let noFade = ComponentModifierEngine.faded(hf, amount: 0.0, direction: .leftToRight)
    try expect(noFade.heights == hf.heights, "0 fade is a no-op")

    // CenterOut keeps the center full, fades the corners.
    var full = [Double](repeating: 4.0, count: 25)
    let fullHF = HeightfieldData(width: 5, height: 5, cellSizeMm: 1.0, minX: 0, minY: 0, heights: full)
    let centerOut = ComponentModifierEngine.faded(fullHF, amount: 1.0, direction: .centerOut)
    try expectClose(centerOut.heights[2 * 5 + 2], 4.0, "centerOut keeps the center full")
    try expectClose(centerOut.heights[0], 0.0, "centerOut fades the corner to 0 at amount 1")

    // ── 4. Composite with modified components ─────────────────────────────
    var component = ReliefComponent(name: "A", heightfield: hf, combineMode: .combineAdd)
    component.heightScale = 2.0
    try expectClose(component.modifiedHeightfield.heights[2 * 5 + 2], 20.0, "modifiedHeightfield applies scale")

    var componentB = ReliefComponent(name: "B", heightfield: hf, combineMode: .combineAdd)
    componentB.fadeAmount = 0.5
    componentB.fadeDirection = .leftToRight
    // Composite A (peak 20 after scale) with B (peak 7.5 after fade): Add caps at max(20, 7.5) = 20.
    let composite = ComponentCompositor.composite([component, componentB])
    try expect(composite != nil, "composite of modified components succeeds")
    try expectClose(composite!.heights[2 * 5 + 2], 20.0, "composite peak = max(20, 7.5) = 20")

    // ── 5. Persist ────────────────────────────────────────────────────────
    let job = Job(name: "Props")
    var jobWith = job
    jobWith.reliefComponents = [component, componentB]
    let encoder = JSONEncoder()
    let data = try encoder.encode(jobWith)
    let decoder = JSONDecoder()
    let roundTripped = try decoder.decode(Job.self, from: data)
    try expect(roundTripped.reliefComponents?.count == 2, "props round-trip component count")
    try expectClose(roundTripped.reliefComponents![0].heightScale ?? 0, 2.0, "props round-trip heightScale")
    try expect(roundTripped.reliefComponents![1].fadeDirection == .leftToRight, "props round-trip fadeDirection")

    // Legacy JSON without the new keys decodes as nil props (synthesized
    // Codable requires every non-optional Job key: id, sheets,
    // documentVariables, drivenDimensions, vcarvePasses, vcarveTimeSeconds,
    // createdAt, updatedAt).
    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Legacy","sheets":[],"documentVariables":[],"drivenDimensions":[],"vcarvePasses":0,"vcarveTimeSeconds":0,"createdAt":0,"updatedAt":0,"reliefComponents":[{"id":"\(UUID().uuidString)","name":"Old","heightfield":{"width":2,"height":2,"cellSizeMm":1,"minX":0,"minY":0,"heights":[1,1,1,1]},"combineMode":"combineAdd","visible":true}]}
    """
    let legacy = try decoder.decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.reliefComponents?.first?.heightScale == nil, "legacy decode: heightScale nil")
    try expect(legacy.reliefComponents?.first?.fadeDirection == nil, "legacy decode: fadeDirection nil")
    try expect(legacy.reliefComponents?.first?.modifiedHeightfield.heights == [1, 1, 1, 1], "legacy decode: unmodified grid")

    print("ShopPilotVerifyDynamicProps: PASS — height scale, tilt rotation, directional fade, composite with props, persist + legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyDynamicProps: FAIL — \(error)")
    exit(1)
}
