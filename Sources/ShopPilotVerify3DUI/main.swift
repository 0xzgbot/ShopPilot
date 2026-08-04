import Foundation
import ShopPilotCore

/// SPK-3D-UI verify (CLT machine, no XCTest).
/// Proves the Model stage data + math spine (the SwiftUI canvas is covered by
/// the app build):
///   1. VISUALIZER: normalized height (peak → 1, floor → 0, outside → 0);
///      grayscale heightmap pixels (peak cell = 255, floor = 0, RGBA layout,
///      correct dimensions, nearest-neighbor upscale); contour counts are
///      monotonically decreasing bands over the pyramid relief.
///   2. CAMERA: zoom clamps to [0.1, 8]; cellToView → viewToCell round-trips
///      to the same cell; pan shifts the view; zoom(by:) compounds.
///   3. GENERATORS: Rough 3D + Finish 3D compute from the fixture relief and
///      emit their markers (the Model stage buttons call these session
///      methods, which add tree nodes + persist params).
///   4. PERSIST: the relief round-trips through Job Codable (`stlHeightfield`,
///      optional → legacy docs decode unchanged), so a saved .shoppilot keeps
///      the Model stage's data.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// 5×5 pyramid: exact 8mm peak at center cell (2,2), linear falloff to 0 at
/// the edges.
func pyramid5() -> HeightfieldData {
    var h: [Double] = []
    for j in 0..<5 {
        for i in 0..<5 {
            let dx = abs(Double(i) - 2.0) / 2.0
            let dy = abs(Double(j) - 2.0) / 2.0
            h.append(8.0 * (1.0 - min(1.0, max(dx, dy))))
        }
    }
    return HeightfieldData(width: 5, height: 5, cellSizeMm: 1.0, minX: 0, minY: 0, heights: h)
}

func main() throws {
    let hf = pyramid5()
    try expect(abs(hf.maxHeight - 8.0) < 1e-9, "fixture peaks at 8mm")

    // ── 1. Visualizer. ─────────────────────────────────────────────────────
    try expect(abs(HeightfieldVisualizer.normalizedHeight(hf, xCell: 2, yCell: 2) - 1.0) < 1e-9,
               "peak cell normalized to 1")
    try expect(abs(HeightfieldVisualizer.normalizedHeight(hf, xCell: 0, yCell: 0)) < 1e-9,
               "edge cell normalized to 0")
    try expect(HeightfieldVisualizer.normalizedHeight(hf, xCell: -1, yCell: 0) == 0,
               "outside-grid cell → 0")
    try expect(HeightfieldVisualizer.normalizedHeight(hf, xCell: 0, yCell: 99) == 0,
               "out-of-range cell → 0")

    let (pixels, w, h) = HeightfieldVisualizer.heightmapGrayscale(hf)
    try expect(w == 5 && h == 5, "grayscale dims match grid (got \(w)×\(h))")
    try expect(pixels.count == 5 * 5 * 4, "RGBA byte count (got \(pixels.count))")
    let peakIdx = (2 * 5 + 2) * 4
    try expect(pixels[peakIdx] == 255 && pixels[peakIdx + 3] == 255,
               "peak pixel is white + opaque")
    try expect(pixels[0] == 0, "edge pixel is black")
    // Nearest-neighbor upscale keeps exact values.
    let (big, bw, bh) = HeightfieldVisualizer.heightmapGrayscale(hf, pixelSize: 2)
    try expect(bw == 10 && bh == 10, "2× upscale dims (got \(bw)×\(bh))")
    let bigPeak = (5 * 10 + 5) * 4 // center of the 4×4 peak block
    try expect(big[bigPeak] == 255, "upscaled peak stays 255")

    let contours = HeightfieldVisualizer.contourCounts(hf, levels: 5)
    try expect(contours.count == 5, "five contour bands")
    try expect(contours.first! > contours.last!, "band sizes shrink with height (got \(contours))")
    // Hand-derived: the 5×5 pyramid's rim cells are 0 (falloff reaches the
    // edges) → cells with height ≥ 1.6mm (norm ≥ 0.2) are the 3×3 inner block
    // = 9; the top band (norm ≥ 1.0) is only the center cell = 1.
    try expect(contours.first! == 9, "lowest band = inner 3×3 block (got \(contours.first!))")
    try expect(contours.last! == 1, "top band = peak cell only (got \(contours.last!))")

    // ── 2. Camera. ─────────────────────────────────────────────────────────
    var cam = HeightfieldCamera(cellSizeMm: 1.0)
    try expect(abs(cam.zoom - 1.0) < 1e-9, "default zoom 1 (fit)")
    let (vx, vy) = cam.cellToView(xCell: 2, yCell: 3)
    try expect(abs(vx - 2.0) < 1e-9 && abs(vy - 3.0) < 1e-9, "zoom-1 view maps cell → world px")
    let cell = cam.viewToCell(x: vx, y: vy, width: 5, height: 5)
    try expect(cell.xCell == 2 && cell.yCell == 3, "viewToCell inverts cellToView")

    cam.zoom(by: 2.0)
    try expect(abs(cam.zoom - 2.0) < 1e-9, "zoom(by: 2) doubles")
    let (vx2, vy2) = cam.cellToView(xCell: 1, yCell: 0)
    try expect(abs(vx2 - 2.0) < 1e-9, "zoomed cell spans 2px")
    let back = cam.viewToCell(x: vx2, y: vy2, width: 5, height: 5)
    try expect(back.xCell == 1 && back.yCell == 0, "zoomed round-trip holds")

    var cam2 = HeightfieldCamera(cellSizeMm: 1.0)
    cam2.panX = 5; cam2.panY = -3
    let (px, py) = cam2.cellToView(xCell: 0, yCell: 0)
    try expect(abs(px - 5.0) < 1e-9 && abs(py - (-3.0)) < 1e-9, "pan shifts the origin")

    var cam3 = HeightfieldCamera(cellSizeMm: 1.0)
    cam3.zoom = 100
    try expect(abs(cam3.zoom - 8.0) < 1e-9, "zoom clamps at 8")
    cam3.zoom = 0.001
    try expect(abs(cam3.zoom - 0.1) < 1e-9, "zoom clamps at 0.1")

    // ── 3. Generators (Model stage buttons). ───────────────────────────────
    let rough = HeightfieldRoughEngine.compute(
        heightfield: hf,
        params: HeightfieldRoughParams()
    )
    try expect(rough.gcodeLines.contains("O=ROUGH_3D"), "Rough 3D emits its marker")
    let finish = HeightfieldFinishEngine.compute(
        heightfield: hf,
        params: HeightfieldFinishParams()
    )
    try expect(finish.gcodeLines.contains("O=FINISH_3D"), "Finish 3D emits its marker")

    // ── 4. Persist — relief survives the package. ──────────────────────────
    var job = Job(name: "Relief Job")
    job.stlHeightfield = hf
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.stlHeightfield != nil, "relief round-trips through Job")
    try expect(abs(decoded.stlHeightfield!.maxHeight - 8.0) < 1e-9,
               "relief height preserved after round-trip")
    // Legacy doc without the relief decodes as nil.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","sheets":[],"createdAt":0,"updatedAt":0,"documentVariables":[],"drivenDimensions":[],"vcarvePasses":0,"vcarveTimeSeconds":0}"#
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.stlHeightfield == nil, "legacy Job without relief decodes fine")

    print("ShopPilotVerify3DUI: PASS — visualizer (normalized/gray/contours), camera (zoom/pan/round-trip/clamp), "
          + "Rough3D+Finish3D markers, relief persists via Job")
}

do {
    try main()
} catch {
    print("ShopPilotVerify3DUI: FAIL — \(error)")
    exit(1)
}
