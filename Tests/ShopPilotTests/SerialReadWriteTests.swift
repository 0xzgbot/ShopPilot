import XCTest
@testable import ShopPilotCore

/// Tests for the serial open/write/read lifecycle using MockTransport.
///
/// AC:
/// - Open a port (or mock), write one line, read response path exists
/// - Unit test with mock transport preferred
final class SerialReadWriteTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
    }

    // MARK: - Open

    func testMockTransportOpensAndEmitsConnected() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)

        // Collect events from the stream
        var connected = false
        for await event in transport.events {
            if case .connected = event {
                connected = true
                break
            }
        }

        XCTAssertTrue(connected, "Transport should emit .connected after open")
    }

    // MARK: - Write

    func testMockTransportWritesOneLine() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)
        let line = "G21\n"
        try await transport.write(Data(line.utf8))

        XCTAssertEqual(transport.writtenText, line, "MockTransport should capture the written line")
        XCTAssertEqual(transport.writtenBytes.count, 1, "Should have exactly one write chunk")
    }

    // MARK: - Read

    func testMockTransportReadReturnsEmptyWhenNothingWritten() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)
        let data = try await transport.read()

        XCTAssertTrue(data.isEmpty, "MockTransport read should return empty Data when nothing was written")
    }

    // MARK: - Close

    func testMockTransportClosesAndEmitsDisconnected() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)
        await transport.close()

        // After close, the stream should terminate — iterating should complete
        var disconnected = false
        for await event in transport.events {
            if case .disconnected = event {
                disconnected = true
            }
        }

        XCTAssertTrue(disconnected, "Transport should emit .disconnected after close")
    }

    // MARK: - Full Lifecycle

    func testOpenWriteReadCloseLifecycle() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        // 1. Open
        try await transport.open(config: config)

        // 2. Write one line
        let gcodeLine = "G21 ; Set millimeters\n"
        try await transport.write(Data(gcodeLine.utf8))

        // 3. Read response path (mock returns empty — path exists, just no data)
        let response = try await transport.read()
        XCTAssertNotNil(response, "read() should return a Data value (not throw)")
        XCTAssertTrue(response.isEmpty, "Mock transport read returns empty Data")

        // 4. Verify write was captured
        XCTAssertEqual(transport.writtenText, gcodeLine)

        // 5. Close
        await transport.close()

        // 6. Verify disconnect event
        var gotDisconnect = false
        for await event in transport.events {
            if case .disconnected = event {
                gotDisconnect = true
            }
        }
        XCTAssertTrue(gotDisconnect, "Should receive .disconnected event after close")
    }

    // MARK: - Clear Captured

    func testMockTransportClearCapturedResetsWrittenBytes() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)
        try await transport.write(Data("FIRST\n".utf8))
        try await transport.write(Data("SECOND\n".utf8))

        XCTAssertEqual(transport.writtenBytes.count, 2, "Should have 2 writes before clear")

        transport.clearCaptured()

        XCTAssertTrue(transport.writtenBytes.isEmpty, "Should be empty after clear")
        XCTAssertTrue(transport.writtenText.isEmpty, "writtenText should be empty after clear")
    }

    // MARK: - Multiple Writes

    func testMockTransportCapturesMultipleWrites() async throws {
        let transport = MockTransport()
        let config = SerialConfig(baudRate: 115200, portName: "/dev/tty.SIM", isSimulator: true)

        try await transport.open(config: config)
        try await transport.write(Data("G21\n".utf8))
        try await transport.write(Data("G90\n".utf8))
        try await transport.write(Data("M3 S1000\n".utf8))

        let text = transport.writtenText
        XCTAssertTrue(text.contains("G21"))
        XCTAssertTrue(text.contains("G90"))
        XCTAssertTrue(text.contains("M3 S1000"))
        XCTAssertEqual(transport.writtenBytes.count, 3, "Should capture all 3 writes")
    }
}
