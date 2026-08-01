import Foundation

/// Non-UI golden path: rectangle → profile G-code → simulator stream (hold/resume capable).
/// Runnable without XCTest via the `ShopPilotGoldenPath` executable.
public enum DemoableGoldenPath {
    public struct Result: Sendable {
        public let gcodeLineCount: Int
        public let streamedLines: Int
        public let held: Bool
        public let resumed: Bool
        public let completed: Bool
        public let summary: String
    }

    public enum PathError: Error, LocalizedError {
        case emptyGCode
        case streamFailed(String)

        public var errorDescription: String? {
            switch self {
            case .emptyGCode: return "Profile engine produced no G-code"
            case .streamFailed(let m): return "Stream failed: \(m)"
            }
        }
    }

    /// Run the demoable simulator path end-to-end.
    public static func run() async throws -> Result {
        let layerId = UUID()
        let square = VectorPath(
            name: "Calibration Square",
            points: [
                VectorPoint(x: 0, y: 0),
                VectorPoint(x: 25, y: 0),
                VectorPoint(x: 25, y: 25),
                VectorPoint(x: 0, y: 25),
                VectorPoint(x: 0, y: 0),
            ],
            isClosed: true,
            layerId: layerId
        )

        let profile = ProfileToolpathEngine.compute(
            vectors: [square],
            params: ProfileToolpathParams(
                cutMode: .onCut,
                feedRateMmPerMin: 800,
                plungeFeedRateMmPerMin: 200,
                maxDepthOfCutMm: 1.0,
                toolDiameterMm: 3.175
            ),
            stockHeightMm: 2.0
        )

        guard !profile.gcodeLines.isEmpty else { throw PathError.emptyGCode }

        let transport = SimulatorTransport()
        try await transport.open(config: SerialConfig(isSimulator: true))

        let streamer = GCodeStreamer()
        var held = false
        var resumed = false

        // Stream in background; exercise hold/resume mid-job when possible.
        let streamTask = Task {
            try await streamer.stream(lines: profile.gcodeLines, to: transport)
        }

        // Brief delay then pause/resume if still streaming
        try await Task.sleep(nanoseconds: 50_000_000)
        if streamer.state == .streaming {
            await streamer.pause()
            held = true
            try await Task.sleep(nanoseconds: 30_000_000)
            await streamer.resume()
            resumed = true
        }

        do {
            try await streamTask.value
        } catch {
            throw PathError.streamFailed(error.localizedDescription)
        }

        await transport.close()

        let completed = streamer.state == .idle
            || streamer.currentLine >= profile.gcodeLines.count

        return Result(
            gcodeLineCount: profile.gcodeLines.count,
            streamedLines: streamer.currentLine,
            held: held,
            resumed: resumed,
            completed: completed,
            summary: "Golden path OK — \(profile.gcodeLines.count) G-code lines, streamed \(streamer.currentLine), hold=\(held), resume=\(resumed)"
        )
    }
}
