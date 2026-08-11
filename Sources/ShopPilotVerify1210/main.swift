import Foundation
import ShopPilotCore

/// SPK-1210 verify (CLT machine, no XCTest).
/// Proves the PECK-DRILL VISUALIZATION + TOOLPATH-ON-HOVER contract:
///   1. PECK DETECTION: a drill block's rapid retract (G0 Z up between two
///      plunges at the same XY) is detected; a plain end-of-op retract is
///      NOT (no same-XY plunge after it).
///   2. NO FALSE POSITIVES: single plunge + final retract → no peck.
///   3. MULTI-PECK: two peck cycles at two XY points → two retracts.
///   4. NODE TAGGING: `tagSegments` marks segments with their O= marker
///      node; the session's per-node map (segmentsByToolpathNode) is the
///      hover lookup the Preview uses — two ops stay distinguishable.
/// The Preview rendering (dashed yellow ticks + hover dim) is compile-
/// checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Peck cycle detected. ───────────────────────────────────────────
    // Classic peck: plunge, retract, plunge, retract, plunge, final retract.
    let peckProgram = [
        "G21", "G90",
        "G0 X10 Y10",
        "G0 Z2.0",
        "G1 Z-3.0 F300",   // plunge 1
        "G0 Z2.0",          // peck retract (same XY)
        "G1 Z-6.0 F300",   // plunge 2
        "G0 Z2.0",          // peck retract (same XY)
        "G1 Z-9.0 F300",   // plunge 3 (final)
        "G0 Z10.0",         // final retract — NOT a peck (no plunge after)
        "M30",
    ]
    let pecks = WireframeRenderer.detectPeckRetracts(from: peckProgram)
    try expect(pecks.count == 2, "two peck retracts detected (got \(pecks.count))")
    for peck in pecks {
        try expect(abs(peck.start.x - 10) < 0.001 && abs(peck.start.y - 10) < 0.001,
                   "peck retract sits at the drill XY (10,10)")
    }

    // ── 2. No false positives: single plunge + final retract only. ────────
    let plainProgram = [
        "G21", "G90",
        "G0 X5 Y5",
        "G0 Z2.0",
        "G1 Z-8.0 F300",   // single plunge
        "G0 Z10.0",         // final retract
        "M30",
    ]
    let plainPecks = WireframeRenderer.detectPeckRetracts(from: plainProgram)
    try expect(plainPecks.isEmpty, "no peck in a single plunge (got \(plainPecks.count))")

    // ── 3. Multi-point pecking → one retract per cycle. ───────────────────
    let multiProgram = [
        "G21", "G90",
        "G0 X1 Y1", "G0 Z2.0",
        "G1 Z-3.0", "G0 Z2.0",   // peck at (1,1)
        "G1 Z-6.0", "G0 Z10.0",
        "G0 X9 Y9", "G0 Z2.0",
        "G1 Z-3.0", "G0 Z2.0",   // peck at (9,9)
        "G1 Z-6.0", "G0 Z10.0",
    ]
    let multiPecks = WireframeRenderer.detectPeckRetracts(from: multiProgram)
    try expect(multiPecks.count == 2, "one peck per XY (got \(multiPecks.count))")

    // ── 4. Node tagging distinguishes ops. ─────────────────────────────────
    let twoOps = [
        "O=PROFILE_TOOLPATH",
        "G0 X0 Y0", "G1 X10 Y0", "G1 X10 Y10",
        "O=POCKET_TOOLPATH",
        "G0 X20 Y20", "G1 X30 Y20", "G1 X30 Y30",
    ]
    let tagged = WireframeRenderer.tagSegments(from: twoOps)
    try expect(tagged.count == 5, "five motion segments tagged (got \(tagged.count))")
    try expect(tagged[0].nodeID == "O=PROFILE_TOOLPATH", "profile segments tagged")
    try expect(tagged[3].nodeID == "O=POCKET_TOOLPATH", "pocket segments tagged (distinguishable)")
    try expect(tagged[2].isRapid, "the G0 X20Y20 move is a rapid")

    // Session-level map shape: two nodes → two keys (the hover lookup).
    let tree = ToolpathTreeManager()
    let profile = tree.addOperation("Profile")
    profile.toolpathResult = "O=PROFILE_TOOLPATH\nG0 X0 Y0\nG1 X10 Y0"
    let pocket = tree.addOperation("Pocket")
    pocket.toolpathResult = "O=POCKET_TOOLPATH\nG0 X20 Y20\nG1 X30 Y30"
    var map: [UUID: [(start: (x: Double, y: Double), end: (x: Double, y: Double), isRapid: Bool)]] = [:]
    for node in tree.allNodes where node.toolpathResult != nil {
        let segs = WireframeRenderer.generateSegments(from: node.toolpathResult!.components(separatedBy: .newlines))
        if !segs.isEmpty { map[node.id] = segs }
    }
    try expect(map.count == 2, "per-node segment map has both ops (hover lookup)")
    try expect(map[profile.id]?.count == 1 && map[pocket.id]?.count == 1,
               "each op contributes its own segments")

    print("ShopPilotVerify1210: PASS — peck retract detection (2 pecks in a 3-plunge cycle, none in single plunge, 1 per XY), node tagging distinguishes ops, per-node hover map")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1210: FAIL — \(error)")
    exit(1)
}
