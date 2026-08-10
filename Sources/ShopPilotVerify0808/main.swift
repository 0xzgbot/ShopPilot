import Foundation
import ShopPilotCore

/// SPK-0808 verify (CLT machine, no XCTest).
/// Proves the PRODUCTION GOLDEN JOB contract — the manager now runs the REAL
/// toolpath engines instead of the legacy `Double.random` stub:
///   1. PASSING RUN: a config whose expected width/depth match the real
///      on-cut profile span (fixture W + tool Ø) yields .passed, with the
///      engine's measured cut span in actualDimensions and duration measured.
///   2. FAILING RUN: a config with an impossible expected width fails with
///      a deviation error and failCount increments.
///   3. LINE-COUNT CHECK: expected gcodeLines compared against the engine's
///      real output within count tolerance.
///   4. RUN HISTORY: results accumulate on the config; status/date update;
///      pass/fail counters are honest (not random).
/// The AppSession glue (goldenJobManager + run surface) is compile-checked
/// by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Passing run against the real engine. ───────────────────────────
    let manager = ProductionGoldenJobManager()
    // 50×50 fixture, 6mm on-cut profile → cut span equals the fixture 50×50mm.
    let good = ProductionGoldenJobConfig(
        name: "Calibration 50×50",
        description: "Golden profile on a 50mm square",
        jobType: .calibration,
        expectedDimensions: ["width": 50, "depth": 50],
        tolerance: 0.5,
        maxTimeMinutes: 30,
        requiredPasses: 3
    )
    manager.jobs.append(good)
    let goodResult = manager.runJob(good)
    try expect(goodResult.status == .passed,
               "matching fixture passes (got \(goodResult.status.rawValue): \(goodResult.errors.joined(separator: "; ")))")
    try expect(!goodResult.actualDimensions.isEmpty, "actual dimensions measured")
    let measuredW = goodResult.actualDimensions["width"] ?? 0
    try expect(abs(measuredW - 50.0) < 1.0,
               "measured width ≈ 50mm (on-cut follows the fixture, got \(String(format: "%.2f", measuredW)))")
    try expect(goodResult.durationMinutes >= 0, "duration measured, not random")
    try expect(goodResult.notes.contains("passed"), "passing note")

    let goodBack = manager.getJobs(by: .calibration).first
    try expect(goodBack?.status == .passed, "manager records pass status")
    try expect(goodBack?.passCount == 1, "passCount incremented")
    try expect(goodBack?.results.count == 1, "result history recorded")
    try expect(goodBack?.lastRunDate != nil, "run date stamped")

    // ── 2. Failing run: impossible expected span. ─────────────────────────
    let bad = ProductionGoldenJobConfig(
        name: "Impossible Span",
        description: "expects a 500mm span from a 50mm fixture",
        jobType: .verification,
        expectedDimensions: ["width": 500, "depth": 50],
        tolerance: 0.5,
        maxTimeMinutes: 30,
        requiredPasses: 1
    )
    manager.jobs.append(bad)
    let badResult = manager.runJob(bad)
    try expect(badResult.status == .failed,
               "impossible width fails (got \(badResult.status.rawValue))")
    try expect(!badResult.errors.isEmpty, "failure carries deviation errors")
    try expect(badResult.deviations["width"] != nil, "width deviation recorded")
    let badBack = manager.getJobs(by: .failed).first
    try expect(badBack?.failCount == 1, "failCount incremented")

    // ── 3. Line-count check. ──────────────────────────────────────────────
    // Run the same engine directly to know the honest count, then assert a
    // config with that expected count passes the count check.
    let rect = VectorPath(
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50), VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0),
        ],
        isClosed: true
    )
    var params = ProfileToolpathParams()
    params.cutMode = .onCut
    params.toolDiameterMm = 6.0
    let engineRun = ProfileToolpathEngine.compute(
        vectors: [rect], params: params, material: nil, stockHeightMm: 12.0
    )
    let expectedCount = Double(engineRun.gcodeLines.count)
    let lineConfig = ProductionGoldenJobConfig(
        name: "Line Count Check",
        description: "expects the engine's real line count",
        jobType: .regression,
        expectedDimensions: ["width": 50, "depth": 50, "gcodeLines": expectedCount],
        tolerance: 0.5,
        maxTimeMinutes: 30,
        requiredPasses: 1
    )
    manager.jobs.append(lineConfig)
    let lineResult = manager.runJob(lineConfig)
    try expect(lineResult.status == .passed,
               "exact line-count expectation passes (got \(lineResult.status.rawValue))")
    try expect((lineResult.actualDimensions["gcodeLines"] ?? -1) == expectedCount,
               "actual line count reported")

    // ── 4. Honest counters + validation. ──────────────────────────────────
    try expect(manager.getJobs(by: .passed).count == 2, "two passed runs recorded")
    try expect(manager.getJobs(by: .failed).count == 1, "one failed run recorded")
    let validation = ProductionGoldenJobManager.validate(
        ProductionGoldenJobConfig(name: "", description: "", requiredPasses: 0)
    )
    try expect(!validation.isValid, "validator rejects empty name + zero passes")

    print("ShopPilotVerify0808: PASS — real-engine golden runs: pass/fail on measured cut span, line-count check, honest counters + history, validation")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0808: FAIL — \(error)")
    exit(1)
}
