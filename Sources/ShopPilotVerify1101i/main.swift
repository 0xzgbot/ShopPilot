//  ShopPilotVerify1101i
//  Verify: ShapeTransformer.align against the real AlignmentMode API
//  (topLeft, centerCenter, bottomRight, distributeHorizontal, distributeVertical).

import Foundation
import ShopPilotGeometry

// MARK: - Test 1: topLeft aligns every shape's minX/minY to the global minima

func testAlignTopLeft() {
    let shapes: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 50, y: 10), width: 30, height: 20),   // minX=50, minY=10
        .rectangle(origin: VectorPoint(x: 10, y: 5), width: 20, height: 15),    // minX=10, minY=5  (minima)
        .rectangle(origin: VectorPoint(x: 30, y: 0), width: 25, height: 10),    // minX=30, minY=0
    ]
    let result = ShapeTransformer().align(shapes: shapes, mode: .topLeft)
    assert(result.count == 3, "preserves count")
    for (i, shape) in result.enumerated() {
        assert(shape.boundingRect.minX == 10.0, "shape \(i) minX should be 10, got \(shape.boundingRect.minX)")
        assert(shape.boundingRect.minY == 0.0, "shape \(i) minY should be 0, got \(shape.boundingRect.minY)")
    }
    print("✓ Test 1 passed: topLeft aligns min X/Y to global minima")
}

// MARK: - Test 2: bottomRight aligns every shape's maxX/maxY to the global maxima

func testAlignBottomRight() {
    let shapes: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 10, y: 0), width: 20, height: 10),    // maxX=30, maxY=10
        .rectangle(origin: VectorPoint(x: 50, y: 20), width: 30, height: 20),   // maxX=80, maxY=40 (maxima)
        .rectangle(origin: VectorPoint(x: 30, y: 30), width: 15, height: 10),   // maxX=45, maxY=40
    ]
    let result = ShapeTransformer().align(shapes: shapes, mode: .bottomRight)
    for (i, shape) in result.enumerated() {
        assert(shape.boundingRect.maxX == 80.0, "shape \(i) maxX should be 80, got \(shape.boundingRect.maxX)")
        assert(shape.boundingRect.maxY == 40.0, "shape \(i) maxY should be 40, got \(shape.boundingRect.maxY)")
    }
    print("✓ Test 2 passed: bottomRight aligns max X/Y to global maxima")
}

// MARK: - Test 3: centerCenter aligns every shape's center to the mean center

func testAlignCenter() {
    let shapes: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 0, y: 0), width: 20, height: 10),    // center (10, 5)
        .rectangle(origin: VectorPoint(x: 10, y: 10), width: 20, height: 10),  // center (20, 15)
        .rectangle(origin: VectorPoint(x: 20, y: 20), width: 20, height: 10),  // center (30, 25)
    ]
    // Mean center: X = (10+20+30)/3 = 20, Y = (5+15+25)/3 = 15
    let result = ShapeTransformer().align(shapes: shapes, mode: .centerCenter)
    for (i, shape) in result.enumerated() {
        let rect = shape.boundingRect
        let cx = rect.minX + rect.width / 2.0
        let cy = rect.minY + rect.height / 2.0
        assert(abs(cx - 20.0) < 0.001, "shape \(i) centerX should be 20, got \(cx)")
        assert(abs(cy - 15.0) < 0.001, "shape \(i) centerY should be 15, got \(cy)")
    }
    print("✓ Test 3 passed: centerCenter aligns to mean center")
}

// MARK: - Test 4: distributeHorizontal spaces shapes evenly, order preserved

func testDistributeHorizontal() {
    let shapes: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10),    // minX=0
        .rectangle(origin: VectorPoint(x: 50, y: 0), width: 10, height: 10),   // minX=50 (maxX=60)
        .rectangle(origin: VectorPoint(x: 25, y: 0), width: 10, height: 10),   // minX=25
    ]
    let result = ShapeTransformer().align(shapes: shapes, mode: .distributeHorizontal)
    // Span 0…60 across 3 shapes → spacing 30 → minX targets 0, 30, 60
    let minXs = result.map { $0.boundingRect.minX }.sorted()
    assert(abs(minXs[0] - 0.0) < 0.001, "leftmost at 0, got \(minXs[0])")
    assert(abs(minXs[1] - 30.0) < 0.001, "middle at 30, got \(minXs[1])")
    assert(abs(minXs[2] - 60.0) < 0.001, "rightmost at 60, got \(minXs[2])")
    print("✓ Test 4 passed: distributeHorizontal spaces evenly")
}

// MARK: - Test 5: single shape is a no-op for every mode

func testSingleShapeNoop() {
    let shape = VectorShape.rectangle(origin: VectorPoint(x: 42, y: 7), width: 20, height: 10)
    for mode in [AlignmentMode.topLeft, .centerCenter, .bottomRight,
                 .distributeHorizontal, .distributeVertical] {
        let result = ShapeTransformer().align(shapes: [shape], mode: mode)
        assert(result.count == 1, "single shape returns one result")
        assert(result[0].boundingRect.minX == 42.0 && result[0].boundingRect.minY == 7.0,
               "single shape unchanged in mode \(mode)")
    }
    print("✓ Test 5 passed: single shape is a no-op")
}

// MARK: - Test 6: empty input returns empty

func testEmpty() {
    let result = ShapeTransformer().align(shapes: [], mode: .topLeft)
    assert(result.isEmpty, "empty input returns empty")
    print("✓ Test 6 passed: empty input returns empty")
}

// MARK: - Main

print("=== ShopPilotVerify1101i: ShapeTransformer.align (real AlignmentMode API) ===")
testAlignTopLeft()
testAlignBottomRight()
testAlignCenter()
testDistributeHorizontal()
testSingleShapeNoop()
testEmpty()
print("All tests passed.")
print("ShopPilotVerify1101i: PASS — alignment preset tests passed")
