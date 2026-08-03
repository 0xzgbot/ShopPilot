import XCTest
@testable import ShopPilotGeometry

/// Unit tests for the VectorOffsetCalculator — SPK-0203.
///
/// NOTE: `offsetShape` returns `[VectorShape]` (the offset geometry committed
/// to the session) and returns an empty array when the shape collapses.
final class VectorOffsetTests: XCTestCase {

    // MARK: - Helpers

    private func freehandPoints(_ shapes: [VectorShape]) -> [VectorPoint]? {
        guard shapes.count == 1, case .freehand(let pts) = shapes[0] else { return nil }
        return pts
    }

    // MARK: - Line offset

    func testLineOffsetPositive() {
        let line = VectorShape.line(
            start: VectorPoint(x: 0, y: 0),
            end: VectorPoint(x: 10, y: 0)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 5.0)
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        XCTAssertEqual(pts?.count, 2)
        // Left normal of (10, 0) is (0, 1), so points should be at y=5
        XCTAssertEqual(pts?[0].y ?? .nan, 5.0, accuracy: 1e-6)
        XCTAssertEqual(pts?[1].y ?? .nan, 5.0, accuracy: 1e-6)
    }

    func testLineOffsetNegative() {
        let line = VectorShape.line(
            start: VectorPoint(x: 0, y: 0),
            end: VectorPoint(x: 10, y: 0)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: -3.0)
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        // Left normal of (10, 0) is (0, 1), so negative distance gives y=-3
        XCTAssertEqual(pts?[0].y ?? .nan, -3.0, accuracy: 1e-6)
    }

    func testLineOffsetVertical() {
        let line = VectorShape.line(
            start: VectorPoint(x: 5, y: 0),
            end: VectorPoint(x: 5, y: 10)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 2.0)
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        // Left normal of (0, 10) is (-1, 0), so x should decrease by 2
        XCTAssertEqual(pts?[0].x ?? .nan, 3.0, accuracy: 1e-6)
    }

    func testLineOffsetDegenerate() {
        let line = VectorShape.line(
            start: VectorPoint(x: 5, y: 5),
            end: VectorPoint(x: 5, y: 5)
        )
        let result = VectorOffsetCalculator.offsetShape(line, by: 3.0)
        // Zero-length line collapses — documented contract returns empty array.
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Circle offset

    func testCircleOffsetExpand() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: 5.0)
        XCTAssertEqual(result.count, 1)
        guard case .circle(let center, let radius) = result[0] else {
            return XCTFail("expected circle, got \(result[0])")
        }
        XCTAssertEqual(center.x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(center.y, 0.0, accuracy: 1e-6)
        // Radius expanded to 15
        XCTAssertEqual(radius, 15.0, accuracy: 1e-6)
    }

    func testCircleOffsetContract() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: -3.0)
        XCTAssertEqual(result.count, 1)
        guard case .circle(_, let radius) = result[0] else {
            return XCTFail("expected circle, got \(result[0])")
        }
        // Radius contracted to 7
        XCTAssertEqual(radius, 7.0, accuracy: 1e-6)
    }

    func testCircleOffsetCollapse() {
        let circle = VectorShape.circle(
            center: VectorPoint(x: 0, y: 0),
            radius: 2.0
        )
        let result = VectorOffsetCalculator.offsetShape(circle, by: -5.0)
        // Collapses (radius <= 0) → empty array
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Rectangle offset

    func testRectangleOffsetExpand() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 20, height: 10
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: 5.0)
        XCTAssertEqual(result.count, 1)
        guard case .rectangle(let origin, let w, let h) = result[0] else {
            return XCTFail("expected rectangle, got \(result[0])")
        }
        // Expanded: minX=-5, minY=-5, width=30, height=20
        XCTAssertEqual(origin.x, -5.0, accuracy: 1e-6)
        XCTAssertEqual(origin.y, -5.0, accuracy: 1e-6)
        XCTAssertEqual(w, 30.0, accuracy: 1e-6)
        XCTAssertEqual(h, 20.0, accuracy: 1e-6)
    }

    func testRectangleOffsetContract() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 20, height: 10
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: -3.0)
        XCTAssertEqual(result.count, 1)
        guard case .rectangle(let origin, let w, let h) = result[0] else {
            return XCTFail("expected rectangle, got \(result[0])")
        }
        // Contracted: minX=3, minY=3, width=14, height=4
        XCTAssertEqual(origin.x, 3.0, accuracy: 1e-6)
        XCTAssertEqual(origin.y, 3.0, accuracy: 1e-6)
        XCTAssertEqual(w, 14.0, accuracy: 1e-6)
        XCTAssertEqual(h, 4.0, accuracy: 1e-6)
    }

    func testRectangleOffsetCollapse() {
        let rect = VectorShape.rectangle(
            origin: VectorPoint(x: 0, y: 0),
            width: 10, height: 5
        )
        let result = VectorOffsetCalculator.offsetShape(rect, by: -100.0)
        // Collapsed to empty
        XCTAssertTrue(result.isEmpty)
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
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        // Radius expanded to 13 → first sample at (13, 0)
        XCTAssertEqual(pts?[0].x ?? .nan, 13.0, accuracy: 1e-6)
    }

    func testArcOffsetContract() {
        let arc = VectorShape.arc(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            startAngle: 0,
            endAngle: .pi
        )
        let result = VectorOffsetCalculator.offsetShape(arc, by: -5.0)
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        // Radius contracted to 5 → first sample at (5, 0)
        XCTAssertEqual(pts?[0].x ?? .nan, 5.0, accuracy: 1e-6)
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
        XCTAssertEqual(result.count, 1)
        guard case .ellipse(_, let rx, let ry, _) = result[0] else {
            return XCTFail("expected ellipse, got \(result[0])")
        }
        // rx expanded to 25, ry to 15
        XCTAssertEqual(rx, 25.0, accuracy: 1e-6)
        XCTAssertEqual(ry, 15.0, accuracy: 1e-6)
    }

    func testEllipseOffsetContract() {
        let ellipse = VectorShape.ellipse(
            center: VectorPoint(x: 0, y: 0),
            radiusX: 20.0,
            radiusY: 10.0,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(ellipse, by: -5.0)
        XCTAssertEqual(result.count, 1)
        guard case .ellipse(_, let rx, let ry, _) = result[0] else {
            return XCTFail("expected ellipse, got \(result[0])")
        }
        // rx=15, ry=5
        XCTAssertEqual(rx, 15.0, accuracy: 1e-6)
        XCTAssertEqual(ry, 5.0, accuracy: 1e-6)
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
        XCTAssertEqual(result.count, 1)
        guard case .polygon(_, let radius, let sides, _) = result[0] else {
            return XCTFail("expected polygon, got \(result[0])")
        }
        XCTAssertEqual(radius, 15.0, accuracy: 1e-6)
        XCTAssertEqual(sides, 4)
    }

    func testPolygonOffsetContract() {
        let polygon = VectorShape.polygon(
            center: VectorPoint(x: 0, y: 0),
            radius: 10.0,
            sides: 4,
            rotation: 0
        )
        let result = VectorOffsetCalculator.offsetShape(polygon, by: -3.0)
        XCTAssertEqual(result.count, 1)
        guard case .polygon(_, let radius, _, _) = result[0] else {
            return XCTFail("expected polygon, got \(result[0])")
        }
        XCTAssertEqual(radius, 7.0, accuracy: 1e-6)
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
        XCTAssertEqual(result.count, 1)
        guard case .star(_, let outer, let inner, let pts, _) = result[0] else {
            return XCTFail("expected star, got \(result[0])")
        }
        // Outer expanded to 18, inner to 11
        XCTAssertEqual(outer, 18.0, accuracy: 1e-6)
        XCTAssertEqual(inner, 11.0, accuracy: 1e-6)
        XCTAssertEqual(pts, 5)
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
        XCTAssertEqual(result.count, 1)
        guard case .star(_, let outer, let inner, _, _) = result[0] else {
            return XCTFail("expected star, got \(result[0])")
        }
        // Outer contracted to 10, inner to 3
        XCTAssertEqual(outer, 10.0, accuracy: 1e-6)
        XCTAssertEqual(inner, 3.0, accuracy: 1e-6)
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
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        XCTAssertGreaterThan(pts?.count ?? 0, 0)
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
        let pts = freehandPoints(result)
        XCTAssertNotNil(pts)
        XCTAssertGreaterThan(pts?.count ?? 0, 0)
    }

    // MARK: - ProfileOffsetGenerator

    @MainActor
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

    @MainActor
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
        XCTAssertEqual(xs.min()!, -5.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max()!, 15.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min()!, -5.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max()!, 15.0, accuracy: 1e-6)
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
        XCTAssertEqual(xs.min()!, 3.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max()!, 7.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min()!, 3.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max()!, 7.0, accuracy: 1e-6)
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
        // Vertex count: 3 corners + explicit closing point.
        XCTAssertEqual(result?.offsetPath.count, 4)
        // Path should be closed
        XCTAssertEqual(result!.offsetPath.first!.x, result!.offsetPath.last!.x, accuracy: 1e-6)
        XCTAssertEqual(result!.offsetPath.first!.y, result!.offsetPath.last!.y, accuracy: 1e-6)
        // All points should be outside original bounds — the apex (5,0) is
        // pushed below the original bottom edge (y=0) by the offset.
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertLessThanOrEqual(xs.min()!, -2.0)
        XCTAssertLessThanOrEqual(ys.min()!, -2.0)
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
        // Vertex count: 6 corners + explicit closing point.
        XCTAssertEqual(result?.offsetPath.count, 7)
        // Bounds expanded outward by 3
        let xs = result!.offsetPath.map { $0.x }
        let ys = result!.offsetPath.map { $0.y }
        XCTAssertEqual(xs.min()!, -3.0, accuracy: 1e-6)
        XCTAssertEqual(xs.max()!, 13.0, accuracy: 1e-6)
        XCTAssertEqual(ys.min()!, -3.0, accuracy: 1e-6)
        XCTAssertEqual(ys.max()!, 13.0, accuracy: 1e-6)
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
        // Input without an explicit closing vertex is treated as closed:
        // output = 4 offset corners + explicit closing point.
        XCTAssertEqual(result?.offsetPath.count, 5)
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
        // Verify that offsetShape returns a non-empty result for every VectorShape case
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
            XCTAssertFalse(result.isEmpty, "offsetShape should return non-empty for \(shape)")
        }
    }
}
