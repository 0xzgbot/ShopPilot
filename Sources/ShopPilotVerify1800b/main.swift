import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1800b verify (CLT machine, no XCTest).
/// Marquee select math — pure helpers so the CLT can test without SwiftUI:
///   1. Bounds-intersection: shape whose bbox intersects the marquee rect is selected.
///   2. Empty drag = marquee (not pan); Space+drag or middle-button = pan.
///   3. Marquee hit-test uses screen-space bounds union.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// SPK-1800b: axis-aligned bounds of a set of points.
func boundingBox(_ pts: [CGPoint]) -> CGRect? {
    guard let first = pts.first else { return nil }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for p in pts.dropFirst() {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// SPK-1800b: marquee hit-test — shape bbox intersects marquee rect.
func marqueeHits(_ shapeBounds: CGRect, _ marquee: CGRect) -> Bool {
    shapeBounds.intersects(marquee)
}

// 1. Intersection: small rect fully inside marquee.
let shapeBounds = CGRect(x: 50, y: 50, width: 20, height: 20)
let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
try expect(marqueeHits(shapeBounds, marquee), "shape inside marquee is selected")

// 2. Edge intersection: shape partially inside marquee.
let partialBounds = CGRect(x: 90, y: 90, width: 30, height: 30)
try expect(marqueeHits(partialBounds, marquee), "partial overlap selected")

// 3. No intersection: shape outside marquee.
let outsideBounds = CGRect(x: 200, y: 200, width: 10, height: 10)
try expect(!marqueeHits(outsideBounds, marquee), "outside shape not selected")

// 4. Bounding box of points matches expected rect.
let pts = [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40), CGPoint(x: 5, y: 50)]
let bbox = boundingBox(pts)!
try expect(bbox == CGRect(x: 5, y: 20, width: 25, height: 30), "bbox union correct")

// 5. Empty points → nil bbox.
try expect(boundingBox([]) == nil, "empty points → nil bbox")

// 6. Space pan gating logic.
func isPanning(spaceKeyDown: Bool, pressedMouseButtons: Set<Int>) -> Bool {
    spaceKeyDown || pressedMouseButtons.contains(2)
}
try expect(isPanning(spaceKeyDown: true, pressedMouseButtons: []), "Space alone pans")
try expect(isPanning(spaceKeyDown: false, pressedMouseButtons: [2]), "middle button alone pans")
try expect(isPanning(spaceKeyDown: true, pressedMouseButtons: [2]), "both pans")
try expect(!isPanning(spaceKeyDown: false, pressedMouseButtons: [1]), "left button alone doesn't pan")
try expect(!isPanning(spaceKeyDown: false, pressedMouseButtons: []), "no input doesn't pan")

print("ShopPilotVerify1800b: PASS — marquee bounds-intersection, pan gating")
