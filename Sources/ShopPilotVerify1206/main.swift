import Foundation
import ShopPilotCore

/// SPK-1206 verify (CLT machine, no XCTest).
/// Proves the VIEW ORIENTATION contract:
///   1. PROJECTIONS: each orientation maps world (x, y) with the documented
///      math — top is identity; isometric shears X (0.707) and compresses Y
///      (0.577 ortho / 0.5 perspective); front collapses Y to an edge-on line.
///   2. ORTHO vs PERSPECTIVE: isometric perspective compresses the mapped
///      point toward the horizon as Y grows; orthographic does not.
///   3. GIZMO FACES: each cube face maps to the expected orientation.
///   4. SHORTCUTS: ⌘⌥1/2/3 → top/iso/front.
/// The gizmo overlay + picker + onKeyPress wiring is compile-checked by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) < tol }

func main() throws {
    // ── 1. Projection math per orientation. ───────────────────────────────
    // Top: identity.
    let top = ViewProjection.projection(for: .top)
    let topMapped = top.map(x: 10, y: 20)
    try expect(close(topMapped.x, 10) && close(topMapped.y, 20), "top projection is identity")

    // Isometric (ortho): X = x + 0.707y, Y = 0.577y.
    let iso = ViewProjection.projection(for: .isometric, orthographic: true)
    let isoMapped = iso.map(x: 10, y: 20)
    try expect(close(isoMapped.x, 10 + 20 * 0.70710678118, 1e-6), "iso shears X by 0.707y")
    try expect(close(isoMapped.y, 20 * 0.57735026919, 1e-6), "iso compresses Y by 0.577")

    // Front: Y collapses (edge-on sheet), X stays linear.
    let front = ViewProjection.projection(for: .front)
    let frontMapped = front.map(x: 10, y: 20)
    try expect(close(frontMapped.x, 10) && close(frontMapped.y, 0), "front collapses Y, keeps X")

    // ── 2. Ortho vs perspective. ──────────────────────────────────────────
    let isoPersp = ViewProjection.projection(for: .isometric, orthographic: false)
    let near = isoPersp.map(x: 10, y: 5)
    let far = isoPersp.map(x: 10, y: 40)
    // Perspective: far points compress toward the horizon (factor < 1 as
    // depth grows) — the far mapped magnitude must be less than a straight
    // ortho mapping of the same point.
    let isoOrthoFar = iso.map(x: 10, y: 40)
    try expect(abs(far.x) < abs(isoOrthoFar.x), "perspective compresses far X")
    try expect(abs(far.y) < abs(isoOrthoFar.y), "perspective compresses far Y")
    // Orthographic top is always exact regardless of the flag.
    let topPersp = ViewProjection.projection(for: .top, orthographic: false)
    let tp = topPersp.map(x: 10, y: 20)
    try expect(close(tp.x, 10) && close(tp.y, 20), "top stays orthographic in both modes")

    // ── 3. Gizmo face → orientation. ──────────────────────────────────────
    try expect(GizmoFace.top.orientation == .top, "top face → top")
    try expect(GizmoFace.front.orientation == .front, "front face → front")
    try expect(GizmoFace.isometric.orientation == .isometric, "iso face → isometric")
    try expect(GizmoFace.right.orientation == .top, "right face → top (right == top for 2.5D)")

    // ── 4. Shortcuts. ─────────────────────────────────────────────────────
    try expect(ViewOrientationShortcut.orientation(for: "1") == .top, "⌘⌥1 → top")
    try expect(ViewOrientationShortcut.orientation(for: "2") == .isometric, "⌘⌥2 → isometric")
    try expect(ViewOrientationShortcut.orientation(for: "3") == .front, "⌘⌥3 → front")
    try expect(ViewOrientationShortcut.orientation(for: "9") == nil, "unknown key → nil")

    print("ShopPilotVerify1206: PASS — top/iso/front projection math, ortho vs perspective compression, gizmo face mapping, ⌘⌥1-3 shortcuts")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1206: FAIL — \(error)")
    exit(1)
}
