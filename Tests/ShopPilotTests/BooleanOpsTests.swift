import XCTest
@testable import ShopPilotGeometry

/// Unit tests for BooleanOps — SPK-0204a.
final class BooleanOpsTests: XCTestCase {

    // MARK: - No overlap: subject unchanged

    func testSubtractNoOverlap() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 20, y: 20), width: 5, height: 5)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 1)
        XCTAssertEqual(result.polygons[0], a)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Full overlap: empty result

    func testSubtractFullOverlap() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: -5, y: -5), width: 20, height: 20)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.polygons.isEmpty)
    }

    // MARK: - B completely inside A: 4 rectangles

    func testSubtractBInsideA() {
        // A: 0,0 to 10,10
        // B: 3,3 to 7,7 — fully inside
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 3, y: 3), width: 4, height: 4)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 4)

        // Verify each remaining rect is valid and non-empty
        for poly in result.polygons {
            switch poly {
            case .rectangle(let o, let w, let h):
                XCTAssertTrue(w > 1e-9 && h > 1e-9, "Remaining rect should have positive area")
            default:
                XCTFail("Result should be rectangles")
            }
        }

        // Sum of areas should equal A.area - B.area
        let totalArea = result.polygons.reduce(0.0) { $0 + $1.area }
        XCTAssertEqual(totalArea, a.area - b.area, accuracy: 1e-6)
    }

    // MARK: - Partial overlap: 3 rectangles (B covers full left edge)

    func testSubtractBStripsLeftEdge() {
        // A: 0,0 to 10,10
        // B: 0,2 to 5,8 — covers full left strip partially
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 2), width: 5, height: 6)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 3)

        // Areas should add up
        let totalArea = result.polygons.reduce(0.0) { $0 + $1.area }
        XCTAssertEqual(totalArea, a.area - b.area, accuracy: 1e-6)
    }

    // MARK: - Partial overlap: 2 rectangles (B covers full top edge)

    func testSubtractBStripsTopEdge() {
        // A: 0,0 to 10,10
        // B: 2,8 to 8,12 — overlaps only the top-middle strip of A (2×6 region)
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 2, y: 8), width: 6, height: 4)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        // Decomposition: left strip, right strip, bottom strip (B's extension
        // above A's top edge removes nothing more).
        XCTAssertEqual(result.polygons.count, 3)

        // B only removes its overlap with A: 6 wide × 2 tall = 12 mm²
        let totalArea = result.polygons.reduce(0.0) { $0 + $1.area }
        XCTAssertEqual(totalArea, a.area - 12.0, accuracy: 1e-6)
    }

    // MARK: - Partial overlap: 1 rectangle (B covers full left and right strips)

    func testSubtractBStripsBothSides() {
        // A: 0,0 to 10,10
        // B: 0,3 to 3,7 and B: 7,3 to 10,7 — two separate B rects would be needed,
        // but we only have one B. Let's use a B that covers full top and bottom strips.
        // Actually with one B rect, we can cover full left strip:
        // B: 0,0 to 3,10 — covers full left edge
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 3, height: 10)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 1)

        // The remaining rect should be 7 wide
        switch result.polygons[0] {
        case .rectangle(let o, let w, let h):
            XCTAssertEqual(w, 7.0, accuracy: 1e-6)
            XCTAssertEqual(h, 10.0, accuracy: 1e-6)
        default:
            XCTFail("Expected rectangle")
        }
    }

    // MARK: - B covers full A: empty

    func testSubtractBEqualsA() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Negative width/height rectangles

    func testSubtractNegativeWidthRect() {
        // A: 10,0 to 0,10 (negative width)
        // B: 5,0 to 15,10 (overlaps right half)
        let a = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 0), width: -10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 5, y: 0), width: 10, height: 10)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        // Should produce one remaining rect on the left
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Touching edges (no overlap)

    func testSubtractTouchingEdges() {
        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 10, y: 0), width: 5, height: 5)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 1)
        XCTAssertEqual(result.polygons[0], a)
    }

    // MARK: - Golden test: specific overlap with known output

    func testSubtractGolden() {
        // A: 0,0 to 100,100
        // B: 30,20 to 70,80
        // Expected: 4 rectangles
        // Left strip:   0,0 to 30,100  (30x100 = 3000)
        // Right strip:  70,0 to 100,100 (30x100 = 3000)
        // Bottom strip: 30,0 to 70,20   (40x20 = 800)
        // Top strip:    30,80 to 70,100 (40x20 = 800)
        // Total remaining: 7600 = 10000 - 40*60 = 10000 - 2400

        let a = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 100, height: 100)
        let b = VectorShape.rectangle(origin: VectorPoint(x: 30, y: 20), width: 40, height: 60)
        let result = BooleanOps.subtract(a, b)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertEqual(result.polygons.count, 4)

        // Verify areas
        let totalArea = result.polygons.reduce(0.0) { $0 + $1.area }
        XCTAssertEqual(totalArea, 7600.0, accuracy: 1e-6)

        // Verify each polygon is a valid rectangle
        for poly in result.polygons {
            switch poly {
            case .rectangle(let o, let w, let h):
                XCTAssertTrue(w > 1e-9 && h > 1e-9)
            default:
                XCTFail("All results should be rectangles")
            }
        }

        // Check that the result is valid: no polygon overlaps with B
        for poly in result.polygons {
            switch poly {
            case .rectangle(let o, let w, let h):
                let pMinX = min(o.x, o.x + w)
                let pMaxX = max(o.x, o.x + w)
                let pMinY = min(o.y, o.y + h)
                let pMaxY = max(o.y, o.y + h)
                // Should not overlap with B's interior
                let bMinX = 30.0, bMaxX = 70.0
                let bMinY = 20.0, bMaxY = 80.0
                XCTAssertFalse(
                    pMinX < bMaxX && pMaxX > bMinX && pMinY < bMaxY && pMaxY > bMinY,
                    "Result polygon should not overlap with subtracted rectangle"
                )
            default:
                XCTFail("Expected rectangle")
            }
        }
    }

    // MARK: - Non-rectangle input returns empty

    func testSubtractNonRectangle() {
        let circle = VectorShape.circle(center: VectorPoint(x: 0, y: 0), radius: 5)
        let rect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 3, height: 3)
        let result = BooleanOps.subtract(circle, rect)
        XCTAssertEqual(result.operation, .subtract)
        XCTAssertTrue(result.isEmpty)
    }
}
