import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1003 verify (CLT machine, no XCTest).
/// Proves the PERFORMANCE contract — the design + relief kernel stays
/// interactive at scale:
///   1. 10K VECTORS: generating + translating 10,000 closed shapes completes
///      in a bounded time (< 10s on this machine) and every shape survives
///      the transform intact (count + geometry checks).
///   2. OFFSET BATCH: offsetting a 1,000-shape batch stays bounded — the
///      kernel path Cut uses for profile offsets doesn't degrade superlinearly
///      on a large selection.
///   3. LARGE RELIEF: mirroring + height-sampling a 512×512 heightfield
///      (262,144 cells — a "large relief") completes quickly and keeps
///      world coordinates exact.
///   4. TOOLPATH SCALE: Profile engine on a 500-vector job emits G-code in
///      bounded time — the Cut stage's recalc path stays interactive.
/// Budgets are generous (CI machines vary); the point is to catch
/// accidentally-quadratic regressions, not micro-benchmarks.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func makeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> VectorShape {
    .rectangle(origin: VectorPoint(x: x, y: y), width: w, height: h)
}

func main() throws {
    // ── 1. 10K vectors: generate + transform in bounded time. ─────────────
    let count = 10_000
    let genStart = Date()
    var shapes: [VectorShape] = []
    shapes.reserveCapacity(count)
    for i in 0..<count {
        let x = Double(i % 100) * 12
        let y = Double(i / 100) * 12
        shapes.append(makeRect(x, y, 8, 6))
    }
    let genSeconds = Date().timeIntervalSince(genStart)
    try expect(shapes.count == count, "10k shapes generated")

    let transformStart = Date()
    let moved = shapes.map { $0.translated(by: 5, 3) }
    let transformSeconds = Date().timeIntervalSince(transformStart)
    try expect(moved.count == count, "10k shapes transformed")
    // Spot-check geometry survived (index 0 and the last).
    try expect(moved[0].boundingRect.minX == 5 && moved[0].boundingRect.minY == 3,
               "first shape translated correctly")
    try expect(abs(moved[count - 1].boundingRect.minX - (99 * 12 + 5)) < 1e-9,
               "last shape translated correctly")

    let budget = 10.0
    try expect(genSeconds + transformSeconds < budget,
               "10k generate+transform in \(String(format: "%.2f", genSeconds + transformSeconds))s < \(budget)s")

    // ── 2. Offset batch (1,000 shapes) stays bounded. ─────────────────────
    let offsetShapes = Array(shapes.prefix(1000))
    let offsetStart = Date()
    var offsetCount = 0
    for shape in offsetShapes {
        offsetCount += VectorOffsetCalculator.offsetShape(shape, by: 1.0).count
    }
    let offsetSeconds = Date().timeIntervalSince(offsetStart)
    try expect(offsetCount >= 1000, "offset batch produced output (\(offsetCount) shapes)")
    try expect(offsetSeconds < 10.0,
               "1k offset batch in \(String(format: "%.2f", offsetSeconds))s < 10s")

    // ── 3. Large relief (512×512): mirror + sample. ───────────────────────
    let w = 512
    let h = 512
    var heights = [Double](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            heights[y * w + x] = Double((x + y) % 32) // deterministic ramp
        }
    }
    let grid = HeightfieldData(width: w, height: h, cellSizeMm: 0.5, minX: 0, minY: 0, heights: heights)
    let mirrorStart = Date()
    let mirrored = LevelMirrorEngine.mirror(grid, axis: .both)
    let mirrorSeconds = Date().timeIntervalSince(mirrorStart)
    try expect(mirrored.heights.count == w * h, "large relief mirror keeps cell count")
    try expect(mirrored.heights[0] == heights[(h - 1) * w + (w - 1)],
               "mirrored corner reads the opposite source corner")
    try expect(mirrorSeconds < 5.0,
               "512×512 mirror in \(String(format: "%.2f", mirrorSeconds))s < 5s")

    let sampleStart = Date()
    var sampleSum = 0.0
    var samples = 0
    for i in 0..<20_000 {
        let x = Double((i * 7) % w) * 0.5
        let y = Double((i * 13) % h) * 0.5
        if let v = grid.height(atX: x, y: y) {
            sampleSum += v
            samples += 1
        }
    }
    let sampleSeconds = Date().timeIntervalSince(sampleStart)
    try expect(samples == 20_000, "world-coordinate sampling covers the grid")
    try expect(sampleSum > 0, "samples carry values")
    try expect(sampleSeconds < 2.0,
               "20k height samples in \(String(format: "%.2f", sampleSeconds))s < 2s")

    // ── 4. Toolpath scale: Profile on 500 vectors stays bounded. ──────────
    let toolpathShapes = Array(shapes.prefix(500))
    let pathVectors = toolpathShapes.map { shape -> VectorPath in
        let bb = shape.boundingRect
        return VectorPath(
            points: [
                VectorPoint(x: bb.minX, y: bb.minY), VectorPoint(x: bb.maxX, y: bb.minY),
                VectorPoint(x: bb.maxX, y: bb.maxY), VectorPoint(x: bb.minX, y: bb.maxY),
                VectorPoint(x: bb.minX, y: bb.minY),
            ],
            isClosed: true
        )
    }
    let tpStart = Date()
    var params = ProfileToolpathParams()
    params.cutMode = .onCut
    params.feedRateMmPerMin = 1500
    let tpResult = ProfileToolpathEngine.compute(
        vectors: pathVectors, params: params, material: nil, stockHeightMm: 12.0
    )
    let tpSeconds = Date().timeIntervalSince(tpStart)
    try expect(!tpResult.gcodeLines.isEmpty, "profile engine emits G-code at scale")
    try expect(tpSeconds < 15.0,
               "500-vector profile in \(String(format: "%.2f", tpSeconds))s < 15s")

    print("ShopPilotVerify1003: PASS — 10k vectors transform \(String(format: "%.2f", genSeconds + transformSeconds))s, 1k offset \(String(format: "%.2f", offsetSeconds))s, 512×512 mirror \(String(format: "%.2f", mirrorSeconds))s + 20k samples \(String(format: "%.2f", sampleSeconds))s, 500-vector profile \(String(format: "%.2f", tpSeconds))s")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1003: FAIL — \(error)")
    exit(1)
}
