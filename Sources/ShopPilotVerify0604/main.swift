import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0604 verify (CLT machine, no XCTest).
/// Proves the V-Carve preflight gate:
///   1. BLOCK: open vectors (line, open freehand, open polyline) make the
///      gate return a blocking report — V-Carve must not run on them.
///   2. FIX CTA: the blocking report carries plain-English fix actions
///      ("Close open vector") with the real affected shape indices.
///   3. ALLOW: closed vectors only (rect, circle, closed freehand) → gate
///      returns nil → carve proceeds. Non-open issues (degenerate, gap,
///      self-intersection) do NOT block.
///   4. MIXED: open + closed shapes → blocked, and only the open indices are
///      in the CTA.
/// The session wiring (generateVCarveToolpath routes to Design + opens the
/// preflight panel on block) is compile-checked by the app build; the sibling
/// PreflightVCarveTests XCTest covers the same engine surface.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

func main() throws {
    // ── 1. Open vectors block the carve. ───────────────────────────────────
    let openLine = VectorShape.line(start: pt(0, 0), end: pt(10, 0))
    let openPolyline = VectorShape.freehand(points: [pt(0, 0), pt(5, 5), pt(10, 0)])
    let gate1 = VectorPreflight.vCarveGate(shapes: [openLine])
    try expect(gate1 != nil, "open line blocks V-Carve")
    try expect(gate1?.issues.contains { $0.issue == .openPath } == true,
               "gate report contains the openPath issue")
    let gate2 = VectorPreflight.vCarveGate(shapes: [openPolyline])
    try expect(gate2 != nil, "open polyline blocks V-Carve")

    // ── 2. Plain-English fix CTA with real indices. ────────────────────────
    let mixed = [
        openLine,                                              // index 0: open
        VectorShape.rectangle(origin: pt(0, 0), width: 10, height: 10),  // 1: closed
        openPolyline,                                          // 2: open
    ]
    let gate3 = VectorPreflight.vCarveGate(shapes: mixed)
    try expect(gate3 != nil, "mixed open+closed blocks V-Carve")
    let actions = VectorPreflight.fixActions(for: gate3!)
    let closeCTA = actions.filter { $0.title == "Close open vector" }
    try expect(!closeCTA.isEmpty, "blocking report has a 'Close open vector' CTA")
    let ctaIndices = closeCTA.flatMap { $0.affectedShapeIndices }.sorted()
    try expect(ctaIndices == [0, 2], "CTA targets exactly the open shapes (got \(ctaIndices))")
    try expect(closeCTA.allSatisfy { !($0.suggestedFix ?? "").isEmpty }, "CTA has a plain-English suggested fix")

    // ── 3. Closed vectors allow the carve. ─────────────────────────────────
    let closedOnly = [
        VectorShape.rectangle(origin: pt(0, 0), width: 50, height: 50),
        VectorShape.circle(center: pt(25, 25), radius: 20),
        VectorShape.freehand(points: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10), pt(0, 0)]),
    ]
    try expect(VectorPreflight.vCarveGate(shapes: closedOnly) == nil,
               "closed vectors only → carve allowed")

    // Non-open issues do not block: degenerate + gap + self-intersection.
    // (Degenerate fixtures must be CLOSED shape types — a zero-length line is
    // a line, and lines are always open, so it correctly blocks.)
    let nonOpenIssues = [
        VectorShape.circle(center: pt(5, 5), radius: 0),                 // degenerate (closed)
        VectorShape.rectangle(origin: pt(0, 0), width: 0, height: 10),   // degenerate (closed)
        VectorShape.rectangle(origin: pt(0, 0), width: 10, height: 10),  // near-gap pair
        VectorShape.rectangle(origin: pt(10.5, 0), width: 10, height: 10),
    ]
    let gate4 = VectorPreflight.vCarveGate(shapes: nonOpenIssues)
    try expect(gate4 == nil, "degenerate/gap-only design does NOT block V-Carve")

    let selfIntersectOnly = [
        // Closed bowtie: first == last (so NOT open), but the two diagonals
        // cross → self-intersection only.
        VectorShape.freehand(points: [pt(0, 0), pt(10, 10), pt(0, 10), pt(10, 0), pt(0, 0)]),
    ]
    let gate5 = VectorPreflight.vCarveGate(shapes: selfIntersectOnly)
    try expect(gate5 == nil, "self-intersection alone does NOT block V-Carve (warning-level)")

    // ── 4. Empty / no-shape design. ────────────────────────────────────────
    try expect(VectorPreflight.vCarveGate(shapes: []) == nil, "empty design does not block")

    print("ShopPilotVerify0604: PASS — open vectors block V-Carve with plain-English fix CTA "
          + "(real indices), closed-only/non-open designs carve freely")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0604: FAIL — \(error)")
    exit(1)
}
