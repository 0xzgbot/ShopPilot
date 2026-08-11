import Foundation
import ShopPilotCore

/// SPK-0711 — Verify zero plane + boundary engine.
/// Proves: computeZeroPlane, computeBoundary (single + multi component merge),
/// computeWorkArea, validate, Codable round-trip.

enum Verify0711 {
    static func run() {
        var pass = 0
        var fail = 0

        // 1. computeZeroPlane from component bounds.
        let box = BoundingBox3D(minX: 0, minY: 0, minZ: 2.0, maxX: 100, maxY: 80, maxZ: 12.0)
        let plane = ZeroPlaneAndBoundaryEngine.computeZeroPlane(componentBoundingBox: box, offsetFromMinZ: 0)
        if abs(plane - 2.0) < 1e-9 {
            pass += 1; print("✓ computeZeroPlane = minZ = 2.0")
        } else {
            fail += 1; print("✗ computeZeroPlane = \(plane), expected 2.0")
        }
        let planeOffset = ZeroPlaneAndBoundaryEngine.computeZeroPlane(componentBoundingBox: box, offsetFromMinZ: -1.0)
        if abs(planeOffset - 1.0) < 1e-9 {
            pass += 1; print("✓ computeZeroPlane with offset −1 = 1.0")
        } else {
            fail += 1; print("✗ computeZeroPlane offset = \(planeOffset)")
        }

        // 2. computeBoundary adds safety margin.
        let boundary = ZeroPlaneAndBoundaryEngine.computeBoundary(componentBoundingBox: box, safetyMargin: 5.0)
        if abs(boundary.minX - (-5)) < 1e-9
            && abs(boundary.maxX - 105) < 1e-9
            && abs(boundary.minY - (-5)) < 1e-9
            && abs(boundary.maxY - 85) < 1e-9
            && boundary.source == .componentBounds {
            pass += 1; print("✓ computeBoundary: ±5mm margin around component bounds")
        } else {
            fail += 1; print("✗ computeBoundary wrong: \(boundary.minX)...\(boundary.maxX), \(boundary.minY)...\(boundary.maxY)")
        }

        // 3. computeWorkArea (single) — area + originZ from zero plane.
        let area = ZeroPlaneAndBoundaryEngine.computeWorkArea(
            componentBoundingBox: box,
            zeroPlaneOffset: 0,
            boundarySafetyMargin: 5.0
        )
        if abs(area.areaWidth - 110) < 1e-9
            && abs(area.areaHeight - 90) < 1e-9
            && abs(area.area - 9900) < 1e-9
            && abs(area.originZ - 2.0) < 1e-9 {
            pass += 1; print("✓ computeWorkArea single: 110×90 mm, area 9900, originZ = zero plane")
        } else {
            fail += 1; print("✗ computeWorkArea single wrong: \(area.areaWidth)×\(area.areaHeight), area \(area.area), z \(area.originZ)")
        }

        // 4. computeWorkArea (multi) — merged bounds.
        let boxA = BoundingBox3D(minX: 0, minY: 0, minZ: 0, maxX: 50, maxY: 50, maxZ: 10)
        let boxB = BoundingBox3D(minX: 20, minY: 30, minZ: 2, maxX: 100, maxY: 90, maxZ: 15)
        let multi = ZeroPlaneAndBoundaryEngine.computeWorkArea(
            componentBoundingBoxes: [boxA, boxB],
            zeroPlaneOffset: 0,
            boundarySafetyMargin: 0
        )
        if abs(multi.boundingBox.minX - 0) < 1e-9
            && abs(multi.boundingBox.maxX - 100) < 1e-9
            && abs(multi.boundingBox.minY - 0) < 1e-9
            && abs(multi.boundingBox.maxY - 90) < 1e-9
            && abs(multi.boundingBox.minZ - 0) < 1e-9
            && abs(multi.boundingBox.maxZ - 15) < 1e-9 {
            pass += 1; print("✓ computeWorkArea multi: merged bounds (0,0,0)–(100,90,15)")
        } else {
            fail += 1; print("✗ computeWorkArea multi merge wrong")
        }

        // 5. Empty input → no crash; degenerate box + margin → 10×10 mm.
        let empty = ZeroPlaneAndBoundaryEngine.computeWorkArea(
            componentBoundingBoxes: [],
            zeroPlaneOffset: 0,
            boundarySafetyMargin: 5.0
        )
        if abs(empty.areaWidth - 10) < 1e-9 && abs(empty.areaHeight - 10) < 1e-9 {
            pass += 1; print("✓ computeWorkArea empty input → 10×10 (margin around degenerate box), no crash")
        } else {
            fail += 1; print("✗ computeWorkArea empty input → \(empty.areaWidth)×\(empty.areaHeight)")
        }

        // 6. validate — valid area passes; degenerate (zero-width) area fails.
        let (valid, _) = ZeroPlaneAndBoundaryEngine.validate(area)
        if valid {
            pass += 1; print("✓ validate accepts valid work area")
        } else {
            fail += 1; print("✗ validate rejected valid work area")
        }
        let degenerate = WorkArea(
            zeroPlane: ZeroPlaneConfig(planeZ: 0),
            boundary: BoundaryConfig(source: .customRectangle, minX: 5, minY: 0, maxX: 5, maxY: 10, safetyMargin: 0),
            boundingBox: BoundingBox3D(minX: 5, minY: 0, minZ: 0, maxX: 5, maxY: 10, maxZ: 1)
        )
        let (invalid, errors) = ZeroPlaneAndBoundaryEngine.validate(degenerate)
        if !invalid && !errors.isEmpty {
            pass += 1; print("✓ validate rejects zero-width area (\(errors.count) errors)")
        } else {
            fail += 1; print("✗ validate accepted zero-width area")
        }

        // 7. Codable round-trip of ZeroPlaneConfig / BoundaryConfig / WorkArea.
        let zc = ZeroPlaneConfig(planeZ: 3.5, autoDetect: false, offsetFromMinZ: 0.5, componentID: UUID())
        let bc = BoundaryConfig(source: .customRectangle, minX: 10, minY: 20, maxX: 200, maxY: 150, safetyMargin: 2.5)
        if let zcData = try? JSONEncoder().encode(zc),
           let zcBack = try? JSONDecoder().decode(ZeroPlaneConfig.self, from: zcData),
           zcBack.planeZ == 3.5, zcBack.autoDetect == false, zcBack.offsetFromMinZ == 0.5 {
            pass += 1; print("✓ ZeroPlaneConfig Codable round-trip")
        } else {
            fail += 1; print("✗ ZeroPlaneConfig Codable round-trip failed")
        }
        if let bcData = try? JSONEncoder().encode(bc),
           let bcBack = try? JSONDecoder().decode(BoundaryConfig.self, from: bcData),
           bcBack.source == .customRectangle, bcBack.safetyMargin == 2.5, bcBack.maxX == 200 {
            pass += 1; print("✓ BoundaryConfig Codable round-trip")
        } else {
            fail += 1; print("✗ BoundaryConfig Codable round-trip failed")
        }
        if let waData = try? JSONEncoder().encode(area),
           let waBack = try? JSONDecoder().decode(WorkArea.self, from: waData),
           abs(waBack.areaWidth - 110) < 1e-9, abs(waBack.originZ - 2.0) < 1e-9 {
            pass += 1; print("✓ WorkArea Codable round-trip")
        } else {
            fail += 1; print("✗ WorkArea Codable round-trip failed")
        }

        print("\nSPK-0711 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0711 — zero plane, boundary, single/multi work area, validation, Codable verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0711.run()
print("ShopPilotVerify0711: PASS — computeZeroPlane + offset verified")
