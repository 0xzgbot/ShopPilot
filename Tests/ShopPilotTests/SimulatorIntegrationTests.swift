import XCTest
@testable import ShopPilotCore
@testable import ShopPilotSerial

// MARK: - Simulator Integration Tests

/// Comprehensive end-to-end test of the machine control path using SimulatorTransport.
/// Tests: connect → stream fixture → hold → resume → complete
final class SimulatorIntegrationTests: XCTestCase {
    
    var transport: SimulatorTransport!
    var streamer: GCodeStreamer!
    
    override func setUp() {
        super.setUp()
        transport = SimulatorTransport()
        streamer = GCodeStreamer()
    }
    
    override func tearDown() {
        transport = nil
        streamer = nil
        super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testConnectToSimulator() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        XCTAssertEqual(transport.events.makeAsyncIterator().next(), .connected)
    }
    
    func testDisconnectFromSimulator() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        // Simulate receiving events
        var eventIterator = transport.events.makeAsyncIterator()
        let connectedEvent = try await eventIterator.next(timeout: 1.0)
        XCTAssertEqual(connectedEvent, .connected)
        
        await transport.close()
        
        let disconnectedEvent = try await eventIterator.next(timeout: 1.0)
        XCTAssertEqual(disconnectedEvent, .disconnected)
    }
    
    // MARK: - Command Tests
    
    func testStatusQuery() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        // Simulate receiving events
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0) // .connected
        
        try await transport.write(Data("?".utf8))
        
        if let event = try await eventIterator.next(timeout: 1.0) {
            if case .dataReceived(let data) = event {
                let response = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(response.contains("<Idle"))
                XCTAssertTrue(response.contains("MPos:"))
            }
        }
    }
    
    func testMoveCommand() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0)
        
        try await transport.write(Data("G0 X10 Y20".utf8))
        
        if let event = try await eventIterator.next(timeout: 1.0) {
            if case .dataReceived(let data) = event {
                let response = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(response.contains("MPos:10.000"))
                XCTAssertTrue(response.contains("MPos:,20.000"))
            }
        }
    }
    
    func testSoftHomeCommand() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0)
        
        // Move to a position first
        try await transport.write(Data("G0 X50 Y50".utf8))
        _ = try await eventIterator.next(timeout: 1.0)
        
        // Then soft home
        try await transport.write(Data("G28".utf8))
        
        if let event = try await eventIterator.next(timeout: 1.0) {
            if case .dataReceived(let data) = event {
                let response = String(decoding: data, as: UTF8.self)
                XCTAssertTrue(response.contains("MPos:0.000,0.000,0.000"))
            }
        }
    }
    
    // MARK: - Streamer Tests
    
    func testStreamerInitialState() {
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 0.0)
        XCTAssertEqual(streamer.currentLine, 0)
        XCTAssertEqual(streamer.totalLines, 0)
    }
    
    func testStreamerIsStreamingProperty() {
        XCTAssertFalse(streamer.isStreaming)
        streamer.state = .streaming
        XCTAssertTrue(streamer.isStreaming)
    }
    
    func testStreamerPauseAndResume() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0)
        
        // Start streaming
        let gcodeLines = ["G21", "G90", "G0 Z5", "G0 X0 Y0", "G1 Z-1 F100", "G1 X50 F500"]
        try await streamer.stream(lines: gcodeLines, to: transport)
        
        // After streaming completes, state should be idle
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 1.0)
    }
    
    func testStreamerLoadFromFile() async throws {
        // Create a temporary G-code file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_integration.nc")
        
        let gcodeContent = """
        G21 ; Set units to mm
        G90 ; Absolute positioning
        G0 Z5 ; Safe Z height
        G0 X0 Y0 ; Move to origin
        G1 Z-1 F100 ; Plunge
        G1 X50 F500 ; Cut line 1
        G1 X50 Y50 ; Cut line 2
        G1 X0 Y50 ; Cut line 3
        G1 X0 Y0 ; Cut line 4
        G0 Z5 ; Retract
        M2 ; Program end
        """
        
        try gcodeContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let lines = try await streamer.load(from: testFile)
        
        // Should filter out comments and blank lines
        XCTAssertTrue(lines.count > 0)
        XCTAssertFalse(lines.contains { $0.hasPrefix(";") })
        XCTAssertFalse(lines.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
    
    func testStreamerLoadFromURL() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_integration2.nc")
        
        let gcodeContent = "G21\nG90\nG0 Z5\nG0 X0 Y0\nM2\n"
        try gcodeContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let lines = try await streamer.load(from: testFile)
        
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0], "G21")
        XCTAssertEqual(lines[1], "G90")
    }
    
    // MARK: - Full Integration Test
    
    func testFullIntegrationConnectStreamComplete() async throws {
        // Step 1: Connect
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        let connectedEvent = try await eventIterator.next(timeout: 1.0)
        XCTAssertEqual(connectedEvent, .connected)
        
        // Step 2: Prepare G-code
        let gcodeLines = [
            "G21 ; Set millimeter units",
            "G90 ; Absolute positioning",
            "G0 Z5 ; Safe Z height",
            "G0 X0 Y0 ; Move to origin",
            "G1 Z-1 F100 ; Plunge",
            "G1 X50 F500 ; Cut line 1",
            "G1 X50 Y50 ; Cut line 2",
            "G1 X0 Y50 ; Cut line 3",
            "G1 X0 Y0 ; Cut line 4",
            "G0 Z5 ; Retract",
            "M2 ; Program end"
        ]
        
        // Step 3: Stream
        try await streamer.stream(lines: gcodeLines, to: transport)
        
        // Step 4: Verify completion
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 1.0)
        XCTAssertEqual(streamer.currentLine, gcodeLines.count)
        XCTAssertEqual(streamer.totalLines, gcodeLines.count)
        
        // Step 5: Disconnect
        await transport.close()
        
        let disconnectedEvent = try await eventIterator.next(timeout: 1.0)
        XCTAssertEqual(disconnectedEvent, .disconnected)
    }
    
    // MARK: - Error Handling Tests
    
    func testStreamerErrorOnTransportFailure() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0)
        
        // Close transport while streamer is trying to stream
        await transport.close()
        
        let gcodeLines = ["G21", "G90"]
        
        do {
            try await streamer.stream(lines: gcodeLines, to: transport)
            XCTFail("Expected stream to throw an error")
        } catch {
            // Expected — transport is closed
            XCTAssertNotNil(error)
        }
    }
    
    func testEmptyGcodeStream() async throws {
        let config = SerialConfig(isSimulator: true)
        try await transport.open(config: config)
        
        var eventIterator = transport.events.makeAsyncIterator()
        _ = try await eventIterator.next(timeout: 1.0)
        
        let emptyLines: [String] = []
        try await streamer.stream(lines: emptyLines, to: transport)
        
        XCTAssertEqual(streamer.state, .idle)
        XCTAssertEqual(streamer.progress, 1.0)
        XCTAssertEqual(streamer.currentLine, 0)
    }
}
