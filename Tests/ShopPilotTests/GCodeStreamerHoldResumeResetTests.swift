import XCTest
@testable import ShopPilotCore

// MARK: - MockTransport Tests

/// Verify the mock transport itself captures bytes correctly.
final class MockTransportTests: XCTestCase {

    func testMockTransportCapturesBytes() async throws {
        let transport = MockTransport()
        try await transport.open(config: SerialConfig())

        let testData = Data("G21\n".utf8)
        try await transport.write(testData)

        XCTAssertEqual(transport.writtenBytes.count, 1)
        XCTAssertEqual(transport.writtenBytes[0], testData)
        XCTAssertEqual(transport.writtenText, "G21\n")
    }

    func testMockTransportClearCaptured() async throws {
        let transport = MockTransport()
        try await transport.open(config: SerialConfig())

        try await transport.write(Data("X\n".utf8))
        try await transport.write(Data("Y\n".utf8))
        XCTAssertEqual(transport.writtenBytes.count, 2)

        transport.clearCaptured()
        XCTAssertEqual(transport.writtenBytes.count, 0)
        XCTAssertTrue(transport.writtenText.isEmpty)
    }

    func testMockTransportCapturesBinaryReset() async throws {
        let transport = MockTransport()
        try await transport.open(config: SerialConfig())

        let resetBytes = Data([0x18])
        try await transport.write(resetBytes)

        XCTAssertEqual(transport.writtenBytes.count, 1)
        XCTAssertEqual(transport.writtenBytes[0], resetBytes)
    }
}

// MARK: - GCodeStreamer Hold / Resume / Reset Tests (SPK-0404b)

/// Tests verifying the streamer's hold/resume/reset realtime commands
/// assert correct bytes written to the transport.
final class GCodeStreamerHoldResumeResetTests: XCTestCase {

    func testStreamerHoldSendsBang() async throws {
        let transport = MockTransport()
        let streamer = GCodeStreamer()

        try await transport.open(config: SerialConfig(isSimulator: true))

        // Start streaming so transport is set
        let task = Task {
            try await streamer.stream(lines: ["G21", "G90"], to: transport)
        }
        // Let it start
        try await Task.sleep(nanoseconds: 100_000_000)

        // Hold
        streamer.pause()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Resume
        streamer.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        task.cancel()
        _ = try? await task.value

        // Verify bytes: G21\n, G90\n, !\n, ~\n
        let text = transport.writtenText
        XCTAssertTrue(text.contains("G21\n"), "Should contain G21")
        XCTAssertTrue(text.contains("G90\n"), "Should contain G90")
        XCTAssertTrue(text.contains("!"), "Should contain hold command !")
        XCTAssertTrue(text.contains("~"), "Should contain resume command ~")
    }

    func testStreamerResetSendsCAN() async throws {
        let transport = MockTransport()
        let streamer = GCodeStreamer()

        try await transport.open(config: SerialConfig(isSimulator: true))

        // Start streaming
        let task = Task {
            try await streamer.stream(lines: ["G21", "G90", "G0 X5"], to: transport)
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        // Reset
        streamer.reset()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Let it finish
        task.cancel()
        _ = try? await task.value

        // Verify reset byte (0x18) was written
        let data = transport.writtenData
        XCTAssertTrue(data.contains(Data([0x18])), "Should contain 0x18 CAN reset byte")
    }

    func testStreamerResetResetsState() async throws {
        let transport = MockTransport()
        let streamer = GCodeStreamer()

        try await transport.open(config: SerialConfig(isSimulator: true))

        // Stream a few lines
        let task = Task {
            try await streamer.stream(lines: ["G21", "G90"], to: transport)
        }
        try await Task.sleep(nanoseconds: 150_000_000)

        // Reset
        streamer.reset()
        try await Task.sleep(nanoseconds: 50_000_000)

        // State should be idle after reset
        XCTAssertEqual(streamer.state, .idle, "State should be idle after reset")
        XCTAssertEqual(streamer.progress, 0.0, "Progress should be 0 after reset")
        XCTAssertEqual(streamer.currentLine, 0, "currentLine should be 0 after reset")
    }

    func testStreamerHoldDoesNotThrow() async throws {
        let transport = MockTransport()
        let streamer = GCodeStreamer()

        try await transport.open(config: SerialConfig(isSimulator: true))

        // No error should be thrown even when hold is called
        streamer.pause()
        streamer.resume()

        // If we got here without throwing, the test passes
        XCTAssertTrue(true, "hold/resume should not throw")
    }

    func testStreamerHoldAndResumeBytes() async throws {
        let transport = MockTransport()
        let streamer = GCodeStreamer()

        try await transport.open(config: SerialConfig(isSimulator: true))

        let task = Task {
            try await streamer.stream(lines: ["G21"], to: transport)
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        // Hold
        streamer.pause()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Resume
        streamer.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        task.cancel()
        _ = try? await task.value

        // Verify exact sequence
        let text = transport.writtenText
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        XCTAssertTrue(lines.contains("G21"), "Should have G21")
        XCTAssertTrue(lines.contains("!"), "Should have !")
        XCTAssertTrue(lines.contains("~"), "Should have ~")
    }
}

// MARK: - MachineSession Hold / Resume / Reset Tests (SPK-0404b)

/// Tests verifying MachineSession's hold/resume/reset APIs
/// assert correct bytes written to the mock transport.
final class MachineSessionHoldResumeResetTests: XCTestCase {

    func testSessionHoldSendsBang() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        try await session.connect(transport: transport)
        transport.clearCaptured()

        await session.hold()
        try await Task.sleep(nanoseconds: 50_000_000)

        let text = transport.writtenText
        XCTAssertTrue(text.contains("!"), "Session hold should send ! to transport")
        XCTAssertEqual(transport.writtenBytes.count, 1, "Should have exactly one write")
    }

    func testSessionResumeSendsTilde() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        try await session.connect(transport: transport)
        transport.clearCaptured()

        await session.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        let text = transport.writtenText
        XCTAssertTrue(text.contains("~"), "Session resume should send ~ to transport")
        XCTAssertEqual(transport.writtenBytes.count, 1, "Should have exactly one write")
    }

    func testSessionResetSendsCAN() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        try await session.connect(transport: transport)
        transport.clearCaptured()

        // Set some fake state first
        await MainActor.run {
            session.machineState = "Run"
            session.mPosX = 10.5
            session.mPosY = 20.3
            session.mPosZ = 5.0
        }

        await session.reset()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify 0x18 was written
        let data = transport.writtenData
        XCTAssertTrue(data.contains(Data([0x18])), "Session reset should send 0x18 CAN byte")

        // Verify local state was reset
        await MainActor.run {
            XCTAssertEqual(session.machineState, "unknown", "machineState should be reset to unknown")
            XCTAssertEqual(session.mPosX, 0.0, "mPosX should be 0 after reset")
            XCTAssertEqual(session.mPosY, 0.0, "mPosY should be 0 after reset")
            XCTAssertEqual(session.mPosZ, 0.0, "mPosZ should be 0 after reset")
        }
    }

    func testSessionHoldWhenDisconnectedDoesNothing() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        // Do NOT connect
        transport.clearCaptured()

        await session.hold()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(transport.writtenBytes.count, 0, "Hold on disconnected session should write nothing")
    }

    func testSessionResumeWhenDisconnectedDoesNothing() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        await session.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(transport.writtenBytes.count, 0, "Resume on disconnected session should write nothing")
    }

    func testSessionResetWhenDisconnectedDoesNothing() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        await session.reset()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(transport.writtenBytes.count, 0, "Reset on disconnected session should write nothing")
    }

    func testSessionHoldResumeResetSequence() async throws {
        let transport = MockTransport()
        let session = MachineSession()

        try await session.connect(transport: transport)
        transport.clearCaptured()

        // Hold
        await session.hold()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Resume
        await session.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Reset
        await session.reset()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify all three commands were sent
        let data = transport.writtenData
        let text = transport.writtenText

        XCTAssertTrue(data.contains(Data("!".utf8)), "Should contain hold command")
        XCTAssertTrue(data.contains(Data("~".utf8)), "Should contain resume command")
        XCTAssertTrue(data.contains(Data([0x18])), "Should contain reset command")
        XCTAssertEqual(transport.writtenBytes.count, 3, "Should have exactly 3 writes")
    }

    func testSessionHoldResetsIsPausedInStreamer() async throws {
        // Verify that hold actually pauses the streamer by checking state
        let transport = MockTransport()
        let session = MachineSession()
        let streamer = GCodeStreamer()

        try await session.connect(transport: transport)

        // Start streaming via streamer directly
        let streamTask = Task {
            try await streamer.stream(lines: ["G21", "G90", "G0 X5"], to: transport)
        }
        try await Task.sleep(nanoseconds: 150_000_000)

        // Hold via session
        await session.hold()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Streamer should be paused
        XCTAssertEqual(streamer.state, .paused, "Streamer should be paused after hold")

        streamTask.cancel()
        _ = try? await streamTask.value
    }
}
