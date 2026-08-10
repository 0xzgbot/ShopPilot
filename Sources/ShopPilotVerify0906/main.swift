import Foundation
import ShopPilotCore

/// SPK-0906 — Verify the laser cut/engrave G-code engine.
/// Proves: validate() accepts valid config / rejects power > 100,
/// generateToolpath returns success with estimatedTime > 0,
/// gcodeForCut emits M3/M5/G1 with the correct F value and pass count,
/// gcodeForEngrave emits raster-style lines at reduced speed,
/// gcodeForMode dispatches, LaserConfig Codable round-trips.

enum Verify0906 {
    static func run() {
        var pass = 0
        var fail = 0

        // Closed 40mm square path (mm coordinates, last == first).
        let path: [(Double, Double)] = [(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)]

        // 1. validate() accepts a valid config and rejects power > 100.
        let valid = LaserEngine.createConfig(mode: .cut, powerPercent: 80.0, speedMmPerMin: 1200.0)
        let (vOK, vErr) = LaserEngine.validate(valid)
        if vOK && vErr.isEmpty {
            pass += 1
            print("✓ validate() accepts a valid laser config")
        } else {
            fail += 1
            print("✗ validate() rejected a valid config: \(vErr)")
        }
        var bad = valid
        bad.powerPercent = 150.0
        let (bOK, bErr) = LaserEngine.validate(bad)
        if !bOK && bErr.contains(where: { $0.contains("Power") }) {
            pass += 1
            print("✓ validate() rejects power 150%")
        } else {
            fail += 1
            print("✗ validate() accepted power 150%: \(bErr)")
        }

        // 2. generateToolpath returns success with estimatedTime > 0.
        let result = LaserEngine.generateToolpath(config: valid, pathLengthMm: 40.0)
        if result.success && result.estimatedTimeMinutes > 0 {
            pass += 1
            print("✓ generateToolpath success, estimated \(String(format: "%.3f", result.estimatedTimeMinutes)) min, cutDepth \(String(format: "%.2f", result.cutDepthMm)) mm")
        } else {
            fail += 1
            print("✗ generateToolpath failed: \(result.errorMessage ?? "unknown")")
        }

        // 3. gcodeForCut: M3/M5 per pass, G1 F<speed>, Z lifts, pass loop.
        var multiPass = valid
        multiPass.passes = 3
        let cut = LaserEngine.gcodeForCut(config: multiPass, path: path)
        let m3Count = cut.filter { $0.hasPrefix("M3") }.count
        let m5Count = cut.filter { $0 == "M5" }.count
        let hasCorrectF = cut.contains { $0 == "G1 F1200" }
        let g1Moves = cut.filter { $0.hasPrefix("G1 X") }.count
        let zLifts = cut.filter { $0.hasPrefix("G0 Z") }.count
        // Path has 4 trailing points (last == first → no extra close line): 4 G1 moves/pass × 3.
        if m3Count == 3 && m5Count == 3 && hasCorrectF && g1Moves == 12 && zLifts == 3 {
            pass += 1
            print("✓ gcodeForCut: 3 passes → 3×M3, 3×M5, G1 F1200, \(g1Moves) G1 moves, \(zLifts) Z lifts")
        } else {
            fail += 1
            print("✗ gcodeForCut: M3=\(m3Count) M5=\(m5Count) F1200=\(hasCorrectF) G1=\(g1Moves) lifts=\(zLifts)")
        }

        // 4. gcodeForEngrave: raster-style, constant power, reduced speed, ends M5.
        let engraveConfig = LaserEngine.createConfig(mode: .engrave, powerPercent: 40.0, speedMmPerMin: 500.0)
        let eng = LaserEngine.gcodeForEngrave(config: engraveConfig, path: path)
        let engM3 = eng.filter { $0.hasPrefix("M3") }.count
        let hasHalfSpeed = eng.contains { $0 == "G1 F250" }
        let endsWithM5 = eng.last == "M5"
        if engM3 == 1 && hasHalfSpeed && endsWithM5 {
            pass += 1
            print("✓ gcodeForEngrave: raster-style M3 constant power, G1 F250 (half speed), ends M5")
        } else {
            fail += 1
            print("✗ gcodeForEngrave: M3=\(engM3) F250=\(hasHalfSpeed) endsM5=\(endsWithM5)")
        }

        // 5. gcodeForMode dispatches cut → cutting feed, engrave → engraving feed.
        let cutByMode = LaserEngine.gcodeForMode(config: valid, path: path)
        let engByMode = LaserEngine.gcodeForMode(config: engraveConfig, path: path)
        if cutByMode.contains(where: { $0 == "G1 F1200" })
            && !cutByMode.contains(where: { $0 == "G1 F250" })
            && engByMode.contains(where: { $0 == "G1 F250" }) {
            pass += 1
            print("✓ gcodeForMode dispatches cut → F1200, engrave → F250")
        } else {
            fail += 1
            print("✗ gcodeForMode dispatch mismatch")
        }

        // 6. LaserConfig Codable round-trip.
        let original = LaserConfig(
            mode: .cut,
            powerPercent: 75.0,
            speedMmPerMin: 900.0,
            frequencyHz: 20000.0,
            passes: 2,
            powerMode: .pulse,
            kerfWidth: 0.2,
            focusOffset: -1.5,
            assistGas: true,
            airAssist: false
        )
        if let data = try? JSONEncoder().encode(original),
           let decoded = try? JSONDecoder().decode(LaserConfig.self, from: data),
           decoded.mode == .cut,
           abs(decoded.powerPercent - 75.0) < 1e-9,
           abs(decoded.speedMmPerMin - 900.0) < 1e-9,
           abs(decoded.frequencyHz - 20000.0) < 1e-9,
           decoded.passes == 2,
           decoded.powerMode == .pulse,
           abs(decoded.kerfWidth - 0.2) < 1e-9,
           abs(decoded.focusOffset - (-1.5)) < 1e-9,
           decoded.assistGas == true,
           decoded.airAssist == false {
            pass += 1
            print("✓ LaserConfig Codable round-trip (all fields preserved)")
        } else {
            fail += 1
            print("✗ LaserConfig Codable round-trip failed")
        }

        print("\nSPK-0906 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0906 — laser validate, estimates, cut/engrave G-code, dispatcher, Codable round-trip verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0906.run()
