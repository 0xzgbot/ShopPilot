import XCTest
@testable import ShopPilotGeometry

final class ShopPilotGeometryTests: XCTestCase {
    
    // MARK: - VectorShape Tests
    
    func testLineAreaIsZero() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 100, y: 0))
        XCTAssertEqual(line.area, 0.0, accuracy: 1e-9)
    }
    
    func testCircleArea() {
        let circle = VectorShape.circle(center: VectorPoint(x: 50, y: 50), radius: 25.0)
        XCTAssertEqual(circle.area, Double.pi * 25.0 * 25.0, accuracy: 1e-6)
    }
    
    func testRectangleArea() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 50)
        XCTAssertEqual(rect.area, 5000.0, accuracy: 1e-9)
    }
    
    // MARK: - Translation
    
    func testLineTranslation() {
        let line = VectorShape.line(start: VectorPoint(x: 10, y: 10), end: VectorPoint(x: 50, y: 10))
        let translated = line.translated(by: 5, 3)
        
        if case .line(let start, let end) = translated {
            XCTAssertEqual(start.x, 15.0, accuracy: 1e-9)
            XCTAssertEqual(start.y, 13.0, accuracy: 1e-9)
            XCTAssertEqual(end.x, 55.0, accuracy: 1e-9)
            XCTAssertEqual(end.y, 13.0, accuracy: 1e-9)
        } else {
            XCTFail("Translation failed")
        }
    }
    
    // MARK: - Node Extraction / Reconstruction
    
    func testLineNodeExtraction() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 100, y: 100))
        let nodes = line.extractNodes()
        
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].point, VectorPoint(x: 0, y: 0))
        XCTAssertEqual(nodes[1].point, VectorPoint(x: 100, y: 100))
    }
    
    func testCircleNodeExtraction() {
        let circle = VectorShape.circle(center: VectorPoint(x: 50, y: 50), radius: 25.0)
        let nodes = circle.extractNodes()
        
        XCTAssertGreaterThanOrEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].point, VectorPoint(x: 50, y: 50))
    }
    
    // MARK: - Transform Tests
    
    func testLineRotation90() {
        let line = VectorShape.line(start: VectorPoint(x: 1, y: 0), end: VectorPoint(x: 2, y: 0))
        let center = VectorPoint(x: 0, y: 0)
        let rotated = line.rotated(around: center, by: .pi / 2)
        
        if case .line(let start, let end) = rotated {
            XCTAssertEqual(start.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(start.y, 1.0, accuracy: 1e-6)
            XCTAssertEqual(end.x, 0.0, accuracy: 1e-6)
            XCTAssertEqual(end.y, 2.0, accuracy: 1e-6)
        } else {
            XCTFail("Rotation failed")
        }
    }
    
    func testLineScaling() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let scaled = line.scaled(by: 2, about: VectorPoint(x: 0, y: 0))
        
        if case .line(_, let end) = scaled {
            XCTAssertEqual(end.x, 20.0, accuracy: 1e-9)
        } else {
            XCTFail("Scaling failed")
        }
    }
    
    // MARK: - Offset Tests
    
    func testLineOffsetPositive() {
        // Horizontal line y=0 from x=0..10; offset +5 should yield parallel line at y=5
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = VectorOffsetCalculator.offsetLine(line, by: 5.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertEqual(result?.offsetPath.count, 2)
        XCTAssertEqual(result?.offsetPath[0].y, 5.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[1].y, 5.0, accuracy: 1e-6)
    }
    
    func testCircleOffsetExpandsRadius() {
        let center = VectorPoint(x: 0, y: 0)
        let circle = VectorShape.circle(center: center, radius: 10.0)
        let result = VectorOffsetCalculator.offsetCircle(circle: circle, by: 5.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertFalse(result?.offsetPath.isEmpty ?? true)
        // All sample points should be at distance 15 from center
        if let pts = result?.offsetPath {
            for pt in pts {
                let d = hypot(pt.x - center.x, pt.y - center.y)
                XCTAssertEqual(d, 15.0, accuracy: 1e-5)
            }
        }
    }
    
    func testRectangleOffsetCorners() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let result = VectorOffsetCalculator.offsetRectangle(rect: rect, by: 2.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 2.0)
        XCTAssertEqual(result?.offsetPath.count, 5) // 4 corners + closing back to first
        // Expected expanded corner: (-2, -2)
        XCTAssertEqual(result?.offsetPath[0].x, -2.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[0].y, -2.0, accuracy: 1e-6)
    }
    
    func testArcOffsetPreservesSweepCount() {
        let arc = VectorShape.arc(center: VectorPoint(x: 0, y: 0), radius: 10.0, startAngle: 0, endAngle: .pi)
        let result = VectorOffsetCalculator.offsetArc(arc: arc, by: 1.0)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 1.0)
        XCTAssertFalse(result?.offsetPath.isEmpty ?? true)
    }
    
    // MARK: - Fillet / Extend Tests
    
    func testRectangleFilletReplacesWithLines() {
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 100)
        let result = FilletExtendEngine.fillet(shape: rect, cornerPoint: VectorPoint(x: 0, y: 0), radius: 10.0)
        
        XCTAssertFalse(result.isEmpty)
        XCTAssertGreaterThan(result.count, 1) // Filleted rectangle becomes multiple line segments
    }
    
    func testExtendLineToPoint() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = FilletExtendEngine.extendLine(line, to: VectorPoint(x: 20, y: 0))
        
        XCTAssertEqual(result.count, 1)
        if case .line(_, let e) = result[0] {
            XCTAssertEqual(e.x, 20.0, accuracy: 1e-9)
        } else {
            XCTFail("Extend failed")
        }
    }
    
    // MARK: - Array Copy Tests
    
    func testGridArrayProducesCorrectCount() {
        let line = VectorShape.line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0))
        let result = line.gridArray(columns: 2, rows: 2, spacingX: 20, spacingY: 20)
        
        XCTAssertEqual(result.copies.count, 4)
        XCTAssertEqual(result.layout, .grid)
    }
    
    func testCircularArrayProducesCorrectCount() {
        let circle = VectorShape.circle(center: VectorPoint(x: 0, y: 0), radius: 5)
        let result = circle.circularArray(count: 4, radius: 20)
        
        XCTAssertEqual(result.copies.count, 4)
        XCTAssertEqual(result.layout, .circular)
    }
    
    // MARK: - Boolean Sanity (API existence + basic equality)
    
    func testBooleanUnionNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.union([a, b])
        XCTAssertFalse(result.isEmpty, "Union of two rectangles should not be empty")
    }
    
    func testBooleanIntersectionNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.intersection([a, b])
        XCTAssertFalse(result.isEmpty, "Intersection of overlapping rectangles should not be empty")
    }
    
    func testBooleanDifferenceNonEmpty() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOperations.difference([a], [b])
        XCTAssertFalse(result.isEmpty, "Difference of overlapping rectangles should not be empty")
    }
}
