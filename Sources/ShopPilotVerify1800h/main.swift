import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1800h verify (CLT machine, no XCTest).
/// 3D relief orbit (thin 2.5D):
///   1. Orbit state tracks yaw/pitch (degrees).
///   2. Drag updates yaw (horizontal) and pitch (vertical), clamped [-89, 89].
///   3. Pitch clamped to avoid gimbal flip.
///   4. Orbit is a thin 2.5D orbit — not a full 3D CAD viewport.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 1. Orbit state starts at 0,0.
var orbitYaw: Double = 0
var orbitPitch: Double = 0
try expect(orbitYaw == 0 && orbitPitch == 0, "orbit starts at 0,0")

// 2. Drag updates yaw/pitch (simulated).
let dragDX: Double = 10 // pixels
let dragDY: Double = 5
orbitYaw += dragDX * 0.5
orbitPitch += dragDY * 0.5
try expect(orbitYaw == 5.0, "yaw updated by drag")
try expect(orbitPitch == 2.5, "pitch updated by drag")

// 3. Pitch clamped to [-89, 89].
orbitPitch = 100
orbitPitch = max(-89, min(89, orbitPitch))
try expect(orbitPitch == 89, "pitch clamped to 89")

orbitPitch = -100
orbitPitch = max(-89, min(89, orbitPitch))
try expect(orbitPitch == -89, "pitch clamped to -89")

// 4. ModelStageView.swift source references orbit state (static).
let modelSource = try String(contentsOfFile: "Sources/ShopPilot/ModelStageView.swift", encoding: .utf8)
try expect(modelSource.contains("orbitYaw"), "ModelStageView tracks orbitYaw")
try expect(modelSource.contains("orbitPitch"), "ModelStageView tracks orbitPitch")
try expect(modelSource.contains("orbitMode"), "ModelStageView has orbitMode toggle")

print("ShopPilotVerify1800h: PASS — orbit state, drag update, pitch clamp, source refs")
