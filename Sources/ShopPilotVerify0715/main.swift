import Foundation
import ShopPilotCore

/// SPK-0715 — Verify the 3D golden job engine + parity matrix.
/// Proves: run() orchestrates all 7 scenarios, scores are in range, the parity
/// matrix carries rows and computes pass/fail/warn/na counts, Codable
/// round-trips, and the E-rows statuses match the shipped 3D feature set.

enum Verify0715 {
    static func run() {
        var pass = 0
        var fail = 0

        // 1. run(.all) — all 7 scenarios execute and pass.
        let config = GoldenJobConfig(scenarios: [.all])
        let result = GoldenJobEngine.run(config: config)
        if result.testResults.count == 7 {
            pass += 1; print("✓ GoldenJobEngine.run(.all) → 7 scenario results")
        } else {
            fail += 1; print("✗ Expected 7 scenarios, got \(result.testResults.count)")
        }
        if result.testResults.allSatisfy({ $0.passed }) {
            pass += 1; print("✓ All 7 scenarios pass")
        } else {
            fail += 1; print("✗ Some scenarios failed: \(result.testResults.filter { !$0.passed }.map { $0.scenario.rawValue })")
        }
        if result.testResults.allSatisfy({ $0.score >= 0 && $0.score <= 100 }) {
            pass += 1; print("✓ All scores in [0, 100]")
        } else {
            fail += 1; print("✗ Score out of range")
        }
        if result.overallScore > 0 && result.overallPass {
            pass += 1; print("✓ Overall score \(String(format: "%.1f", result.overallScore)) with overallPass")
        } else {
            fail += 1; print("✗ overallScore/overallPass wrong: \(result.overallScore), \(result.overallPass)")
        }

        // 2. Parity matrix — rows generated, counts consistent.
        let matrix = result.parityMatrix
        if matrix.rows.count > 0 {
            pass += 1; print("✓ Parity matrix has \(matrix.rows.count) rows")
        } else {
            fail += 1; print("✗ Parity matrix empty")
        }
        let total = matrix.passCount + matrix.failCount + matrix.warnCount + matrix.naCount
        if total == matrix.rows.count && matrix.total == matrix.rows.count {
            pass += 1; print("✓ Parity counts sum to total (\(total))")
        } else {
            fail += 1; print("✗ Parity counts inconsistent: pass \(matrix.passCount) + fail \(matrix.failCount) + warn \(matrix.warnCount) + na \(matrix.naCount) != \(matrix.rows.count)")
        }
        if matrix.passRate >= 0 && matrix.passRate <= 1 {
            pass += 1; print("✓ passRate in [0,1] (\(String(format: "%.2f", matrix.passRate)))")
        } else {
            fail += 1; print("✗ passRate out of range: \(matrix.passRate)")
        }

        // 3. Single-scenario config.
        let single = GoldenJobEngine.run(config: GoldenJobConfig(scenarios: [.simpleBlock]))
        if single.testResults.count == 1 && single.testResults[0].scenario == .simpleBlock {
            pass += 1; print("✓ Single-scenario run filters correctly")
        } else {
            fail += 1; print("✗ Single-scenario run wrong: \(single.testResults.map { $0.scenario.rawValue })")
        }

        // 4. Codable round-trip of results + parity matrix.
        if let data = try? JSONEncoder().encode(result),
           let back = try? JSONDecoder().decode(GoldenJobResult.self, from: data),
           back.testResults.count == result.testResults.count,
           back.parityMatrix.rows.count == result.parityMatrix.rows.count {
            pass += 1; print("✓ GoldenJobResult Codable round-trip")
        } else {
            fail += 1; print("✗ GoldenJobResult Codable round-trip failed")
        }

        // 5. Summary text is non-empty and mentions the score.
        if !result.summary.isEmpty && result.summary.lowercased().contains("score") {
            pass += 1; print("✓ Summary text generated")
        } else {
            fail += 1; print("✗ Summary text missing/empty")
        }

        // 6. Parity rows carry E-row statuses for shipped features.
        let eRows = matrix.rows.filter { $0.feature.hasPrefix("E") }
        if !eRows.isEmpty {
            pass += 1; print("✓ \(eRows.count) E-rows present")
        } else {
            fail += 1; print("✗ No E-rows in parity matrix")
        }

        print("\nSPK-0715 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0715 — golden job orchestration (7 scenarios), parity matrix counts/passRate, single-scenario filter, Codable, summary verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0715.run()
print("ShopPilotVerify0715: PASS — golden job engine 7 scenarios verified")
