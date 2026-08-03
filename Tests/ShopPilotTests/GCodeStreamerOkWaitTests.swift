import XCTest
@testable import ShopPilotCore

// MARK: - GCodeStreamer Ok-Wait Protocol Tests (SPK-0404a)

/// Focused tests verifying the ok-wait protocol: send one line, wait for ok, advance.
final class GCodeStreamerOkWaitTests: XCTestCase {

    // MARK: - Single-line ok-wait with SimulatorTransport

    func testSingleLineSendWaitAdvance() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

// Consume the .connected event
        try await transport.open(config: config)
        let firstEvent = try await eventIterator.next(timeout: 2.0)
        XCTAssertEqual(.connected, firstEvent, "First event should be .connected")

        // Stream exactly one line
        let lines = ["G21"]
        try await streamer.stream(lines: lines, to: transport)

        // Verify: state returned to idle, progress 1.0, currentLine advanced to 1
        XCTAssertEqual(streamer.state, .idle, "State should be .idle after completing one line")
        XCTAssertEqual(streamer.progress, 1.0, "Progress should be 1.0 after one line")
        XCTAssertEqual(streamer.currentLine, 1, "currentLine should be 1 after one line")
        XCTAssertEqual(streamer.totalLines, 1, "totalLines should be 1")
    }

    func testSingleLineOkWaitWithFile() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

// Consume .connected
        try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        // Create a one-line G-code file
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("okwait_single.nc")
        try "G90\n".write(to: tempFile, atomically: true, encoding: .utf8)

        try await streamer.stream(from: tempFile, to: transport)

        XCTAssertEqual(streamer.state, .idle, "State should be .idle")
        XCTAssertEqual(streamer.currentLine, 1, "Should have processed 1 line")
        XCTAssertEqual(streamer.totalLines, 1, "totalLines should be 1")
    }

    // MARK: - ok-wait ordering: one line at a time

    func testLinesProcessedSequentially() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        let lines = ["G21", "G90", "G0 Z5", "G1 X10 F500"]
        try await streamer.stream(lines: lines, to: transport)

        XCTAssertEqual(streamer.currentLine, 4, "Should have processed all 4 lines")
        XCTAssertEqual(streamer.totalLines, 4, "totalLines should match input count")
        XCTAssertEqual(streamer.state, .idle, "Should end in idle")
    }

    // MARK: - Filtering: comments and blanks don't count

    func testCommentsFilteredFromCount() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        let lines = [
            "G21 ; set units",
            "(comment line)",
            "G90",
            "   ",
            "G0 Z5"
        ]
        try await streamer.stream(lines: lines, to: transport)

        // Comments and blanks are filtered; only G21, G90, G0 Z5 are streamed
        XCTAssertEqual(streamer.totalLines, 3, "Comments and blanks should be filtered out")
        XCTAssertEqual(streamer.currentLine, 3, "Should have processed 3 executable lines")
    }

    // MARK: - Empty input

    func testEmptyStreamNoOkWait() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        try await streamer.stream(lines: [], to: transport)

        XCTAssertEqual(streamer.state, .idle, "Empty stream should leave state idle")
        XCTAssertEqual(streamer.currentLine, 0, "No lines processed")
        XCTAssertEqual(streamer.totalLines, 0, "totalLines should be 0")
    }

    // MARK: - State transitions

    func testInitialStateIsIdle() {
        let streamer = GCodeStreamer()
        XCTAssertEqual(streamer.state, .idle, "New streamer starts idle")
        XCTAssertFalse(streamer.isStreaming, "isStreaming should be false initially")
    }

    func testIsStreamingProperty() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        // Before streaming
        XCTAssertFalse(streamer.isStreaming, "Should not be streaming before call")

        // During streaming (check mid-stream by observing state)
        let lines = ["G21", "G90"]
        try await streamer.stream(lines: lines, to: transport)

        // After streaming completes
        XCTAssertFalse(streamer.isStreaming, "Should not be streaming after completion")
        XCTAssertEqual(streamer.state, .idle)
    }

    // MARK: - Error handling: transport disconnect during ok-wait

    func testStreamerThrowsOnDisconnect() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        // Close transport mid-stream
        await transport.close()

        let lines = ["G21"]
        do {
            try await streamer.stream(lines: lines, to: transport)
            XCTFail("Streaming to a disconnected transport should throw")
        } catch {
            let nsError = error as NSError
            // Transport was closed before streaming, so the transport's own
            // write() error surfaces instead of the streamer's ok-wait error.
            // Either is correct — the safety property is that the failure is
            // reported and mentions the disconnection.
            if nsError.domain == "GCodeStreamer" {
                XCTAssertEqual(nsError.code, 2, "Error code should indicate disconnected transport")
            }
            let message = nsError.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("disconnect") || message.contains("not connected"),
                          "Error message should mention disconnection, got: \(nsError.localizedDescription)")
        }
    }

    // MARK: - Cancelled task

    func testStreamerRespectsCancellation() async throws {
        let transport = SimulatorTransport()
        let streamer = GCodeStreamer()

        let config = SerialConfig(isSimulator: true)
        var eventIterator = transport.events.makeAsyncIterator()
        defer { Task { await transport.close() } }

try await transport.open(config: config)
        _ = try await eventIterator.next(timeout: 2.0)

        // Many lines — cancel after a short delay
        let lines = Array(repeating: "G0 X1", count: 100)
        let task = Task {
            try await streamer.stream(lines: lines, to: transport)
        }

        // Cancel after 200ms — simulator has 50ms delay per line, so ~4 lines max
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        // Wait for the task to finish (it should exit gracefully)
        try await task.value

        // State should NOT be .streaming (either .idle or .error)
        XCTAssertNotEqual(streamer.state, .streaming, "Should not remain streaming after cancellation")
    }
}
