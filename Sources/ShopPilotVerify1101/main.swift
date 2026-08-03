import Foundation
import ShopPilotGeometry

/// SPK-1101 feed verify without XCTest (CLT-only machines).
/// Proves the nudge-selection-+1mm-in-X behavior backed by the canonical
/// `VectorShape.translated(by:_:)` kernel op that `AppSession.applyNudgeX()`
/// calls:
///   1. Every shape type shifts exactly +1.0 in X and 0.0 in Y.
///   2. Rectangle keeps width/height; line endpoints both move.
///   3. Circle/ellipse keep radius; freehand every vertex moves.
///   4. Nudge +1 then -1 composes to identity.
///   5. A multi-shape selection moves as a rigid group (relative offsets kept).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

func expectPoint(_ p: VectorPoint, _ x: Double, _ y: Double, _ msg: String, tolerance: Double = 1e-9) throws {
    try expectClose(p.x, x, "\(msg).x", tolerance: tolerance)
    try expectClose(p.y, y, "\(msg).y", tolerance: tolerance)
}

func main() throws {
    // 1. Rectangle: origin shifts by exactly (+1, 0); size untouched.
    let rect = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 20), width: 100, height: 40)
    let nudgedRect = rect.translated(by: 1, 0)
    guard case .rectangle(let ro, let rw, let rh) = nudgedRect else {
        throw VerifyError.failed("rect lost type after nudge")
    }
    try expectPoint(ro, 11, 20, "rect origin after +1mm X")
    try expectClose(rw, 100, "rect width preserved")
    try expectClose(rh, 40, "rect height preserved")

    // 2. Line: both endpoints shift +1 in X, Y untouched.
    let line = VectorShape.line(start: VectorPoint(x: 5, y: 7), end: VectorPoint(x: 50, y: 60))
    let nudgedLine = line.translated(by: 1, 0)
    guard case .line(let ls, let le) = nudgedLine else {
        throw VerifyError.failed("line lost type after nudge")
    }
    try expectPoint(ls, 6, 7, "line start after +1mm X")
    try expectPoint(le, 51, 60, "line end after +1mm X")

    // 3. Circle: center shifts, radius preserved.
    let circle = VectorShape.circle(center: VectorPoint(x: 80, y: 30), radius: 12)
    let nudgedCircle = circle.translated(by: 1, 0)
    guard case .circle(let cc, let cr) = nudgedCircle else {
        throw VerifyError.failed("circle lost type after nudge")
    }
    try expectPoint(cc, 81, 30, "circle center after +1mm X")
    try expectClose(cr, 12, "circle radius preserved")

    // 4. Ellipse: center shifts, radii + rotation preserved.
    let ellipse = VectorShape.ellipse(center: VectorPoint(x: 30, y: 20), radiusX: 10, radiusY: 5, rotation: 0.7)
    let nudgedEllipse = ellipse.translated(by: 1, 0)
    guard case .ellipse(let ec, let erx, let ery, let erot) = nudgedEllipse else {
        throw VerifyError.failed("ellipse lost type after nudge")
    }
    try expectPoint(ec, 31, 20, "ellipse center after +1mm X")
    try expectClose(erx, 10, "ellipse rx preserved")
    try expectClose(ery, 5, "ellipse ry preserved")
    try expectClose(erot, 0.7, "ellipse rotation preserved")

    // 5. Freehand: every vertex shifts +1 in X.
    let poly = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0),
        VectorPoint(x: 100, y: 40), VectorPoint(x: 0, y: 40),
    ])
    let nudgedPoly = poly.translated(by: 1, 0)
    guard case .freehand(let np) = nudgedPoly else {
        throw VerifyError.failed("freehand lost type after nudge")
    }
    try expect(np.count == 4, "poly vertex count preserved")
    try expectPoint(np[0], 1, 0, "poly vertex 0")
    try expectPoint(np[1], 101, 0, "poly vertex 1")
    try expectPoint(np[2], 101, 40, "poly vertex 2")
    try expectPoint(np[3], 1, 40, "poly vertex 3")

    // 6. Group nudge: relative offsets between shapes preserved.
    let group = [rect, line]
    let nudgedGroup = group.map { $0.translated(by: 1, 0) }
    guard case .rectangle(let gro, _, _) = nudgedGroup[0] else {
        throw VerifyError.failed("group rect lost type")
    }
    guard case .line(let gls, let gle) = nudgedGroup[1] else {
        throw VerifyError.failed("group line lost type")
    }
    // Rect moved (10,20)→(11,20); line moved (5,7)-(50,60)→(6,7)-(51,60).
    try expectPoint(gro, 11, 20, "group rect origin")
    try expectPoint(gls, 6, 7, "group line start")
    try expectPoint(gle, 51, 60, "group line end")

    // 7. Nudge +1 then -1 composes to identity.
    let roundTrip = poly.translated(by: 1, 0).translated(by: -1, 0)
    guard case .freehand(let rp) = roundTrip else {
        throw VerifyError.failed("freehand lost type after round-trip")
    }
    for (i, p) in rp.enumerated() {
        try expectPoint(p, [0, 100, 100, 0][i], i < 2 ? 0 : 40, "round-trip vertex \(i)")
    }

    // 8. Y-only nudge leaves X untouched (sanity for the dx/dy split).
    let nudgedY = rect.translated(by: 0, 5)
    guard case .rectangle(let yo, _, _) = nudgedY else {
        throw VerifyError.failed("rect lost type after Y nudge")
    }
    try expectPoint(yo, 10, 25, "Y-only nudge origin")

    print("SPK-1101 feed verification: PASS")
    print("  rect (10,20)100×40 → (11,20)100×40 ✓")
    print("  line (5,7)-(50,60) → (6,7)-(51,60) ✓")
    print("  circle center (80,30)→(81,30), r=12 ✓  ellipse rx/ry/rot kept ✓")
    print("  freehand every vertex +1 X ✓  group rigid move ✓")
    print("  +1 then -1 = identity ✓  Y-only nudge keeps X ✓")
}

do {
    try main()
} catch {
    fputs("SPK-1101 feed verification: FAIL — \(error)\n", stderr)
    exit(1)
}
