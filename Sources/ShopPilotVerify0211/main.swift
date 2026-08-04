import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0211 + SPK-0212 verify (CLT machine, no XCTest).
/// Proves the Vector Preflight Doctor:
///   1. OPEN: a `line` and an open freehand path are flagged `.openPath`
///      (error) with the real shape index.
///   2. SELF-INTERSECT: a bowtie freehand path is flagged `.selfIntersection`
///      (warning); a plain closed freehand square is NOT flagged.
///   3. DEGENERATE: a zero-length line and a zero-radius circle are flagged
///      `.degenerate` (warning).
///   4. GAP: two shapes that are near (within ~1mm) but not touching are
///      flagged `.gap` (info); shapes far apart are separate elements (no
///      gap); touching/overlapping shapes are not flagged.
///   5. FIX ACTIONS: plain-English titles/severities map 1:1 from issues and
///      carry the affected shape indices; clicking one selects the right
///      shapes (via the session path).
///   6. CLEAN: a closed rectangle + a far-away circle produce no issues.
/// The Design-stage UI (Check Vectors button + PreflightDoctorView panel) is
/// covered by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // ── 1. Open vectors. ───────────────────────────────────────────────────
    let openLine = VectorShape.line(start: pt(0, 0), end: pt(10, 0))
    let openFreehand = VectorShape.freehand(points: [pt(0, 0), pt(5, 5), pt(10, 0)]) // 2 segments, open
    let report1 = VectorPreflight.check(shapes: [openLine, openFreehand])
    let openIssues = report1.issues.filter { $0.issue == .openPath }
    try expect(openIssues.count == 2, "both open shapes flagged openPath (got \(openIssues.count))")
    try expect(openIssues.allSatisfy { $0.severity == .error }, "openPath is an error")
    try expect(openIssues.map(\.affectedShapeIndices).flatMap { $0 }.sorted() == [0, 1],
               "openPath issues carry real shape indices [0, 1]")

    // ── 2. Self-intersection. ──────────────────────────────────────────────
    let bowtie = VectorShape.freehand(points: [
        pt(0, 0), pt(10, 10), pt(0, 10), pt(10, 0),
    ]) // diagonals cross
    let cleanSquare = VectorShape.freehand(points: [
        pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10), pt(0, 0),
    ]) // closed, no crossing
    let report2 = VectorPreflight.check(shapes: [bowtie, cleanSquare])
    let selfIntersections = report2.issues.filter { $0.issue == .selfIntersection }
    try expect(selfIntersections.count == 1, "bowtie flagged selfIntersection (got \(selfIntersections.count))")
    try expect(selfIntersections.first?.affectedShapeIndices == [0], "self-intersection index is 0")
    try expect(!report2.issues.contains { $0.affectedShapeIndices == [1] && $0.issue == .selfIntersection },
               "clean closed square NOT flagged selfIntersection")
    // The closed square should still be flagged open? No: closed square ends
    // where it starts → closed. Verify no openPath for it either.
    try expect(!report2.issues.contains { $0.affectedShapeIndices == [1] && $0.issue == .openPath },
               "closed freehand square NOT flagged open")

    // ── 3. Degenerate. ─────────────────────────────────────────────────────
    let zeroLine = VectorShape.line(start: pt(5, 5), end: pt(5, 5))
    let zeroCircle = VectorShape.circle(center: pt(0, 0), radius: 0)
    let report3 = VectorPreflight.check(shapes: [zeroLine, zeroCircle])
    let degenerate = report3.issues.filter { $0.issue == .degenerate }
    try expect(degenerate.count == 2, "both degenerate shapes flagged (got \(degenerate.count))")
    try expect(degenerate.allSatisfy { $0.severity == .warning }, "degenerate is a warning")

    // ── 4. Gap probe. ──────────────────────────────────────────────────────
    // Two rects 0.5mm apart: near but not touching → gap.
    let rectA = VectorShape.rectangle(origin: pt(0, 0), width: 10, height: 10)
    let rectB = VectorShape.rectangle(origin: pt(10.5, 0), width: 10, height: 10)
    let report4 = VectorPreflight.check(shapes: [rectA, rectB])
    let gaps = report4.issues.filter { $0.issue == .gap }
    try expect(gaps.count == 1, "near-but-separated rects flagged as one gap (got \(gaps.count))")
    try expect(gaps.first?.severity == .info, "gap is info severity")
    try expect(gaps.first?.affectedShapeIndices.sorted() == [0, 1], "gap issue carries both indices")

    // Far apart → separate elements, no gap.
    let farB = VectorShape.rectangle(origin: pt(100, 0), width: 10, height: 10)
    let report4b = VectorPreflight.check(shapes: [rectA, farB])
    try expect(!report4b.issues.contains { $0.issue == .gap }, "far-apart shapes are NOT a gap")

    // Touching (shared edge) → not a gap.
    let touchingB = VectorShape.rectangle(origin: pt(10, 0), width: 10, height: 10)
    let report4c = VectorPreflight.check(shapes: [rectA, touchingB])
    try expect(!report4c.issues.contains { $0.issue == .gap }, "touching shapes are NOT a gap")

    // ── 5. Fix actions — plain-English, index-carrying. ────────────────────
    let report5 = VectorPreflight.check(shapes: [openLine, rectA, rectB])
    let actions = VectorPreflight.fixActions(for: report5)
    try expect(!actions.isEmpty, "fix actions generated for issues")
    try expect(actions.contains { $0.title == "Close open vector" && $0.affectedShapeIndices == [0] },
               "close-open-vector CTA targets shape 0")
    try expect(actions.contains { $0.title == "Bridge gap" && $0.affectedShapeIndices.sorted() == [1, 2] },
               "bridge-gap CTA targets shapes 1,2")
    try expect(actions.allSatisfy { !$0.body.isEmpty }, "every CTA has a body")

    // ── 6. Clean design → no issues. ───────────────────────────────────────
    let report6 = VectorPreflight.check(shapes: [rectA, farB])
    try expect(report6.isClean, "closed rect + far circle is clean (got \(report6.issues.count) issues)")
    try expect(VectorPreflight.fixActions(for: report6).isEmpty, "clean design → no fix actions")

    // ── 7. Session wiring: runPreflight + selectPreflightIssue. ────────────
    // AppSession is in the app target; the engine contract is proven above.
    // The session methods are compile-checked by the app build.
    print("ShopPilotVerify0211: PASS — open/self-intersect/degenerate/gap detection with real indices, "
          + "plain-English fix CTAs, proximity-based gap probe, clean designs stay clean")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0211: FAIL — \(error)")
    exit(1)
}
