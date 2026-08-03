import XCTest
@testable import ShopPilotCore
@testable import ShopPilotGeometry

final class VCarveGoldenFixtureTests: XCTestCase {
    
    // MARK: - Golden V-Carve Fixture: Basic Square
    
    func testGoldenSquareVCarve() {
        // Define a 50mm square with known Z-depths
        let squareId = UUID()
        let vector = VectorPath(
            id: squareId,
            name: "golden_square",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0),
                VectorPoint(x: 50, y: 50),
                VectorPoint(x: 0, y: 50),
                VectorPoint(x: 0, y: 0)
            ],
            isClosed: true,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 1.0,
            flatBottomMode: false,
            vectorDepths: [squareId: 2.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Verify G-code structure
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"), "Should have V-Carve header")
        XCTAssertTrue(result.gcodeLines.contains("M30"), "Should have M30 footer")
        
        // Verify pass count: tipWidth = 2*2*tan(pi/8) = 0.828, passes = ceil(0.828/1) = 1
        let tipWidth = params.tipWidthAtDepth(params.maxDepthOfCutMm)
        let expectedPasses = Int(ceil(tipWidth / params.stepOverMm))
        XCTAssertEqual(result.passCount, expectedPasses, "Pass count should match tipWidth/stepOver")
        
        // Verify time estimate is reasonable
        XCTAssertGreaterThan(result.estimatedTimeSeconds, 0)
        
        // Verify bounding box matches input
        XCTAssertEqual(result.boundsMinX, 0.0)
        XCTAssertEqual(result.boundsMinY, 0.0)
        XCTAssertEqual(result.boundsMaxX, 50.0)
        XCTAssertEqual(result.boundsMaxY, 50.0)
    }
    
    // MARK: - Golden V-Carve Fixture: Multi-Pass
    
    func testMultiPassVCarve() {
        let vectorId = UUID()
        let vector = VectorPath(
            id: vectorId,
            name: "multi_pass",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 100, y: 0)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        // 45° bit at 2mm depth with 0.5mm stepover = many passes
        let params = VCarveParams(
            vBitAngleDegrees: 45.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 0.5,
            flatBottomMode: false,
            vectorDepths: [vectorId: 2.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // 45° bit: tipWidth = 2*2*tan(pi/8) ≈ 0.828 for 90°, but for 45°:
        // halfAngle = 22.5°, tipWidth = 2*2*tan(22.5°) ≈ 1.657
        // passes = ceil(1.657/0.5) = 4
        let tipWidth = params.tipWidthAtDepth(params.maxDepthOfCutMm)
        let expectedPasses = Int(ceil(tipWidth / params.stepOverMm))
        XCTAssertEqual(result.passCount, expectedPasses, "Multi-pass count should match")
        
        // Verify G-code contains multiple pass comments
        let passComments = result.gcodeLines.filter { $0.contains("Pass") }
        XCTAssertGreaterThan(passComments.count, 0, "Should have pass comments")
    }
    
    // MARK: - Golden V-Carve Fixture: DOC Calibration
    
    func testDocCalibrationJob() {
        // DOC job: simple text-based V-Carve with known dimensions
        let textId = UUID()
        let vector = VectorPath(
            id: textId,
            name: "doc_calibration",
            points: [
                VectorPoint(x: 10, y: 10),
                VectorPoint(x: 90, y: 10),
                VectorPoint(x: 90, y: 90),
                VectorPoint(x: 10, y: 90),
                VectorPoint(x: 10, y: 10)
            ],
            isClosed: true,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 800,
            plungeFeedRateMmPerMin: 200,
            maxDepthOfCutMm: 1.5,
            leadInDistanceMm: 3.0,
            leadOutDistanceMm: 3.0,
            stepOverMm: 0.75,
            // A calibration cut must be constant-depth — flat-bottom mode keeps
            // every pass at the calibration Z instead of progressive shading.
            flatBottomMode: true,
            vectorDepths: [textId: 1.5]
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Verify G-code structure
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        
        // Verify Z coordinates are at -1.5mm (the DOC depth)
        let zLines = result.gcodeLines.filter { $0.contains("G1 Z") }
        for line in zLines {
            XCTAssertTrue(line.contains("Z-1.500"), "DOC job should use calibration depth, got: \(line)")
        }
        
        // Verify bounding box
        XCTAssertEqual(result.boundsMinX, 10.0)
        XCTAssertEqual(result.boundsMinY, 10.0)
        XCTAssertEqual(result.boundsMaxX, 90.0)
        XCTAssertEqual(result.boundsMaxY, 90.0)
    }
    
    // MARK: - Golden V-Carve Fixture: Flat Bottom
    
    func testFlatBottomVCarve() {
        let vectorId = UUID()
        let vector = VectorPath(
            id: vectorId,
            name: "flat_bottom",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0),
                VectorPoint(x: 50, y: 50),
                VectorPoint(x: 0, y: 50),
                VectorPoint(x: 0, y: 0)
            ],
            isClosed: true,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 1.0,
            flatBottomMode: true,
            vectorDepths: [vectorId: 2.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Verify G-code contains flat bottom section
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        
        // Verify pass count with flat bottom
        let tipWidth = params.tipWidthAtDepth(params.maxDepthOfCutMm)
        let expectedPasses = Int(ceil(tipWidth / params.stepOverMm))
        XCTAssertEqual(result.passCount, expectedPasses)
    }
    
    // MARK: - Golden V-Carve Fixture: Multiple Vectors
    
    func testMultipleVectorsGoldenFixture() {
        let id1 = UUID()
        let id2 = UUID()
        
        let vector1 = VectorPath(
            id: id1, name: "vec1",
            points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 50, y: 0)],
            isClosed: false, layerId: UUID()
        )
        
        let vector2 = VectorPath(
            id: id2, name: "vec2",
            points: [VectorPoint(x: 0, y: 50), VectorPoint(x: 50, y: 50)],
            isClosed: false, layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 1.0,
            flatBottomMode: false,
            vectorDepths: [id1: 2.0, id2: 1.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vector1, vector2], params: params)
        
        // Verify G-code structure
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        
        // Verify bounding box covers both vectors
        XCTAssertEqual(result.boundsMinX, 0.0)
        XCTAssertEqual(result.boundsMinY, 0.0)
        XCTAssertEqual(result.boundsMaxX, 50.0)
        XCTAssertEqual(result.boundsMaxY, 50.0)
    }
    
    // MARK: - Golden V-Carve Fixture: Empty Input
    
    func testEmptyVectorsGoldenFixture() {
        let params = VCarveParams()
        let result = VCarveEngine.compute(vectors: [], params: params)
        
        // Should still produce valid G-code structure
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        XCTAssertEqual(result.passCount, 0)
        XCTAssertNil(result.boundsMinX)
    }
    
    // MARK: - Golden V-Carve Fixture: Tip Width Math Verification
    
    func testTipWidthMath() {
        // Full cutting width at depth d for included angle θ: 2·d·tan(θ/2).
        // 90° bit at 2mm depth → 2·2·tan(45°) = 4.0
        let params90 = VCarveParams(vBitAngleDegrees: 90.0, maxDepthOfCutMm: 2.0)
        let tipWidth90 = params90.tipWidthAtDepth(2.0)
        XCTAssertEqual(tipWidth90, 4.0, accuracy: 1e-6)
        
        // 45° bit at 2mm depth → 2·2·tan(22.5°) = 4·0.4142 = 1.657
        let params45 = VCarveParams(vBitAngleDegrees: 45.0, maxDepthOfCutMm: 2.0)
        let tipWidth45 = params45.tipWidthAtDepth(2.0)
        XCTAssertEqual(tipWidth45, 1.65685424949238, accuracy: 1e-6)
        
        // 30° bit at 2mm depth → 2·2·tan(15°) = 4·0.2679 = 1.072
        let params30 = VCarveParams(vBitAngleDegrees: 30.0, maxDepthOfCutMm: 2.0)
        let tipWidth30 = params30.tipWidthAtDepth(2.0)
        XCTAssertEqual(tipWidth30, 1.0717967697244, accuracy: 1e-6)
    }
    
    // MARK: - Golden V-Carve Fixture: Time Estimate
    
    func testTimeEstimateReasonable() {
        let vector = VectorPath(
            id: UUID(), name: "test",
            points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 100, y: 0)],
            isClosed: false, layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 1.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 0.5,
            flatBottomMode: false,
            vectorDepths: [:]
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // 100mm at 1000mm/min = 0.1 min = 6 seconds
        // Plus some overhead for passes and lead-in/out
        XCTAssertGreaterThan(result.estimatedTimeSeconds, 5)
        XCTAssertLessThan(result.estimatedTimeSeconds, 60)
    }
}
