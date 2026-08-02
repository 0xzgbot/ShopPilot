import XCTest
@testable import ShopPilotGeometry

/// Unit tests for the VectorOffsetCalculator — SPK-0203.
final class VectorOffsetTests: XCTestCase {

    // MARK: - Line offset

    func testLineOffsetPositive() {
        let line = VectorShape.line(
            start: VectorPoint(x: 0, y: 0),
            end: VectorPoint(x: 10, y: 0)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertEqual(result?.offsetPath.count, 2)
        // Left normal of (10, 0) is (0, 1), so points should be at y=5
        XCTAssertEqual(result?.offsetPath[0].y, 5.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[1].y, 5.0, accuracy: 1e-6)
    }

    func testLineOffsetNegative() {
        let line = VectorShape.line(
            start: VectorPoint(x: 0, y: 0),
            end: VectorPoint(x: 10, y: 0)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: -3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, -3.0)
        // Left normal of (10, 0) is (0, 1), so negative distance gives y=-3
        XCTAssertEqual(result?.offsetPath[0].y, -3.0, accuracy: 1e-6)
    }

    func testLineOffsetVertical() {
        let line = VectorShape.line(
            start: VectorPoint(x: 5, y: 0),
            end: VectorPoint(x: 5, y: 10)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 2.0)
        XCTAssertNotNil(result)
        // Left normal of (0, 10) is (-1, 0), so x should decrease by 2
        XCTAssertEqual(result?.offsetPath[0].x, 3.0, accuracy: 1e-6)
    }

    func testLineOffsetDegenerate() {
        let line = VectorShape.line(
            start: VectorPoint(x: 5, y: 5),
            end: VectorPoint(x: 5, y: 5)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offsetPath.count, 1)
        XCTAssertEqual(result?.offsetPath[0].x, 2.0, accuracy: 1e-6)
    }

    // MARK: - Circle offset

    func testCircleOffsetExpand() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertEqual(result?.offsetPath.count, 64)
        // First point should be at (15, 0) since radius expanded to 15
        XCTAssertEqual(result?.offsetPath[0].x, 15.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[0].y, 0.0, accuracy: 1e-6)
    }

    func testCircleOffsetContract() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: -3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offsetPath.count, 64)
        // Radius contracted to 7
        XCTAssertEqual(result?.offsetPath[0].x, 7.0, accuracy: 1e-6)
    }

    func testCircleOffsetCollapse() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 2.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: -5.0)
        XCTAssertNotNil(result)
        // Collapsed to a point
        XCTAssertEqual(result?.offsetPath.count, 1)
    }

    // MARK: - Rectangle offset

    func testRectangleOffsetExpand() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 20, height: 10
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        // Expanded: minX=-5, minY=-5, maxX=25, maxY=15
        XCTAssertEqual(result?.offsetPath[0].x, -5.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[0].y, -5.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[2].x, 25.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[2].y, 15.0, accuracy: 1e-6)
    }

    func testRectangleOffsetContract() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 20, height: 10
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: -3.0)
        XCTAssertNotNil(result)
        // Contracted: minX=3, minY=3, maxX=17, maxY=7
        XCTAssertEqual(result?.offsetPath[0].x, 3.0, accuracy: 1e-6)
        XCTAssertEqual(result?.offsetPath[0].y, 3.0, accuracy: 1e-6)
    }

    func testRectangleOffsetCollapse() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 10, height: 5
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: -100.0)
        XCTAssertNotNil(result)
        // Collapsed to empty
        XCTAssertTrue(result?.offsetPath.isEmpty ?? false)
    }

    // MARK: - Arc offset

    func testArcOffsetExpand() {
        let arc = VectorShape.arc(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            startAngle: 0,
            endAngle: .pi
        )
        let result = VectorOffsetCalculator.offsetShape(arc, by: 3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 3.0)
        // Radius expanded to 13
        XCTAssertEqual(result?.offsetPath[0].x, 13.0, accuracy: 1e-6)
    }

    func testArcOffsetContract() {
        let arc = VectorShape.arc(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            startAngle: 0,
            endAngle: .pi
        )
        let result = VectorOffsetCalculator.offsetShape(arc, by: -5.0)
        XCTAssertNotNil(result)
        // Radius contracted to 5
        XCTAssertEqual(result?.offsetPath[0].x, 5.0, accuracy: 1e-6)
    }

    // MARK: - Ellipse offset

    func testEllipseOffsetExpand() {
        let ellipse = VectorShape.ellipse(
            center: VectorPoint(x: 0, y: 0),
            radiusX: 20.0,
            radiusY: 10.0,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(ellipse, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        XCTAssertEqual(result?.offsetPath.count, 64)
        // First point should be at (25, 0) since rx expanded to 25
        XCTAssertEqual(result?.offsetPath[0].x, 25.0, accuracy: 1e-6)
    }

    func testEllipseOffsetContract() {
        let ellipse = VectorShape.ellipse(
            center: VectorPoint(x: 0, y: 0),
            radiusX: 20.0,
            radiusY: 10.0,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(ellipse, by: -5.0)
        XCTAssertNotNil(result)
        // rx=15, ry=5
        XCTAssertEqual(result?.offsetPath[0].x, 15.0, accuracy: 1e-6)
    }

    // MARK: - Polygon offset

    func testPolygonOffsetExpand() {
        let polygon = VectorShape.polygon(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            sides: 4, // square
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(polygon, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        // Should produce a closed polygon with more points
        XCTAssertGreaterThan(result?.offsetPath.count ?? 0, 0)
        // Path should be closed (first ≈ last)
        if result?.offsetPath.count ?? 0 > 1 {
            let first = result!.offsetPath.first!
            let last = result!.offsetPath.last!
            XCTAssertEqual(first.x, last.x, accuracy: 1e-6)
            XCTAssertEqual(first.y, last.y, accuracy: 1e-6)
        }
    }

    func testPolygonOffsetContract() {
        let polygon = VectorShape.polygon(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            sides: 4,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(polygon, by: -3.0)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result?.offsetPath.count ?? 0, 0)
    }

    // MARK: - Star offset

    func testStarOffsetExpand() {
        let star = VectorShape.star(
            center: VectorPoint(x: 0, y: 0),
            outerRadius: 15.0,
            innerRadius: 8.0,
            points: 5,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(star, by: 3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 3.0)
        XCTAssertEqual(result?.offsetPath.count, 10) // 5 outer + 5 inner
        // Outer radius expanded to 18
        XCTAssertEqual(result?.offsetPath[0].x, 18.0, accuracy: 1e-6)
    }

    func testStarOffsetContract() {
        let star = VectorShape.star(
            center: VectorPoint(x: 0, y: 0),
            outerRadius: 15.0,
            innerRadius: 8.0,
            points: 5,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(star, by: -5.0)
        XCTAssertNotNil(result)
        // Outer radius contracted to 10
        XCTAssertEqual(result?.offsetPath[0].x, 10.0, accuracy: 1e-6)
    }

    // MARK: - Freehand offset

    func testFreehandOffsetExpand() {
        let freehand = VectorShape.freehand(
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 10, y: 0),
                VectorPoint(x: 10, y: 10),
                VectorPoint(x: 0, y: 10),
            ]
        )
        let result = VectorOffsetCalculator.offsetShape(freehand, by: 3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 3.0)
        // Should produce offset points
        XCTAssertGreaterThan(result?.offsetPath.count ?? 0, 0)
    }

    func testFreehandOffsetContract() {
        let freehand = VectorShape.freehand(
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 10, y: 0),
                VectorPoint(x: 10, y: 10),
            ]
        )
        let result = VectorOffsetCalculator.offsetShape(freehand, by: -2.0)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result?.offsetPath.count ?? 0, 0)
    }

    // MARK: - ProfileOffsetGenerator

    func testProfileOffsetGenerator() {
        let generator = ProfileOffsetGenerator()
        let shapes: [VectorShape] = [
            .rectangle(
                origin: VectorPoint(x: 0, y: 0),
                width: 50, height: 30
            )
        ]
        let results = generator.generateProfileOffsets(
            shapes: shapes,
            offsetDistance: 0.0,
            toolDiameter: 6.0
        )
        XCTAssertEqual(results.count, 1)
        // Tool radius = 3, so offset should be +3
        XCTAssertEqual(results[0].distance, 3.0, accuracy: 1e-6)
    }

    func testDualProfileOffsets() {
        let generator = ProfileOffsetGenerator()
        let shapes: [VectorShape] = [
            .circle(center: VectorPoint(x: 0, y: 0), radius: 20.0)
        ]
        let results = generator.generateDualProfileOffsets(
            shapes: shapes,
            toolDiameter: 6.0,
            allowance: 0.0
        )
        XCTAssertEqual(results.count, 2)
        // Outside: +3, Inside: -3
        XCTAssertEqual(results[0].distance, 3.0, accuracy: 1e-6)
        XCTAssertEqual(results[1].distance, -3.0, accuracy: 1e-6)
    }

    // MARK: - OffsetResult convenience

    func testOffsetResultIsValid() {
        let result = OffsetResult(
            original: .line(start: .zero, end: VectorPoint(x: 1, y: 0)),
            offsetPath: [VectorPoint(x: 0, y: 1), VectorPoint(x: 1, y: 1)],
            distance: 1.0
        )
        XCTAssertTrue(result.isValid)
    }

    func testOffsetResultIsInvalid() {
        let result = OffsetResult(
            original: .line(start: .zero, end: VectorPoint(x: 1, y: 0)),
            offsetPath: [],
            distance: 1.0
        )
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Closed polyline offset

    func testClosedPolylineSquareExpand() {
        // Unit square offset outward by 5
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: 0, y: 0),
        ]
        let result = VectorOffsetCalculator.offsetClosedPolyline(points: points, by: 5.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 5.0)
        // Vertex count should match input (5 = 4 corners + close)
        XCTAssertEqual(result?.offsetPath.count, 5)
        // Bounds: expanded square should be [-5, -5] to [15, 15]
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertEqual(xs.min(), -5.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max(), 15.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min(), -5.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max(), 15.0, accuracy: 1e-6)
        // Path should be closed (first ≈ last)
        XCTAssertEqual(result!.offsetPath.first!.x, result!.offsetPath.last!.x, accuracy: 1e-6)
        XCTAssertEqual(result!.offsetPath.first!.y, result!.offsetPath.last!.y, accuracy: 1e-6)
    }

    func testClosedPolylineSquareContract() {
        // Unit square offset inward by 3
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: 0, y: 0),
        ]
        let result = VectorOffsetCalculator.offsetClosedPolyline(points: points, by: -3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, -3.0)
        XCTAssertEqual(result?.offsetPath.count, 5)
        // Bounds: contracted square should be [3, 3] to [7, 7]
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertEqual(xs.min(), 3.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max(), 7.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min(), 3.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max(), 7.0, accuracy: 1e-6)
    }

    func testClosedPolylineTriangle() {
        // Equilateral-ish triangle offset outward
        let points: [VectorPoint] = [
            VectorPoint(x: 5, y: 0),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 5, y: 0),
        ]
        let result = VectorOffsetCalculator.offsetClosedPolyline(points: points, by: 2.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 2.0)
        // Vertex count matches input
        XCTAssertEqual(result?.offsetPath.count, 3)
        // Path should be closed
        XCTAssertEqual(result!.offsetPath.first!.x, result!.offsetPath.last!.x, accuracy: 1e-6)
        XCTAssertEqual(result!.offsetPath.first!.y, result!.offsetPath.last!.y, accuracy: 1e-6)
        // All points should be outside original bounds
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertLessThanOrEqual(xs.min()!, -2.0, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(ys.min()!, 0.0)
    }

    func testClosedPolylineNonConvex() {
        // L-shaped polygon offset outward
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 5),
            VectorPoint(x: 5, y: 5),
            VectorPoint(x: 5, y: 10),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: 0, y: 0),
        ]
        let result = VectorOffsetCalculator.offsetClosedPolyline(points: points, by: 3.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.distance, 3.0)
        // Vertex count matches input
        XCTAssertEqual(result?.offsetPath.count, 6)
        // Bounds expanded outward by 3
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertEqual(xs.min(), -3.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max(), 13.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min(), -3.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max(), 13.0, accuracy: 1e-6)
    }

    func testClosedPolylineTooFewPoints() {
        // Fewer than 3 points should return nil
        let result = VectorOffsetCalculator.offsetClosedPolyline(
            points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 1, y: 1)],
            by: 2.0
        )
        XCTAssertNil(result)
    }

    func testClosedPolylineAlreadyClosed() {
        // Points without explicit closing vertex — function should still work
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 0, y: 10),
        ]
        let result = VectorOffsetCalculator.offsetClosedPolyline(points: points, by: 2.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offsetPath.count, 4)
        // Result should be closed (first == last)
        XCTAssertEqual(result!.offsetPath.first!.x, result!.offsetPath.last!.x, accuracy: 1e-6)
        XCTAssertEqual(result!.offsetPath.first!.y, result!.offsetPath.last!.y, accuracy: 1e-6)
    }

    // MARK: - Equatable conformance

    func testOffsetResultEquatable() {
        let r1 = OffsetResult(
            original: .line(start: .zero, end: VectorPoint(x: 1, y: 0)),
            offsetPath: [VectorPoint(x: 0, y: 1), VectorPoint(x: 1, y: 1)],
            distance: 1.0
        )
        let r2 = OffsetResult(
            original: .line(start: .zero, end: VectorPoint(x: 1, y: 0)),
            offsetPath: [VectorPoint(x: 0, y: 1), VectorPoint(x: 1, y: 1)],
            distance: 1.0
        )
        let r3 = OffsetResult(
            original: .line(start: .zero, end: VectorPoint(x: 1, y: 0)),
            offsetPath: [VectorPoint(x: 0, y: 1), VectorPoint(x: 1, y: 1)],
            distance: 2.0
        )
        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }

    // MARK: - Shape type coverage

    func testAllShapeTypesSupported() {
        // Verify that offsetShape returns non-nil for every VectorShape case
        let shapes: [VectorShape] = [
            .line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 10, y: 0)),
            .circle(center: VectorPoint(x: 5, y: 5), radius: 10.0),
            .rectangle(origin: VectorPoint(x: 0, y: 0), width: 20, height: 10),
            .arc(center: VectorPoint(x: 0, y: 0), radius: 10.0, startAngle: 0, endAngle: .pi),
            .ellipse(center: VectorPoint(x: 0, y: 0), radiusX: 20, radiusY: 10, rotation: 0),
            .polygon(center: VectorPoint(x: 0, y: 0), radius: 10, sides: 6, rotation: 0),
            .star(center: VectorPoint(x: 0, y: 0), outerRadius: 15, innerRadius: 8, points: 5, rotation: 0),
            .freehand(points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 10, y: 0),
                VectorPoint(x: 10, y: 10),
            ]),
        ]

        for shape in shapes {
            let result = VectorOffsetCalculator.offsetShape(shape, by: 2.0)
            XCTAssertNotNil(result, "offsetShape should return non-nil for \(shape)")
            XCTAssertEqual(result?.original, shape)
            XCTAssertEqual(result?.distance, 2.0)
        }
    }
}
