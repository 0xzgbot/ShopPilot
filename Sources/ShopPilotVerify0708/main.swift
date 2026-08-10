import Foundation
import ShopPilotCore

/// SPK-0708 — Verify the Metal composite render engine.
/// Proves: material presets (7), config Codable round-trip, config clamping,
/// preset→config creation, real PNG render output (file exists, non-zero size).

enum Verify0708 {
    static func run() {
        var pass = 0
        var fail = 0

        // 1. Preset catalog: exactly 7 presets, unique names.
        let presets = MetalCompositeRenderEngine.presets
        let names = Set(presets.map { $0.name })
        if presets.count == 7 && names.count == 7 {
            pass += 1
            print("✓ Preset catalog: 7 unique presets")
        } else {
            fail += 1
            print("✗ Preset catalog: expected 7 unique, got \(presets.count) presets / \(names.count) unique")
        }

        // 2. Each preset has valid ranges (0...1).
        var rangesOK = true
        for p in presets {
            if p.reflectivity < 0 || p.reflectivity > 1
                || p.roughness < 0 || p.roughness > 1
                || p.metalness < 0 || p.metalness > 1 {
                rangesOK = false
                print("  preset \(p.name) out of range")
            }
        }
        if rangesOK {
            pass += 1
            print("✓ All preset material params in [0, 1]")
        } else {
            fail += 1
            print("✗ Preset material params out of range")
        }

        // 3. getPreset by name.
        if let preset = MetalCompositeRenderEngine.getPreset(named: "Polished Steel"),
           preset.material == .steel, preset.finish == .polished, preset.metalness == 1.0 {
            pass += 1
            print("✓ getPreset(\"Polished Steel\") returns correct preset")
        } else {
            fail += 1
            print("✗ getPreset(\"Polished Steel\") failed")
        }
        if MetalCompositeRenderEngine.getPreset(named: "Nonexistent") == nil {
            pass += 1
            print("✓ getPreset(nonexistent) → nil")
        } else {
            fail += 1
            print("✗ getPreset(nonexistent) should be nil")
        }

        // 4. createConfig from preset.
        let preset = MetalCompositeRenderEngine.presets[0]
        let compID = UUID()
        let cfg = MetalCompositeRenderEngine.createConfig(preset: preset, componentID: compID)
        if cfg.material == preset.material
            && cfg.finish == preset.finish
            && cfg.reflectivity == preset.reflectivity
            && cfg.componentID == compID {
            pass += 1
            print("✓ createConfig(preset:) carries preset values + componentID")
        } else {
            fail += 1
            print("✗ createConfig(preset:) mismatch")
        }

        // 5. Config Codable round-trip.
        let original = MetalCompositeConfig(
            material: .copper,
            finish: .sandblasted,
            lighting: RenderLighting(ambientIntensity: 0.4, directionalIntensity: 1.5, directionalAngle: 60),
            reflectivity: 0.65,
            roughness: 0.42,
            metalness: 0.88,
            componentID: compID
        )
        if let data = try? JSONEncoder().encode(original),
           let decoded = try? JSONDecoder().decode(MetalCompositeConfig.self, from: data),
           decoded.material == .copper,
           decoded.finish == .sandblasted,
           abs(decoded.lighting.directionalAngle - 60) < 1e-9,
           abs(decoded.reflectivity - 0.65) < 1e-9,
           decoded.componentID == compID {
            pass += 1
            print("✓ MetalCompositeConfig Codable round-trip")
        } else {
            fail += 1
            print("✗ MetalCompositeConfig Codable round-trip failed")
        }

        // 6. Config clamping.
        let clamped = MetalCompositeConfig(
            material: .plastic,
            finish: .matte,
            reflectivity: 1.7,
            roughness: -0.3,
            metalness: 0.5
        )
        if clamped.reflectivity == 1.0 && clamped.roughness == 0.0 {
            pass += 1
            print("✓ Config clamping (reflectivity 1.7→1.0, roughness −0.3→0.0)")
        } else {
            fail += 1
            print("✗ Config clamping failed: \(clamped.reflectivity), \(clamped.roughness)")
        }

        // 7. validate() accepts valid config and rejects out-of-range.
        let valid = MetalCompositeConfig(material: .aluminum, finish: .brushed)
        let (vOK, vErr) = MetalCompositeRenderEngine.validate(valid)
        if vOK && vErr == nil {
            pass += 1
            print("✓ validate() accepts valid config")
        } else {
            fail += 1
            print("✗ validate() rejected valid config: \(vErr ?? "nil")")
        }
        var bad = valid
        bad.reflectivity = 2.0
        let (bOK, _) = MetalCompositeRenderEngine.validate(bad)
        if !bOK {
            pass += 1
            print("✓ validate() rejects reflectivity 2.0")
        } else {
            fail += 1
            print("✗ validate() accepted reflectivity 2.0")
        }

        // 8. render() produces a real PNG on disk.
        let renderConfig = MetalCompositeConfig(
            material: .brass,
            finish: .brushed,
            lighting: RenderLighting(ambientIntensity: 0.3, directionalIntensity: 1.0, directionalAngle: 45),
            reflectivity: 0.6,
            roughness: 0.4,
            metalness: 0.8,
            componentID: compID
        )
        let output = MetalCompositeRenderEngine.render(renderConfig)
        if output.success {
            pass += 1
            print("✓ render() reports success")
        } else {
            fail += 1
            print("✗ render() failed: \(output.errorMessage ?? "unknown")")
        }
        if output.width == 512 && output.height == 512 {
            pass += 1
            print("✓ render() output size 512×512")
        } else {
            fail += 1
            print("✗ render() size: \(output.width)×\(output.height)")
        }
        if output.fileSize > 0 {
            pass += 1
            print("✓ render() PNG file on disk (\(output.fileSize) bytes)")
        } else {
            fail += 1
            print("✗ render() PNG file is empty/missing")
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: output.imageUrl),
           let size = attrs[.size] as? Int64, size > 0 {
            pass += 1
            print("✓ render() file verified on disk via attributes")
        } else {
            fail += 1
            print("✗ render() file not found at \(output.imageUrl)")
        }

        print("\nSPK-0708 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0708 — material presets, config Codable, clamping, validation, real PNG render verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0708.run()
