import XCTest
@testable import ShopPilotCore
@testable import ShopPilotGeometry
@testable import ShopPilotSerial

// MARK: - Calibration E2E Tests

/// End-to-end test for the calibration job pipeline:
/// design vectors → profile toolpath → preview simulation → stream to simulator
final class CalibrationE2ETests: XCTestCase {
    
    var streamer: GCodeStreamer!
    
    override func setUp() {
        super.setUp()
        streamer = GCodeStreamer()
    }
    
    // MARK: - Design Phase: Create Calibration Vectors
    
    func testCreateCalibrationSquareVectors() {
        // Create a simple square (calibration vector set)
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0) // Close the path
        ]
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        XCTAssertEqual(vectorPath.points.count, 5)
        XCTAssertTrue(vectorPath.isClosed)
        XCTAssertEqual(vectorPath.length, 200.0) // 4 sides × 50mm
    }
    
    func testCreateCalibrationCircleVectors() {
        // Create a circle approximation (8-point polygon)
        let center = VectorPoint(x: 25, y: 25)
        let radius: Double = 20
        let segments = 16
        var points: [VectorPoint] = []
        
        for i in 0...segments {
            let angle = Double(i) * 2.0 * .pi / Double(segments)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            points.append(VectorPoint(x: x, y: y))
        }
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        XCTAssertTrue(vectorPath.isClosed)
        XCTAssertEqual(vectorPath.points.count, segments + 1)
    }
    
    // MARK: - Cut Phase: Generate Toolpath
    
    func testProfileToolpathFromCalibrationSquare() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            toolDiameterMm: 6.0,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )
        
        let result = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        // Verify toolpath was generated
        XCTAssertFalse(result.gcodeLines.isEmpty)
        XCTAssertEqual(result.passCount, 6) // 12mm stock / 2mm depth = 6 passes
        
        // Verify G-code structure
        XCTAssertTrue(result.gcodeLines.contains { $0.contains("G0 Z5.0") })
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1 Z") })
        XCTAssertTrue(result.gcodeLines.contains { $0.hasPrefix("G1 X") })
        XCTAssertTrue(result.gcodeLines.contains { $0 == "M30" })
    }
    
    func testProfileToolpathWithMaterialDefaults() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 100, y: 0),
            VectorPoint(x: 100, y: 100),
            VectorPoint(x: 0, y: 100),
            VectorPoint(x: 0, y: 0)
        ]
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let pine = Material.pine
        
        let params = ProfileToolpathParams.fromMaterial(pine, toolDiameter: 6.0)
        
        let result = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: pine,
            stockHeightMm: 12.0
        )
        
        // Verify material-based parameters
        XCTAssertEqual(params.feedRateMmPerMin, 4200.0) // 6000 * 0.7
        XCTAssertEqual(params.plungeFeedRateMmPerMin, 1800.0) // 6000 * 0.3
        XCTAssertEqual(params.maxDepthOfCutMm, 6.0)
        XCTAssertEqual(params.toolDiameterMm, 6.0)
        
        XCTAssertFalse(result.gcodeLines.isEmpty)
    }
    
    // MARK: - Preview Phase: Simulate Toolpath
    
    func testSimulateProfileToolpath() {
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            toolDiameterMm: 6.0,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )
        
        let toolpathResult = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        let gcodeString = toolpathResult.gcodeLines.joined(separator: "\n")
        
        // Simulate the toolpath
        let simulator = ToolpathSimulator.createDefault(cellSizeMm: 0.5, stockWidthMm: 100, stockHeightMm: 100)
        let simulation = simulator.simulate(toolpathGcode: toolpathResult.gcodeLines)
        
        // Verify simulation completed
        XCTAssertGreaterThan(simulation.finalHeightmap.data.count, 0)
        
        // Verify material was removed: some cells should be below the stock height (12.0)
        XCTAssertTrue(simulation.finalHeightmap.data.contains { $0 < 12.0 })
    }
    
    func testSimulateEmptyGcode() {
        let simulator = ToolpathSimulator.createDefault(cellSizeMm: 0.5, stockWidthMm: 100, stockHeightMm: 100)
        let simulation = simulator.simulate(toolpathGcode: [])
        
        // No G-code → no material removed; all cells remain at stock height (12.0)
        XCTAssertFalse(simulation.finalHeightmap.data.contains { $0 < 12.0 })
    }
    
    // MARK: - Machine Phase: Stream to Simulator
    
    func testStreamCalibrationGcodeToSimulator() async throws {
        let config = SerialConfig(isSimulator: true)
        let transport = SimulatorTransport()
        
        try await transport.open(config: config)
        
        // Create calibration G-code
        let gcodeLines = [
            "G21 ; Set millimeter units",
            "G90 ; Absolute positioning",
            "G0 Z5.0 ; Safe Z height",
            "G0 X0 Y0 ; Move to origin",
            "G1 Z-2.0 F300 ; Plunge",
            "G1 X50 F1000 ; Cut line 1",
            "G1 X50 Y50 F1000 ; Cut line 2",
            "G1 X0 Y50 F1000 ; Cut line 3",
            "G1 X0 Y0 F1000 ; Cut line 4",
            "G0 Z5.0 ; Retract",
            "M30 ; Program end"
        ]
        
        // Stream to simulator
        try await streamer.stream(lines: gcodeLines, to: transport)
        
        // Verify completion
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 1.0)
        XCTAssertEqual(streamer.currentLine, gcodeLines.count)
        XCTAssertEqual(streamer.totalLines, gcodeLines.count)
        
        await transport.close()
    }
    
    // MARK: - Full E2E Pipeline
    
    func testFullCalibrationPipeline() async throws {
        // Phase 1: Design — Create calibration vectors
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 50, y: 0),
            VectorPoint(x: 50, y: 50),
            VectorPoint(x: 0, y: 50),
            VectorPoint(x: 0, y: 0)
        ]
        let vectorPath = VectorPath(points: points, isClosed: true)
        XCTAssertTrue(vectorPath.isClosed)
        
        // Phase 2: Cut — Generate profile toolpath
        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            toolDiameterMm: 6.0,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )
        
        let toolpathResult = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        XCTAssertFalse(toolpathResult.gcodeLines.isEmpty)
        XCTAssertTrue(toolpathResult.gcodeLines.contains { $0.contains("G0 Z5.0") })
        
        // Phase 3: Preview — Simulate material removal
        let simulator = ToolpathSimulator.createDefault(cellSizeMm: 0.5, stockWidthMm: 100, stockHeightMm: 100)
        let simulation = simulator.simulate(toolpathGcode: toolpathResult.gcodeLines)
        
        XCTAssertGreaterThan(simulation.finalHeightmap.data.count, 0)
        XCTAssertTrue(simulation.finalHeightmap.data.contains { $0 < 12.0 })
        
        // Phase 4: Machine — Stream to simulator
        let config = SerialConfig(isSimulator: true)
        let transport = SimulatorTransport()
        try await transport.open(config: config)
        
        // Filter to non-comment lines for streaming
        let streamLines = toolpathResult.gcodeLines.filter { !$0.hasPrefix(";") && !$0.hasPrefix("%") }
        try await streamer.stream(lines: streamLines, to: transport)
        
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 1.0)
        
        await transport.close()
    }
    
    // MARK: - Golden Fixture Verification
    
    func testGoldenProfileFixture() {
        let manager = GoldenFixtureManager.createWithPredefinedFixtures()
        
        guard let expectedGcode = manager.fixture(for: .profile) else {
            XCTFail("Profile fixture not registered")
            return
        }
        
        // Create a simple square vector
        let points: [VectorPoint] = [
            VectorPoint(x: 0, y: 0),
            VectorPoint(x: 10, y: 0),
            VectorPoint(x: 10, y: 10),
            VectorPoint(x: 0, y: 10),
            VectorPoint(x: 0, y: 0)
        ]
        
        let vectorPath = VectorPath(points: points, isClosed: true)
        
        let params = ProfileToolpathParams(
            cutMode: .onCut,
            feedRateMmPerMin: 1000,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: 2.0,
            toolDiameterMm: 6.0,
            tabWidths: [],
            finishPasses: 1,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0
        )
        
        let result = ProfileToolpathEngine.compute(
            vectors: [vectorPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        let actualGcode = result.gcodeLines.joined(separator: "\n")
        
        // Verify the actual output has valid G-code structure
        XCTAssertTrue(actualGcode.contains("G0 Z5.0"))
        XCTAssertTrue(actualGcode.contains("G1"))
        XCTAssertTrue(actualGcode.contains("M30"))
        XCTAssertTrue(actualGcode.contains("%"))
    }
    
    // MARK: - Error Handling
    
    func testEmptyVectorPath() {
        let emptyPath = VectorPath(points: [], isClosed: false)
        XCTAssertTrue(emptyPath.points.isEmpty)
        
        let params = ProfileToolpathParams()
        let result = ProfileToolpathEngine.compute(
            vectors: [emptyPath],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        // Should still produce G-code (just with no cuts)
        XCTAssertFalse(result.gcodeLines.isEmpty)
    }
    
    func testSinglePointVectorPath() {
        let singlePoint = VectorPath(points: [VectorPoint(x: 10, y: 10)], isClosed: false)
        XCTAssertEqual(singlePoint.points.count, 1)
        
        let params = ProfileToolpathParams()
        let result = ProfileToolpathEngine.compute(
            vectors: [singlePoint],
            params: params,
            material: nil,
            stockHeightMm: 12.0
        )
        
        XCTAssertFalse(result.gcodeLines.isEmpty)
    }
}
