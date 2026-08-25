import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-2020a0 — polyline join-with-gap-tolerance + zero-span delete.

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

func pts(_ pairs: [(Double, Double)]) -> [VectorPoint] {
    pairs.map { VectorPoint(x: $0.0, y: $0.1) }
}

func main() throws {
    // ── AC1 — two freehand polylines with a 0.05 mm endpoint gap merge into
    // one under tolerance 0.1 (default). ────────────────────────────────────
    let a = VectorShape.freehand(points: pts([(0, 0), (10, 0)]))
    let b = VectorShape.freehand(points: pts([(10.05, 0), (20, 0)]))

    let (joined, remaining) = ShapeJoinEngine.joinAll(shapes: [a, b], tolerance: 0.1)
    try expect(joined.count == 1, "gap 0.05 ≤ tolerance 0.1 → exactly one merged polyline, got \(joined.count)")
    try expect(remaining.isEmpty, "no leftovers when everything chains")
    guard case .freehand(let mergedPts)? = joined.first else {
        throw VerifyError.failed("merged result must be a freehand polyline")
    }
    try expect(mergedPts.count == 3, "merged polyline must carry 3 points (coincident endpoint dropped), got \(mergedPts.count)")
    try expect(abs(mergedPts[0].x - 0) < 1e-12 && abs(mergedPts[2].x - 20) < 1e-12,
               "merged endpoints must span 0→20")
    try expect(abs(mergedPts[1].x - 10) < 1e-12,
               "interior point is a's coincident endpoint; b's snapped start dropped")

    // Default parameter form also joins.
    let (joinedDefault, _) = ShapeJoinEngine.joinAll(shapes: [a, b])
    try expect(joinedDefault.count == 1, "default tolerance is 0.1 mm")

    // Chain of three: c continues from the merged end with another small gap.
    let c = VectorShape.freehand(points: pts([(20.08, 0), (30, 0)]))
    let (joined3, rem3) = ShapeJoinEngine.joinAll(shapes: [a, b, c], tolerance: 0.1)
    try expect(joined3.count == 1 && rem3.isEmpty, "three polylines chain into one")

    // ── AC2 — zero tolerance leaves them separate (legacy behaviour). ───────
    let (joinedZero, remainingZero) = ShapeJoinEngine.joinAll(shapes: [a, b], tolerance: 0)
    try expect(joinedZero.isEmpty && remainingZero.count == 2,
               "tolerance=0 with a real gap must not join; pass-through both shapes")
    // Exactly coincident endpoints still join at tolerance=0 (today's behaviour).
    let exactB = VectorShape.freehand(points: pts([(10, 0), (20, 0)]))
    let (joinedExact, _) = ShapeJoinEngine.joinAll(shapes: [a, exactB], tolerance: 0)
    try expect(joinedExact.count == 1, "exactly-coincident endpoints join at tolerance=0")

    // Non-freehand shapes pass through untouched.
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 5, height: 5)
    let line = VectorShape.line(start: VectorPoint(x: 100, y: 100), end: VectorPoint(x: 110, y: 100))
    let (jMixed, rMixed) = ShapeJoinEngine.joinAll(shapes: [rect, a, line, b], tolerance: 0.1)
    try expect(jMixed.count == 1, "only the freehands merge in mixed input")
    try expect(rMixed.count == 2, "rect + unattached line pass through")

    // ── AC3 — deleteZeroSpan removes degenerate shapes with counts. ─────────
    let zeroLine = VectorShape.line(start: VectorPoint(x: 1, y: 1), end: VectorPoint(x: 1, y: 1))
    let zeroFreehand = VectorShape.freehand(points: pts([(2, 2), (2, 2)]))
    let singlePt = VectorShape.freehand(points: pts([(3, 3)]))
    let zeroRect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 4, height: 0)
    let zeroCircle = VectorShape.circle(center: VectorPoint(x: 5, y: 5), radius: 0)
    let keepLine = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 9, y: 0))
    let keepFreehand = VectorShape.freehand(points: pts([(0, 0), (1, 1), (2, 0)]))

    let (kept, removed) = ShapeJoinEngine.deleteZeroSpan([
        zeroLine, keepLine, zeroFreehand, singlePt, zeroRect, zeroCircle, keepFreehand
    ])
    try expect(kept.count == 2, "two healthy shapes kept, got \(kept.count)")
    try expect(removed.count == 5, "five degenerate shapes removed, got \(removed.count)")
    try expect(kept.contains(keepLine) && kept.contains(keepFreehand),
               "the healthy shapes are exactly the ones kept")

    // All-healthy input removes nothing; empty input is fine.
    let (keptClean, removedClean) = ShapeJoinEngine.deleteZeroSpan([keepLine, keepFreehand])
    try expect(keptClean.count == 2 && removedClean.isEmpty, "healthy input untouched")
    let (keptEmpty, removedEmpty) = ShapeJoinEngine.deleteZeroSpan([])
    try expect(keptEmpty.isEmpty && removedEmpty.isEmpty, "empty input handled")

    // ── AC4 — session APPLY entry mutates the array and returns counts. ─────
    var shapes: [VectorShape] = [
        a, b,                                  // join into one (gap 0.05)
        VectorShape.freehand(points: pts([(50, 50), (55, 50), (50.02, 50)])), // already-closed-ish loop via tolerance
        zeroLine,                              // zero span → removed
        keepLine                               // passes through
    ]
    let applyResult = ShapeJoinEngine.applyJoinAndCleanup(&shapes, tolerance: 0.1)
    try expect(applyResult.joinedCount >= 1, "at least one join happened, got \(applyResult.joinedCount)")
    try expect(applyResult.closedCount >= 1, "loop chain counted as closed, got \(applyResult.closedCount)")
    try expect(applyResult.removedCount == 1, "one zero-span shape removed, got \(applyResult.removedCount)")
    try expect(shapes.count == applyResult.remaining,
               "mutated array count matches reported remaining (\(shapes.count) vs \(applyResult.remaining))")
    try expect(applyResult.remaining == 3, "2 joined + loop + keeper = 3 remaining, got \(applyResult.remaining)")

    // The mutated array contains the merged polyline and no zero-span shape.
    try expect(!shapes.contains(zeroLine), "zero-span shape gone from mutated array")
    let hasMerged = shapes.contains {
        if case .freehand(let p) = $0 { return p.count == 3 }
        return false
    }
    try expect(hasMerged, "mutated array carries the 3-point merged polyline")

    // Idempotent second apply: nothing left to join/remove.
    let second = ShapeJoinEngine.applyJoinAndCleanup(&shapes, tolerance: 0.1)
    try expect(second.joinedCount == 0, "second apply joins nothing, got \(second.joinedCount)")
    try expect(second.removedCount == 0, "second apply removes nothing, got \(second.removedCount)")
    try expect(second.remaining == 3, "second apply keeps all three, got \(second.remaining)")

    print("ShopPilotVerify2020a0: PASS — gap-tolerance join (\(joined.count) merged / zero-tol separate), zero-span delete (\(removed.count) removed / \(kept.count) kept), apply counts j=\(applyResult.joinedCount) c=\(applyResult.closedCount) r=\(applyResult.removedCount) n=\(applyResult.remaining)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2020a0: FAIL — \(error)")
    exit(1)
}
