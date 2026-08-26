import Foundation
import ShopPilotCore

// SPK-2023e — Copy along path: N-or-spacing along curve, tangent-follow toggle.
// Generalizes ArrayCopy to arbitrary polylines.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

func main() throws {
    // L-shaped path: (0,0) → (10,0) → (10,10). Total length 20.
    let path = [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 10, y: 0),
        VectorPoint(x: 10, y: 10),
    ]

    // ── 1. Count mode: 4 copies evenly spaced. ────────────────────────────
    var p = PathArrayCopyParams(targetPathID: UUID(), mode: .count(4), followTangent: false)
    let r = ArrayCopyAndMergeEngine.createPathArray(points: path, params: p)
    try expect(r.success, "count mode succeeds")
    try expect(r.positions.count == 4, "4 copies (\(r.positions.count))")
    // Positions: s=0 → (0,0); s=6.67 → (6.67,0); s=13.33 → (10,3.33); s=20 → (10,10).
    try expect(abs(r.positions[0].x - 0) < 1e-6 && abs(r.positions[0].y - 0) < 1e-6,
               "first copy at start (0,0)")
    try expect(abs(r.positions[3].x - 10) < 1e-6 && abs(r.positions[3].y - 10) < 1e-6,
               "last copy at end (10,10)")
    try expect(abs(r.positions[1].x - 20.0/3) < 1e-6 && abs(r.positions[1].y - 0) < 1e-6,
               "second copy at (6.67, 0)")
    try expect(abs(r.positions[2].x - 10) < 1e-6 && abs(r.positions[2].y - 10.0/3) < 1e-6,
               "third copy at (10, 3.33)")

    // ── 2. Spacing mode: copies every 5 mm. ────────────────────────────────
    p = PathArrayCopyParams(targetPathID: UUID(), mode: .spacing(5), followTangent: false)
    let r2 = ArrayCopyAndMergeEngine.createPathArray(points: path, params: p)
    try expect(r2.success, "spacing mode succeeds")
    // s=0,5,10,15,20 → 5 copies.
    try expect(r2.positions.count == 5, "5 copies at 5mm spacing (\(r2.positions.count))")
    try expect(abs(r2.positions[0].x - 0) < 1e-6, "spacing: first at 0")
    try expect(abs(r2.positions[1].x - 5) < 1e-6, "spacing: second at x=5")
    try expect(abs(r2.positions[2].x - 10) < 1e-6 && abs(r2.positions[2].y - 0) < 1e-6,
               "spacing: third at corner (10,0)")
    try expect(abs(r2.positions[4].x - 10) < 1e-6 && abs(r2.positions[4].y - 10) < 1e-6,
               "spacing: last at end (10,10)")

    // ── 3. Tangent follow: angles computed. ────────────────────────────────
    p = PathArrayCopyParams(targetPathID: UUID(), mode: .count(4), followTangent: true)
    let r3 = ArrayCopyAndMergeEngine.createPathArray(points: path, params: p)
    try expect(r3.angles.count == 4, "4 tangent angles (\(r3.angles.count))")
    // First segment is horizontal (0°), second is vertical (90°).
    try expect(abs(r3.angles[0] - 0) < 1e-6, "first tangent 0° (horizontal)")
    try expect(abs(r3.angles[2] - 90) < 1e-6, "third tangent 90° (vertical)")
    try expect(abs(r3.angles[3] - 90) < 1e-6, "fourth tangent 90° (vertical)")

    // ── 4. Tangent off: no angles. ─────────────────────────────────────────
    p = PathArrayCopyParams(targetPathID: UUID(), mode: .count(4), followTangent: false)
    let r4 = ArrayCopyAndMergeEngine.createPathArray(points: path, params: p)
    try expect(r4.angles.isEmpty, "followTangent=false → no angles")

    // ── 5. Error cases. ────────────────────────────────────────────────────
    let bad = ArrayCopyAndMergeEngine.createPathArray(points: [VectorPoint(x: 0, y: 0)], params: p)
    try expect(!bad.success, "single-point path fails")

    let zeroLen = ArrayCopyAndMergeEngine.createPathArray(
        points: [VectorPoint(x: 5, y: 5), VectorPoint(x: 5, y: 5)], params: p)
    try expect(!zeroLen.success, "zero-length path fails")

    print(failures == 0
          ? "ShopPilotVerify2023e: PASS"
          : "ShopPilotVerify2023e: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
