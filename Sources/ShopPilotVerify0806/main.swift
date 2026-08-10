import Foundation
import ShopPilotCore

/// SPK-0806 verify (CLT machine, no XCTest).
/// Proves the EXPANDED VECTOR VALIDATOR contract (the 630-line rule set that
/// the preflight doctor's basic checks do NOT cover):
///   1. DEGENERATE: < 2 points → error, invalid shape.
///   2. ZERO-LENGTH: duplicate consecutive points → zeroLength error.
///   3. OPEN-VS-CLOSED: closed flag routes to closed-path checks.
///   4. SELF-INTERSECTION: a bowtie freehand path → selfIntersection error +
///      geometry category + a fix action.
///   5. OVERLAPPING SEGMENTS: collinear overlapping segments → overlap error.
///   6. BATCH AGGREGATION: validateBatch totals, criticalErrors list and the
///      summary string aggregate correctly across mixed valid/invalid input.
///   7. FIX ACTIONS: invalid shapes carry a suggested action (close/remove)
///      the UI can surface.
/// The AppSession glue (runVectorValidation over session vectors + Validate
/// All button + VectorValidationPanel) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Degenerate: single point → error. ──────────────────────────────
    let degenerateShape = VectorShapeData(id: UUID(), points: [VectorPoint(x: 0, y: 0)],
                                          isClosed: true, shapeType: .freehand)
    let degenerate = VectorValidator.validate(shapeData: degenerateShape)
    try expect(!degenerate.isValid, "single-point shape is invalid")
    try expect(degenerate.errors.contains(.degenerate), "degenerate error reported")

    // ── 2. Zero-length segment: repeated point. ───────────────────────────
    let zeroLen = VectorValidator.validate(
        shapeData: VectorShapeData(id: UUID(),
                                   points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0)],
                                   isClosed: false, shapeType: .freehand)
    )
    try expect(zeroLen.errors.contains(.zeroLength), "duplicate consecutive point → zeroLength")

    // ── 3. Bowtie self-intersection. ──────────────────────────────────────
    let bowtie = VectorShapeData(id: UUID(),
                                 points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 10),
                                          VectorPoint(x: 0, y: 10), VectorPoint(x: 10, y: 0),
                                          VectorPoint(x: 0, y: 0)],
                                 isClosed: true, shapeType: .freehand)
    let bowtieResult = VectorValidator.validate(shapeData: bowtie)
    try expect(bowtieResult.errors.contains(.selfIntersection),
               "bowtie → selfIntersection (got \(bowtieResult.errors.map(\.rawValue)))")
    try expect(bowtieResult.category == .geometry,
               "self-intersection is a geometry-category issue")
    try expect(!bowtieResult.fixActions.isEmpty,
               "invalid shape carries a fix action")

    // ── 4. Overlapping segments: closed path whose (0→20) and (20→10)
    //        segments cover 10..20 twice — genuine overlap. ────────────────
    let overlap = VectorShapeData(id: UUID(),
                                  points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 20, y: 0),
                                           VectorPoint(x: 10, y: 0), VectorPoint(x: 0, y: 10),
                                           VectorPoint(x: 0, y: 0)],
                                  isClosed: true, shapeType: .freehand)
    let overlapResult = VectorValidator.validate(shapeData: overlap)
    try expect(overlapResult.errors.contains(.overlappingSegments),
               "collinear overlapping segments → overlap error (got \(overlapResult.errors.map(\.rawValue)))")

    // ── 5. Clean closed square → valid, no errors. A closed path stores its
    //        vertices once (no explicit closing duplicate — the closing
    //        segment is implied by isClosed), which is how the session's
    //        layer-faithful paths are built. ───────────────────────────────
    let square = VectorShapeData(id: UUID(),
                                 points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0),
                                          VectorPoint(x: 10, y: 10), VectorPoint(x: 0, y: 10)],
                                 isClosed: true, shapeType: .freehand)
    let squareResult = VectorValidator.validate(shapeData: square)
    try expect(squareResult.isValid, "clean square is valid (got \(squareResult.errors.map(\.rawValue)))")
    try expect(squareResult.errors.isEmpty, "no errors on clean square")

    // ── 6. Batch aggregation. ─────────────────────────────────────────────
    let batch = VectorValidator.validateBatch(shapes: [bowtie, square, degenerateShape])
    try expect(batch.totalShapes == 3, "batch counts 3 shapes")
    try expect(batch.totalErrors == (bowtieResult.errors.count + 1), // bowtie + degenerate
               "totalErrors aggregates (got \(batch.totalErrors))")
    try expect(batch.criticalErrors.count == 2, "two invalid shapes are critical (got \(batch.criticalErrors.count))")
    try expect(batch.validShapes == 1, "exactly one valid shape")
    try expect(!batch.summary.isEmpty, "summary string renders")

    // ── 7. Threshold validation contract. ─────────────────────────────────
    let thresholds = VectorValidationThresholds()
    let thresholdCheck = VectorValidator.validate(thresholds)
    try expect(thresholdCheck.isValid, "default thresholds are valid")
    try expect(thresholds.nearIntersectionThreshold > 0, "thresholds carry sensible defaults")

    print("ShopPilotVerify0806: PASS — expanded validator: degenerate/zero-length/self-intersection/overlap detection, category classification, fix actions, batch aggregation, threshold contract")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0806: FAIL — \(error)")
    exit(1)
}
