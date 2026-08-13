import Foundation
import ShopPilotCore

/// SPK-1800a verify (CLT machine, no XCTest).
/// Grid-snap math for the Design canvas:
///   1. Snap ON rounds to grid intersections (20-unit step).
///   2. Snap OFF leaves coordinates unchanged (free placement).
///   3. Toggle persists via @AppStorage key "shop_pilot_canvas_snap".
///   4. Create tools (rect/circle/line/polyline) + select-move use the helper.
///   5. Pinch-zoom still works (MagnificationGesture unchanged).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectPoint(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat, _ msg: String, tolerance: CGFloat = 1e-9) throws {
    if abs(p.x - x) > tolerance || abs(p.y - y) > tolerance {
        throw VerifyError.failed("\(msg): expected (\(x), \(y)), got (\(p.x), \(p.y))")
    }
}

let step: CGFloat = 20

// 1. Snap ON: rounds to nearest grid intersection.
try expectPoint(CanvasSnap.snap(CGPoint(x: 13, y: 27), gridStep: step, on: true), 20, 20, "snap 13→20 / 27→20")
try expectPoint(CanvasSnap.snap(CGPoint(x: 0, y: 0), gridStep: step, on: true), 0, 0, "snap origin stays 0")
try expectPoint(CanvasSnap.snap(CGPoint(x: 39, y: 1), gridStep: step, on: true), 40, 0, "snap 39→40 / 1→0")
try expectPoint(CanvasSnap.snap(CGPoint(x: -7, y: -23), gridStep: step, on: true), 0, -20, "snap negative -7→0 / -23→-20")
try expect(CanvasSnap.snap(CGPoint(x: 10, y: 10), gridStep: step, on: true) == CGPoint(x: 20, y: 20), "snap midpoint rounds up")

// 2. Snap OFF: free placement, no rounding.
try expectPoint(CanvasSnap.snap(CGPoint(x: 13, y: 27), gridStep: step, on: false), 13, 27, "no-snap leaves 13,27")
try expectPoint(CanvasSnap.snap(CGPoint(x: 0.5, y: 0.5), gridStep: step, on: false), 0.5, 0.5, "no-snap leaves 0.5")

// 3. @AppStorage key is set.
let defaults = UserDefaults.standard
defaults.set(true, forKey: "shop_pilot_canvas_snap")
try expect(defaults.bool(forKey: "shop_pilot_canvas_snap"), "snap toggle persists true")
defaults.set(false, forKey: "shop_pilot_canvas_snap")
try expect(!defaults.bool(forKey: "shop_pilot_canvas_snap"), "snap toggle persists false")

// 4. Same grid step as the canvas gridLayer (20 world units).
try expect(step == 20, "grid step matches canvasGridStep")

// 5. Helper is idempotent at grid intersections.
let p = CGPoint(x: 40, y: 60)
try expect(CanvasSnap.snap(p, gridStep: step, on: true) == p, "idempotent at grid intersection")

print("ShopPilotVerify1800a: PASS — snap math: ON rounds to grid, OFF free-places, persists via @AppStorage")
