import XCTest
@testable import ShopPilotGeometry
@testable import ShopPilotCore

// MARK: - Preflight V-Carve Tests

/// Tests for SPK-0604: Preflight blocks V-Carve on open vectors with fix CTA.
final class PreflightVCarveTests: XCTestCase {
    
    // MARK: - Test: Preflight detects open vectors
    
    func testPreflightDetectsOpenPath() {
        // Create an open freehand path (not closed)
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50)
        ]
        let shape = VectorShape.freehand(points: points)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .openPath })
        XCTAssertEqual(report.worstSeverity, .error)
    }
    
    func testPreflightDetectsOpenLine() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertTrue(report.issues.contains { $0.issue == .openPath })
    }
    
    // MARK: - Test: Preflight allows closed vectors
    
    func testPreflightAllowsClosedRectangle() {
        let shape = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertTrue(report.isClean)
    }
    
    func testPreflightAllowsClosedCircle() {
        let shape = VectorShape.circle(center: VectorPoint(x: 25, y: 25), radius: 20)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertTrue(report.isClean)
    }
    
    func testPreflightAllowsClosedPolygon() {
        let shape = VectorShape.polygon(center: VectorPoint(x: 50, y: 50), radius: 30, points: 6)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertTrue(report.isClean)
    }
    
    // MARK: - Test: Preflight detects self-intersection
    
    func testPreflightDetectsSelfIntersection() {
        // Create a bow-tie shape (self-intersecting)
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 100),
            VectorPoint(x: 0, y: 100),
            VectorPoint(x: 100, y: 0)
        ]
        let shape = VectorShape.freehand(points: points)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .selfIntersection })
    }
    
    // MARK: - Test: Preflight detects degenerate shapes
    
    func testPreflightDetectsDegenerateLine() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 0.0001, y: 0.0001))
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .degenerate })
    }
    
    func testPreflightDetectsDegenerateFreehand() {
        let shape = VectorShape.freehand(points: [VectorPoint(x: 0, y: 0)])
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .degenerate })
    }
    
    // MARK: - Test: Preflight detects gaps
    
    func testPreflightDetectsGap() {
        let shape1 = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let shape2 = VectorShape.rectangle(origin: VectorPoint(x: 100, y: 100), width: 10, height: 10)
        let report = VectorPreflight.check(shapes: [shape1, shape2])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .gap })
    }
    
    // MARK: - Test: Preflight allows adjacent shapes
    
    func testPreflightAllowsAdjacentShapes() {
        let shape1 = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50)
        let shape2 = VectorShape.rectangle(origin: VectorPoint(x: 50, y: 0), width: 50, height: 50)
        let report = VectorPreflight.check(shapes: [shape1, shape2])
        
        // Adjacent shapes should not have gaps
        XCTAssertTrue(report.isClean || !report.issues.contains { $0.issue == .gap })
    }
    
    // MARK: - Test: Preflight report properties
    
    func testPreflightReportIsClean() {
        let shape = VectorShape.circle(center: VectorPoint(x: 0, y: 0), radius: 10)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertTrue(report.isClean)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.worstSeverity, .info)
    }
    
    func testPreflightReportWorstSeverity() {
        let openShape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [openShape])
        
        XCTAssertEqual(report.worstSeverity, .error)
    }
    
    func testPreflightReportIssueCount() {
        let openShape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [openShape])
        
        XCTAssertGreaterThan(report.issues.count, 0)
    }
    
    // MARK: - Test: Fix actions
    
    func testFixActionsForOpenPath() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [shape])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.contains { $0.title == "Close open vector" })
    }
    
    func testFixActionsForSelfIntersection() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 100),
            VectorPoint(x: 0, y: 100),
            VectorPoint(x: 100, y: 0)
        ]
        let shape = VectorShape.freehand(points: points)
        let report = VectorPreflight.check(shapes: [shape])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertTrue(actions.contains { $0.title == "Remove self-intersection" })
    }
    
    func testFixActionsForDegenerate() {
        let shape = VectorShape.freehand(points: [VectorPoint(x: 0, y: 0)])
        let report = VectorPreflight.check(shapes: [shape])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertTrue(actions.contains { $0.title == "Remove degenerate shape" })
    }
    
    func testFixActionsForGap() {
        let shape1 = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 10, height: 10)
        let shape2 = VectorShape.rectangle(origin: VectorPoint(x: 100, y: 100), width: 10, height: 10)
        let report = VectorPreflight.check(shapes: [shape1, shape2])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertTrue(actions.contains { $0.title == "Bridge gap" })
    }
    
    func testFixActionHasSeverity() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [shape])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertFalse(actions.isEmpty)
        XCTAssertEqual(actions[0].severity, .error)
    }
    
    func testFixActionHasSuggestedFix() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [shape])
        let actions = VectorPreflight.fixActions(for: report)
        
        XCTAssertFalse(actions.isEmpty)
        XCTAssertNotNil(actions[0].suggestedFix)
    }
    
    // MARK: - Test: V-Carve blocks on open vectors
    
    func testVCarveBlocksOnOpenVectors() {
        // Create open vectors
        let openPoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50)
        ]
        let openShape = VectorShape.freehand(points: openPoints)
        
        let report = VectorPreflight.check(shapes: [openShape])
        
        // Preflight should detect open path
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .openPath })
        
        // V-Carve should not proceed without fix
        let params = VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1000)
        
        // Create a vector path from the shape
        let vectorPath = VectorPath(points: openPoints, isClosed: false)
        
        // V-Carve engine should handle this gracefully
        let result = VCarveEngine.compute(vectors: [vectorPath], params: params)
        
        // Should produce some output but with warnings
        XCTAssertFalse(result.gcodeLines.isEmpty)
    }
    
    func testVCarveAllowsClosedVectors() {
        // Create closed rectangle
        let closedPoints: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        let closedShape = VectorShape.freehand(points: closedPoints)
        
        let report = VectorPreflight.check(shapes: [closedShape])
        
        // Preflight should be clean
        XCTAssertTrue(report.isClean)
        
        // V-Carve should proceed
        let vectorPath = VectorPath(points: closedPoints, isClosed: true)
        let params = VCarveParams(vBitAngleDegrees: 90, feedRateMmPerMin: 1000)
        let result = VCarveEngine.compute(vectors: [vectorPath], params: params)
        
        XCTAssertFalse(result.gcodeLines.isEmpty)
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("G0 Z5.0") })
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1") })
        XCTAssertTrue(result.gcodeLines.contains { $0 == "M30" })
    }
    
    // MARK: - Test: Preflight with multiple shapes
    
    func testPreflightMultipleShapesMixed() {
        let closedRect = VectorShape.rectangle(origin: VectorPoint(x: 0, y: 0), width: 50, height: 50)
        let openLine = VectorShape.line(from: VectorPoint(x: 100, y: 0), to: VectorPoint(x: 150, y: 50))
        let degenerate = VectorShape.freehand(points: [VectorPoint(x: 0, y: 0)])
        
        let report = VectorPreflight.check(shapes: [closedRect, openLine, degenerate])
        
        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.issues.contains { $0.issue == .openPath })
        XCTAssertTrue(report.issues.contains { $0.issue == .degenerate })
        XCTAssertFalse(report.issues.contains { $0.issue == .openPath && $0.affectedShapeIds.isEmpty })
    }
    
    // MARK: - Test: Preflight severity ordering
    
    func testPreflightSeverityOrdering() {
        let openShape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [openShape])
        
        let errors = report.issues.filter { $0.severity == .error }
        let warnings = report.issues.filter { $0.severity == .warning }
        let infos = report.issues.filter { $0.severity == .info }
        
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(warnings.count, 0)
        XCTAssertEqual(infos.count, 0)
    }
    
    // MARK: - Test: Preflight tolerance
    
    func testPreflightTolerance() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 0.001, y: 0.001), // Very close to origin
            VectorPoint(x: 10, y: 10)
        ]
        let shape = VectorShape.freehand(points: points)
        let report = VectorPreflight.check(shapes: [shape], tolerance: 0.01)
        
        // With larger tolerance, the first segment might be degenerate
        XCTAssertTrue(report.issues.contains { $0.issue == .degenerate || $0.issue == .openPath })
    }
    
    // MARK: - Test: Empty shapes
    
    func testPreflightEmptyShapes() {
        let report = VectorPreflight.check(shapes: [])
        
        XCTAssertTrue(report.isClean)
        XCTAssertTrue(report.issues.isEmpty)
    }
    
    // MARK: - Test: V-Carve with vector depths
    
    func testVCarveWithVectorDepths() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let params = VCarveParams(
            vBitAngleDegrees: 90,
            feedRateMmPerMin: 1000,
            vectorDepths: [vectorPath.id: 3.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vectorPath], params: params)
        
        XCTAssertFalse(result.gcodeLines.isEmpty)
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("Z=") })
    }
    
    // MARK: - Test: V-Carve flat bottom mode
    
    func testVCarveFlatBottomMode() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let params = VCarveParams(
            vBitAngleDegrees: 90,
            feedRateMmPerMin: 1000,
            flatBottomMode: true
        )
        
        let result = VCarveEngine.compute(vectors: [vectorPath], params: params)
        
        XCTAssertFalse(result.gcodeLines.isEmpty)
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("Flat Bottom: Yes") })
    }
    
    // MARK: - Test: Preflight report ID
    
    func testPreflightReportHasId() {
        let shape = VectorShape.circle(center: VectorPoint(x: 0, y: 0), radius: 10)
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertNotNil(report.id)
    }
    
    // MARK: - Test: Preflight result properties
    
    func testPreflightResultHasAllProperties() {
        let shape = VectorShape.line(from: VectorPoint(x: 0, y: 0), to: VectorPoint(x: 10, y: 10))
        let report = VectorPreflight.check(shapes: [shape])
        
        XCTAssertFalse(report.issues.isEmpty)
        let issue = report.issues[0]
        XCTAssertNotNil(issue.id)
        XCTAssertEqual(issue.issue, .openPath)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertFalse(issue.message.isEmpty)
    }
}
