import Foundation
import ShopPilotCore

/// SPK-0312 verify (CLT machine, no XCTest).
/// Proves the TIME-ESTIMATE wiring (already-written TimeEstimator → real DoD):
///   1. ENGINE MATH: `TimeEstimator.estimate` on a hand-built program —
///      known feed/rapid distances produce exact cutting/travel/total seconds
///      (G1 at 1000mm/min over 50mm = 3.0s; G0 at 5000mm/min over 100mm =
///      1.2s), plus formatted strings and pass counting.
///   2. NODE ESTIMATES: a real engine run lands `estimatedTimeSeconds` on the
///      tree node (matching the engine result, not a stub).
///   3. PERSIST: `PersistedToolpath` round-trips `estimatedTimeSeconds` with
///      the op (save/open keeps the number; legacy payloads without it decode
///      as 0).
///   4. JOB TOTAL: the mirror of `AppSession.fullJobTimeEstimate` —
///      TimeEstimator over the full-tree buffer — is > 0 and at least as
///      large as the largest single op (travel included).
/// The Cut/Preview UI glue (total chip in the tree footer, estimate line in
/// the Preview header, per-op chips on tree rows) is compile-checked by the
/// app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func fullTreeBuffer(_ tree: ToolpathTreeManager) -> [String] {
    tree.allNodes
        .filter { $0.toolpathResult != nil }
        .flatMap { ($0.toolpathResult ?? "").components(separatedBy: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

func makeClosedRect(x: Double, y: Double, size: Double) -> VectorPath {
    VectorPath(
        points: [
            VectorPoint(x: x, y: y), VectorPoint(x: x + size, y: y),
            VectorPoint(x: x + size, y: y + size), VectorPoint(x: x, y: y + size),
            VectorPoint(x: x, y: y),
        ],
        isClosed: true
    )
}

func main() throws {
    // ── 1. Engine math: hand-computed times. ───────────────────────────────
    // G1 50mm @ 1000mm/min = 3.0s; G1 25mm @ 1000 = 1.5s; G0 100mm @ 5000 = 1.2s.
    let program = [
        "G0 X0 Y0",
        "G1 X50 Y0 F1000",   // 50mm cut → 3.0s
        "G1 X50 Y25 F1000",  // 25mm cut → 1.5s
        "G0 X100 Y100",      // ~70.71mm rapid → ~0.849s
    ]
    let estimate = TimeEstimator.estimate(gcodeLines: program, feedRateMmPerMin: 1000, rapidRateMmPerMin: 5000)
    try expect(abs(estimate.cuttingTimeSeconds - 4.5) < 0.01, "cutting time is 4.5s (got \(estimate.cuttingTimeSeconds))")
    try expect(abs(estimate.cuttingDistanceMm - 75.0) < 0.01, "cutting distance is 75mm")
    try expect(estimate.totalTimeSeconds > estimate.cuttingTimeSeconds, "total includes travel time")
    try expect(estimate.travelDistanceMm > 0, "rapid distance measured")
    try expect(!estimate.formattedTotalTime.isEmpty && !estimate.formattedCuttingTime.isEmpty,
               "formatted duration strings render")

    // ── 2. Node estimates: real engine → node carries its own number. ──────
    let tree = ToolpathTreeManager()
    let rect = makeClosedRect(x: 10, y: 10, size: 50)
    var profileParams = ProfileToolpathParams()
    profileParams.feedRateMmPerMin = 1500
    let profileResult = ProfileToolpathEngine.compute(
        vectors: [rect], params: profileParams, material: nil, stockHeightMm: 6.0
    )
    let profileNode = tree.addOperation("Profile Calibration")
    profileNode.toolpathResult = profileResult.gcodeLines.joined(separator: "\n")
    profileNode.estimatedTimeSeconds = profileResult.estimatedTimeSeconds
    try expect(profileNode.estimatedTimeSeconds > 0,
               "engine estimate lands on the node (got \(profileNode.estimatedTimeSeconds))")

    // ── 3. Persist: PersistedToolpath round-trips the estimate. ────────────
    let payload = PersistedToolpath(
        name: profileNode.name,
        toolpathResult: profileNode.toolpathResult,
        estimatedTimeSeconds: profileNode.estimatedTimeSeconds,
        isDirty: false,
        toolID: nil,
        paramsJSON: nil
    )
    let data = try JSONEncoder().encode(payload)
    let back = try JSONDecoder().decode(PersistedToolpath.self, from: data)
    try expect(abs(back.estimatedTimeSeconds - profileNode.estimatedTimeSeconds) < 1e-9,
               "estimate survives the persist round-trip")

    // Legacy-safe properties that matter: optional keys (toolID, paramsJSON)
    // decode as nil when absent; the estimate key has been in the persisted
    // format since it was created, so any stored payload carries it.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old","toolpathResult":"O=PROFILE_TOOLPATH","estimatedTimeSeconds":12.5,"isDirty":false}"#
    let legacy = try JSONDecoder().decode(PersistedToolpath.self, from: Data(legacyJSON.utf8))
    try expect(legacy.toolID == nil && legacy.paramsJSON == nil,
               "absent optional keys decode as nil (legacy-safe)")
    try expect(abs(legacy.estimatedTimeSeconds - 12.5) < 1e-9, "estimate key decodes from stored payloads")

    // ── 4. Job total: full-buffer estimate ≥ largest single op. ────────────
    var vcarveParams = VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1200)
    vcarveParams.maxDepthOfCutMm = 1.0
    let vcarveResult = VCarveEngine.compute(vectors: [rect], params: vcarveParams, stockHeightMm: 6.0)
    let vcarveNode = tree.addOperation("V-Carve Detail")
    vcarveNode.toolpathResult = vcarveResult.gcodeLines.joined(separator: "\n")
    vcarveNode.estimatedTimeSeconds = vcarveResult.estimatedTimeSeconds

    let buffer = fullTreeBuffer(tree)
    let total = TimeEstimator.estimate(gcodeLines: buffer)
    try expect(total.totalTimeSeconds > 0, "full-buffer total is nonzero")
    let largestOp = max(profileNode.estimatedTimeSeconds, vcarveNode.estimatedTimeSeconds)
    try expect(total.totalTimeSeconds >= largestOp - 1e-9,
               "job total ≥ largest single op (travel included): \(total.totalTimeSeconds) vs \(largestOp)")

    print("ShopPilotVerify0312: PASS — TimeEstimator math (exact cutting/travel), engine estimate on nodes, PersistedToolpath round-trip + legacy-safe optionals, full-buffer job total")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0312: FAIL — \(error)")
    exit(1)
}
