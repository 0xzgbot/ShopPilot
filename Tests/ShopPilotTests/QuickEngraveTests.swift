import XCTest
@testable import ShopPilotCore
@testable import ShopPilotGeometry

final class QuickEngraveEngineTests: XCTestCase {
    
    // MARK: - Basic Quick Engrave
    
    func testQuickEngraveProducesGCode() {
        let vector = VectorPath(
            id: UUID(),
            name: "test",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = QuickEngraveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            depthMm: 1.0
        )
        
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertTrue(result.gcodeLines.contains("O=QUICK_ENGRAVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1 Z") })
        XCTAssertEqual(result.passCount, 1)
    }
    
    func testQuickEngraveSinglePass() {
        let vector = VectorPath(
            id: UUID(),
            name: "test",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = QuickEngraveParams(depthMm: 2.0)
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        // Always exactly 1 pass
        XCTAssertEqual(result.passCount, 1)
        
        // All Z moves should be at -2.0 (single depth)
        let zLines = result.gcodeLines.filter { $0.contains("Z") && !$0.hasPrefix("(") }
        for line in zLines where line.contains("G1 Z") {
            XCTAssertTrue(line.contains("Z-2.000"), "Quick engrave should use constant depth, got: \(line)")
        }
    }
    
    func testQuickEngravePerVectorDepth() {
        let id1 = UUID()
        let id2 = UUID()
        
        let vector1 = VectorPath(
            id: id1, name: "deep",
            points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0)],
            isClosed: false, layerId: UUID()
        )
        
        let vector2 = VectorPath(
            id: id2, name: "shallow",
            points: [VectorPoint(x: 0, y: 50), VectorPoint(x: 50, y: 50)],
            isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams(
            depthMm: 1.0,
            vectorDepths: [id1: 2.0, id2: 0.5]
        )
        
        let result = QuickEngraveEngine.compute(vectors: [vector1, vector2], params: params)
        
        let gcode = result.gcodeLines.joined(separator: "\n")
        XCTAssertTrue(gcode.contains("Z-2.000"), "Should use vector-specific depth 2.0")
        XCTAssertTrue(gcode.contains("Z-0.500"), "Should use vector-specific depth 0.5")
    }
    
    // MARK: - Bounding Box
    
    func testBoundingBoxComputation() {
        let vector = VectorPath(
            id: UUID(), name: "test",
            points: [VectorPoint(x: 10, y: 20), VectorPoint(x: 100, y: 200)],
            isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertEqual(result.boundsMinX, 10.0)
        XCTAssertEqual(result.boundsMinY, 20.0)
        XCTAssertEqual(result.boundsMaxX, 100.0)
        XCTAssertEqual(result.boundsMaxY, 200.0)
    }
    
    func testEmptyVectorsNoBounds() {
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: [], params: params)
        
        XCTAssertNil(result.boundsMinX)
    }
    
    // MARK: - Time Estimate
    
    func testTimeEstimateCalculation() {
        let vector = VectorPath(
            id: UUID(), name: "test",
            points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0)],
            isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams(
            feedRateMmPerMin: 1000,
            depthMm: 1.0
        )
        
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        // 100mm at 1000mm/min = 0.1 min = 6 seconds
        XCTAssertGreaterThan(result.estimatedTimeSeconds, 0)
    }
    
    // MARK: - Safety Checks
    
    func testEmptyVectorSkipped() {
        let vector = VectorPath(
            id: UUID(), name: "empty",
            points: [], isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertTrue(result.gcodeLines.contains("O=QUICK_ENGRAVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        XCTAssertEqual(result.passCount, 1)
    }
    
    func testSinglePointVectorSkipped() {
        let vector = VectorPath(
            id: UUID(), name: "single",
            points: [VectorPoint(x: 0, y: 0)],
            isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertTrue(result.gcodeLines.contains("O=QUICK_ENGRAVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
    }
    
    // MARK: - Lead-In/Lead-Out
    
    func testLeadInLeadOut() {
        let vector = VectorPath(
            id: UUID(), name: "test",
            points: [VectorPoint(x: 50, y: 50), VectorPoint(x: 100, y: 50)],
            isClosed: false, layerId: UUID()
        )
        
        let params = QuickEngraveParams(
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )
        
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        let gcode = result.gcodeLines.joined(separator: "\n")
        
        XCTAssertTrue(gcode.contains("G0 X45.000"), "Lead-in should start 5mm before")
        // Lead-out is a cutting move (G1 at depth), not a rapid (G0).
        XCTAssertTrue(gcode.contains("G1 X105.000"), "Lead-out should end 5mm after")
    }
    
    // MARK: - Closed Vector Path
    
    func testClosedVectorPath() {
        let vector = VectorPath(
            id: UUID(), name: "square",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0),
                VectorPoint(x: 50, y: 50),
                VectorPoint(x: 0, y: 50),
                VectorPoint(x: 0, y: 0)
            ],
            isClosed: true, layerId: UUID()
        )
        
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertGreaterThan(result.gcodeLines.count, 5)
    }
    
    // MARK: - V-Bit Angle
    
    func testVBitAngleStored() {
        let params = QuickEngraveParams(vBitAngleDegrees: 45.0)
        XCTAssertEqual(params.vBitAngleDegrees, 45.0)
        XCTAssertEqual(params.halfAngleRadians, .pi / 8.0, accuracy: 1e-9)
    }
    
    // MARK: - Multiple Vectors
    
    func testMultipleVectors() {
        var vectors: [VectorPath] = []
        for i in 0..<5 {
            let startX = Double(i * 10)
            let endX = Double(i * 10 + 50)
            let points = [
                VectorPoint(x: startX, y: 0),
                VectorPoint(x: endX, y: 0)
            ]
            vectors.append(
                VectorPath(
                    id: UUID(),
                    name: "v\(i)",
                    points: points,
                    isClosed: false,
                    layerId: UUID()
                )
            )
        }
        
        let params = QuickEngraveParams()
        let result = QuickEngraveEngine.compute(vectors: vectors, params: params)
        
        XCTAssertGreaterThan(result.gcodeLines.count, 10)
        XCTAssertTrue(result.gcodeLines.contains("M30"))
    }
}
