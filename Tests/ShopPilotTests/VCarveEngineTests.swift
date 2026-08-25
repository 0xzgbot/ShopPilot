import XCTest
@testable import ShopPilotCore
@testable import ShopPilotGeometry

final class VCarveEngineTests: XCTestCase {
    
    // MARK: - Basic V-Carve Computation
    
    func testBasicVCarveProducesGCode() {
        // Create a simple horizontal line vector
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
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Verify G-code header exists
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("V-Bit") })
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("O=V_CARVE_TOOLPATH") })
        
        // Verify G-code footer exists
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        XCTAssertTrue(result.gcodeLines.contains("%"))
        
        // Verify Z moves are present
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1 Z") })
        
        // Verify X/Y moves are present
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1 X") })
    }
    
    func testVCarvePassCountBasedOnTipWidth() {
        // 90-degree V-bit at 2mm depth: tipWidth = 2 * |2| * tan(45°) = 4mm
        // With stepOver = 1mm, should produce 4 passes
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
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // 90° V-bit: halfAngle = 45°, tan(45°) = 1
        // tipWidth at 2mm = 2 * 2 * 1 = 4mm
        // passCount = ceil(4 / 1) = 4
        XCTAssertEqual(result.passCount, 4)
    }
    
    func testVCarvePassCountFor30DegreeBit() {
        // 30-degree V-bit at 2mm depth: tipWidth = 2 * |2| * tan(15°) ≈ 1.07mm
        // With stepOver = 1mm, should produce 2 passes
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
        
        let params = VCarveParams(
            vBitAngleDegrees: 30.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // 30° V-bit: halfAngle = 15°, tan(15°) ≈ 0.268
        // tipWidth at 2mm = 2 * 2 * 0.268 ≈ 1.07mm
        // passCount = ceil(1.07 / 1) = 2
        XCTAssertEqual(result.passCount, 2)
    }
    
    // MARK: - Flat Bottom Mode
    
    func testFlatBottomModeConstantZ() {
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
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0,
            flatBottomMode: true
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // In flat-bottom mode, all passes should use Z = -2.0 (constant depth).
        // Filter G1 moves only — the pass comment uses `Z=` display format.
        let zLines = result.gcodeLines.filter { $0.contains("G1 Z") }
        for line in zLines {
            XCTAssertTrue(line.contains("Z-2.000"), "Flat bottom mode should use constant Z=-2.000, got: \(line)")
        }
    }
    
    // MARK: - Per-Vector Depths
    
    func testPerVectorDepths() {
        let id1 = UUID()
        let id2 = UUID()
        
        let vector1 = VectorPath(
            id: id1,
            name: "deep",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let vector2 = VectorPath(
            id: id2,
            name: "shallow",
            points: [
                VectorPoint(x: 0, y: 50),
                VectorPoint(x: 50, y: 50)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0,
            vectorDepths: [id1: 3.0, id2: 1.0]
        )
        
        let result = VCarveEngine.compute(vectors: [vector1, vector2], params: params)
        
        // Result should contain G-code for both vectors
        let gcode = result.gcodeLines.joined(separator: "\n")
        XCTAssertTrue(gcode.contains("O=V_CARVE_TOOLPATH"))
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
                    name: "vector_\(i)",
                    points: points,
                    isClosed: false,
                    layerId: UUID()
                )
            )
        }
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: vectors, params: params)
        
        // Should produce G-code for all vectors
        XCTAssertGreaterThan(result.gcodeLines.count, 10)
        XCTAssertTrue(result.gcodeLines.contains("M30"))
    }
    
    // MARK: - Bounding Box
    
    func testBoundingBoxComputation() {
        let vector = VectorPath(
            id: UUID(),
            name: "test",
            points: [
                VectorPoint(x: 10, y: 20),
                VectorPoint(x: 100, y: 200)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams()
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        XCTAssertEqual(result.boundsMinX, 10.0)
        XCTAssertEqual(result.boundsMinY, 20.0)
        XCTAssertEqual(result.boundsMaxX, 100.0)
        XCTAssertEqual(result.boundsMaxY, 200.0)
    }
    
    func testEmptyVectorsNoBounds() {
        let params = VCarveParams()
        let result = VCarveEngine.compute(vectors: [], params: params)
        
        XCTAssertNil(result.boundsMinX)
        XCTAssertNil(result.boundsMinY)
        XCTAssertNil(result.boundsMaxX)
        XCTAssertNil(result.boundsMaxY)
    }
    
    // MARK: - Time Estimate
    
    func testTimeEstimateCalculation() {
        // Create a 100mm line
        let vector = VectorPath(
            id: UUID(),
            name: "test",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 100, y: 0)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // 100mm at 1000mm/min = 0.1 min = 6 seconds
        // With 4 passes: 6 * 4 = 24 seconds (rough estimate)
        XCTAssertGreaterThan(result.estimatedTimeSeconds, 0)
    }
    
    // MARK: - G-Code Structure
    
    func testGCodeHasLeadInLeadOut() {
        let vector = VectorPath(
            id: UUID(),
            name: "test",
            points: [
                VectorPoint(x: 50, y: 50),
                VectorPoint(x: 100, y: 50)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        let gcode = result.gcodeLines.joined(separator: "\n")
        
        // Lead-in: X should be 50 - 5 = 45
        XCTAssertTrue(gcode.contains("G0 X45.000"), "Lead-in should start 5mm before vector start")
        
        // Lead-out is a cutting move (G1 at depth), not a rapid (G0).
        XCTAssertTrue(gcode.contains("G1 X105.000"), "Lead-out should end 5mm after vector end")
    }
    
    // MARK: - Safety Checks
    
    func testEmptyVectorSkipped() {
        let vector = VectorPath(
            id: UUID(),
            name: "empty",
            points: [],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams()
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Should produce minimal G-code (header + footer only)
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
        XCTAssertEqual(result.passCount, 0)
    }
    
    func testSinglePointVectorSkipped() {
        let vector = VectorPath(
            id: UUID(),
            name: "single",
            points: [VectorPoint(x: 0, y: 0)],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams()
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Single point should be skipped (need >= 2 points)
        XCTAssertTrue(result.gcodeLines.contains("O=V_CARVE_TOOLPATH"))
        XCTAssertTrue(result.gcodeLines.contains("M30"))
    }
    
    // MARK: - V-Bit Angle Variations
    
    func test90DegreeVBitTipWidth() {
        let params = VCarveParams(vBitAngleDegrees: 90.0)
        let tipWidth = params.tipWidthAtDepth(2.0)
        // tan(45°) = 1, so tipWidth = 2 * 2 * 1 = 4
        XCTAssertEqual(tipWidth, 4.0, accuracy: 1e-9)
    }
    
    func test45DegreeVBitTipWidth() {
        let params = VCarveParams(vBitAngleDegrees: 45.0)
        let tipWidth = params.tipWidthAtDepth(2.0)
        // tan(22.5°) ≈ 0.414, so tipWidth = 2 * 2 * 0.414 ≈ 1.657
        XCTAssertEqual(tipWidth, 1.65685424949238, accuracy: 1e-6)
    }
    
    func test30DegreeVBitTipWidth() {
        let params = VCarveParams(vBitAngleDegrees: 30.0)
        let tipWidth = params.tipWidthAtDepth(2.0)
        // tan(15°) ≈ 0.268, so tipWidth = 2 * 2 * 0.268 ≈ 1.072
        XCTAssertEqual(tipWidth, 1.0717967697244, accuracy: 1e-6)
    }
    
    // MARK: - V-Carve Shading
    
    func testVCarveShadingZVariation() {
        // Create a vertical vector (Y varies from 0 to 100)
        let vector = VectorPath(
            id: UUID(),
            name: "vertical",
            points: [
                VectorPoint(x: 50, y: 0),
                VectorPoint(x: 50, y: 100)
            ],
            isClosed: false,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        let gcode = result.gcodeLines.joined(separator: "\n")
        
        // SPK-2010b: depth comes from local channel WIDTH, not page Y. An
        // open straight polyline has no interior width, so every point cuts
        // at this pass's clamp depth — identical Z at both ends.
        XCTAssertTrue(gcode.contains("G1 X50.000 Y100.000 Z-2.000"), "Far end should cut at the pass depth, got: \(gcode)")
        XCTAssertTrue(gcode.contains("G1 X50.000 Y0.000"), "Near end should be cut too")
    }
    
    // MARK: - Closed Vector Path
    
    func testClosedVectorPath() {
        let vector = VectorPath(
            id: UUID(),
            name: "square",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 50, y: 0),
                VectorPoint(x: 50, y: 50),
                VectorPoint(x: 0, y: 50),
                VectorPoint(x: 0, y: 0) // Closed
            ],
            isClosed: true,
            layerId: UUID()
        )
        
        let params = VCarveParams(
            vBitAngleDegrees: 90.0,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            stepOverMm: 1.0
        )
        
        let result = VCarveEngine.compute(vectors: [vector], params: params)
        
        // Should produce G-code for the closed path
        XCTAssertGreaterThan(result.gcodeLines.count, 5)
    }
}
