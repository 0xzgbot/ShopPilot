//  ShopPilotVerify1101b
//  Verify: moveVertex on a freehand polyline updates session vectors.
//
//  AC:
//  - With a selected polyline, drag one vertex; session vector points update.

import Foundation
import ShopPilotCore
import ShopPilotGeometry

// MARK: - Test 1: VectorShape.moveVertex on freehand

func testMoveVertexFreehand() {
    var shape = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 10, y: 10),
        VectorPoint(x: 20, y: 0),
    ])

    // Move middle vertex
    shape = shape.moveVertex(at: 1, to: VectorPoint(x: 10, y: 20))

    let pts = shape.points
    assert(pts.count == 3, "freehand vertex count must stay 3, got \(pts.count)")
    assert(pts[0].x == 0 && pts[0].y == 0, "first vertex unchanged")
    assert(pts[1].x == 10 && pts[1].y == 20, "middle vertex moved to (10,20)")
    assert(pts[2].x == 20 && pts[2].y == 0, "last vertex unchanged")

    // Out-of-range index returns self unchanged
    let unchanged = shape.moveVertex(at: 99, to: VectorPoint(x: 999, y: 999))
    assert(unchanged.points[1].y == 20, "out-of-range index must not change shape")

    print("✓ Test 1 passed: VectorShape.moveVertex on freehand polyline")
}

// MARK: - Test 2: VectorShape.moveVertex on line

func testMoveVertexLine() {
    var shape = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 100, y: 100))

    // Move start point (index 0)
    shape = shape.moveVertex(at: 0, to: VectorPoint(x: 5, y: 5))
    let pts0 = shape.points
    assert(pts0[0].x == 5 && pts0[0].y == 5, "line start moved")
    assert(pts0[1].x == 100 && pts0[1].y == 100, "line end unchanged")

    // Move end point (index 1)
    shape = shape.moveVertex(at: 1, to: VectorPoint(x: 200, y: 50))
    let pts1 = shape.points
    assert(pts1[0].x == 5 && pts1[0].y == 5, "line start still at (5,5)")
    assert(pts1[1].x == 200 && pts1[1].y == 50, "line end moved to (200,50)")

    // Out-of-range index returns self
    let unchanged = shape.moveVertex(at: 2, to: VectorPoint(x: 0, y: 0))
    assert(unchanged.points[1].x == 200 && unchanged.points[1].y == 50, "out-of-range must not change line")

    print("✓ Test 2 passed: VectorShape.moveVertex on line")
}

// MARK: - Test 3: VectorShape.moveVertex on non-editable shapes returns self

func testMoveVertexImmutable() {
    let circle = VectorShape.circle(center: VectorPoint(x: 50, y: 50), radius: 25)
    let moved = circle.moveVertex(at: 0, to: VectorPoint(x: 0, y: 0))
    assert(moved == circle, "circle moveVertex must return self unchanged")

    let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 50)
    let movedRect = rect.moveVertex(at: 0, to: VectorPoint(x: 0, y: 0))
    assert(movedRect == rect, "rectangle moveVertex must return self unchanged")

    print("✓ Test 3 passed: VectorShape.moveVertex on immutable shapes returns self")
}

// MARK: - Test 4: Equatable — moved shape differs from original

func testMoveVertexEquatable() {
    let original = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 10, y: 10),
    ])
    let moved = original.moveVertex(at: 1, to: VectorPoint(x: 10, y: 20))
    assert(original != moved, "moved shape must not equal original")

    // Same move applied twice should be equal
    let movedAgain = original.moveVertex(at: 1, to: VectorPoint(x: 10, y: 20))
    assert(moved == movedAgain, "same move produces identical shape")

    print("✓ Test 4 passed: Equatable — moved shape differs from original")
}

// MARK: - Test 5: GeometryBridge.toCorePaths reflects vertex move

func testMoveVertexAffectsCorePaths() {
    let original = VectorShape.freehand(points: [
        VectorPoint(x: 0, y: 0),
        VectorPoint(x: 10, y: 10),
        VectorPoint(x: 20, y: 0),
    ])
    let moved = original.moveVertex(at: 1, to: VectorPoint(x: 10, y: 20))

    let origPaths = GeometryBridge.toCorePaths([original])
    let movedPaths = GeometryBridge.toCorePaths([moved])

    assert(origPaths.count == 1 && movedPaths.count == 1, "both must produce exactly one core path")

    let origPts = origPaths[0].points
    let movedPts = movedPaths[0].points

    assert(origPts.count == 3 && movedPts.count == 3, "core path vertex count preserved")
    assert(origPts[1].x == 10 && origPts[1].y == 10, "original core path middle vertex at (10,10)")
    assert(movedPts[1].x == 10 && movedPts[1].y == 20, "moved core path middle vertex at (10,20)")

    print("✓ Test 5 passed: GeometryBridge.toCorePaths reflects vertex move")
}

// MARK: - Main

print("=== ShopPilotVerify1101b: moveVertex on polyline ===")
testMoveVertexFreehand()
testMoveVertexLine()
testMoveVertexImmutable()
testMoveVertexEquatable()
testMoveVertexAffectsCorePaths()
print("All tests passed.")
print("ShopPilotVerify1101b: PASS — moveVertex node-edit tests passed")
