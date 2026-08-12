import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - ConnectionState

/// Connection state of the machine session.
public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - MachineSession

/// Facade that coordinates transport, status parsing, and streaming for a CNC machine.
public final class MachineSession: ObservableObject {

    // MARK: - Published State

    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var machineState: String = "unknown"
    @Published public var mPosX: Double = 0.0
    @Published public var mPosY: Double = 0.0
    @Published public var mPosZ: Double = 0.0
    @Published public var wPosX: Double = 0.0
    @Published public var wPosY: Double = 0.0
    @Published public var wPosZ: Double = 0.0

    // MARK: - Private State

    private var transport: MachineTransport?

    /// Consumes transport events and parses `<Idle|MPos:…>` status reports
    /// into the published state.
    private var eventTask: Task<Void, Never>?

    /// Actively queries GRBL by writing `?` on an interval (SPK-1401f).
    private var pollTask: Task<Void, Never>?

    /// The poller that writes the GRBL status-query byte to the transport.
    private let statusPoller: StatusPoller

    // MARK: - Computed Properties

    public var isConnected: Bool { connectionState == .connected }

    // MARK: - Lifecycle

    public init(statusPollInterval: Duration = .milliseconds(500)) {
        self.statusPoller = StatusPoller(
            intervalNanoseconds: Self.statusPollIntervalNanoseconds(statusPollInterval)
        )
    }

    deinit {
        eventTask?.cancel()
        pollTask?.cancel()
    }

    /// Convert a `Duration` to whole nanoseconds for the poller's sleep.
    private static func statusPollIntervalNanoseconds(_ interval: Duration) -> UInt64 {
        let components = interval.components
        let seconds = UInt64(max(0, components.seconds))
        let attoseconds = UInt64(max(0, components.attoseconds))
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }

    // MARK: - Connection Management

    public func connect(transport: MachineTransport, config: SerialConfig = SerialConfig()) async throws {
        guard !isConnected else { return }

        self.transport = transport
        connectionState = .connecting

        do {
            // SPK-1401a: the caller's config (UI port/baud) must reach the
            // transport — never open with a fresh default that discards it.
            try await transport.open(config: config)
            connectionState = .connected
            startStatusPolling(transport: transport)
        } catch {
            connectionState = .error(error.localizedDescription)
            self.transport = nil
            throw error
        }
    }

    /// Adopt an already-open transport (e.g. one opened by `ConnectionManager`)
    /// without re-opening it. Wires status polling and marks the session
    /// connected so hold/resume/reset reach the machine.
    public func attach(transport: MachineTransport) {
        guard self.transport !== transport else { return }
        self.transport = transport
        connectionState = .connected
        startStatusPolling(transport: transport)
    }

    public func disconnect() async {
        eventTask?.cancel()
        eventTask = nil
        pollTask?.cancel()
        pollTask = nil
        await transport?.close()
        transport = nil
        connectionState = .disconnected
        machineState = "unknown"
        mPosX = 0.0; mPosY = 0.0; mPosZ = 0.0
        wPosX = 0.0; wPosY = 0.0; wPosZ = 0.0
    }

    /// Drop the session's transport reference without closing it (used when an
    /// external owner — e.g. `ConnectionManager` — manages the transport's
    /// lifecycle). Stops status polling and resets local state.
    public func detach() {
        eventTask?.cancel()
        eventTask = nil
        pollTask?.cancel()
        pollTask = nil
        transport = nil
        connectionState = .disconnected
        machineState = "unknown"
        mPosX = 0.0; mPosY = 0.0; mPosZ = 0.0
        wPosX = 0.0; wPosY = 0.0; wPosZ = 0.0
    }

    // MARK: - Status Polling

    private func startStatusPolling(transport: MachineTransport) {
        // Reader: consume transport events and parse status reports into the
        // published position/state the UI shows.
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in transport.events {
                guard !Task.isCancelled else { break }

                switch event {
                case .dataReceived(let data):
                    if let parsed = StatusParser.parse(data) {
                        await MainActor.run { [parsed] in
                            self.machineState = parsed.state
                            self.mPosX = parsed.mPosX
                            self.mPosY = parsed.mPosY
                            self.mPosZ = parsed.mPosZ
                            self.wPosX = parsed.wPosX
                            self.wPosY = parsed.wPosY
                            self.wPosZ = parsed.wPosZ
                        }
                    }

                case .connected:
                    await MainActor.run { [weak self] in
                        self?.connectionState = .connected
                    }

                case .disconnected:
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if self.connectionState == .connected || self.connectionState == .connecting {
                            self.connectionState = .disconnected
                            self.machineState = "unknown"
                            self.mPosX = 0.0; self.mPosY = 0.0; self.mPosZ = 0.0
                            self.wPosX = 0.0; self.wPosY = 0.0; self.wPosZ = 0.0
                        }
                    }

                case .error(let message):
                    await MainActor.run { [weak self, message] in
                        self?.connectionState = .error(message)
                    }
                }
            }
        }

        // Poller: actively ask GRBL for status by writing '?' on an interval.
        // The poller is cancellable (disconnect()/detach() cancel this task)
        // and stops writing the moment the task is cancelled or the transport
        // rejects a write — the wire goes silent with the connection.
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.statusPoller.run(transport: transport)
        }
    }

    // MARK: - G-code Buffer

    /// G-code lines loaded from the Cut stage (post-processed).
    @Published public var gcodeBuffer: [String] = []

    /// Load G-code lines into the session buffer.
    public func loadGCode(_ lines: [String]) {
        gcodeBuffer = lines
    }

    /// Run the buffered G-code through the streamer to the connected transport.
    public func runJob() async throws {
        guard let transport = transport, isConnected else {
            throw MachineSessionError.notConnected
        }
        guard !gcodeBuffer.isEmpty else {
            throw MachineSessionError.commandFailed("No G-code loaded")
        }

        let streamer = GCodeStreamer()
        try await streamer.stream(lines: gcodeBuffer, to: transport)
    }

    // MARK: - Hold / Resume / Reset (GRBL control)

    /// Send GRBL hold command (bang).
    public func hold() async {
        guard isConnected else { return }
        guard let transport = transport else { return }
        // Pause the streamer if it is streaming
        await streamer?.pause()
        do {
            try await transport.write(Data("!".utf8))
        } catch {
            // Best-effort: hold should not crash
        }
    }

    /// Send GRBL resume command (tilde).
    public func resume() async {
        guard isConnected else { return }
        guard let transport = transport else { return }
        await streamer?.resume()
        do {
            try await transport.write(Data("~".utf8))
        } catch {
            // Best-effort
        }
    }

    /// Send GRBL reset (CAN byte 0x18).
    public func reset() async {
        // Reset must work from the alarm/error banner too — that is its job.
        // Only bail when there is no transport at all.
        guard let transport = transport else { return }
        await streamer?.reset()
        do {
            try await transport.write(Data([0x18]))
            // Refresh status so the UI reports Idle once the alarm clears
            // (the simulator does not emit status on its own after reset).
            _ = try? await transport.write(Data("?".utf8))
        } catch {
            // Best-effort
        }
        // Reset local state
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            self.machineState = "unknown"
            self.mPosX = 0.0; self.mPosY = 0.0; self.mPosZ = 0.0
            self.wPosX = 0.0; self.wPosY = 0.0; self.wPosZ = 0.0
        }
    }

    // MARK: - Command Sending

    public func sendCommand(_ command: String) async throws {
        guard isConnected else {
            throw MachineSessionError.notConnected
        }
        // SPK-1401c: append '\n' if missing (never double-terminate) so every
        // GRBL command line carries its line terminator.
        let data = GCodeLine.sending(command).data(using: .utf8) ?? Data()
        try await transport?.write(data)
    }

    // MARK: - Streamer access

    private var streamer: GCodeStreamer?

    /// Attach a streamer to this session for hold/resume/reset coordination.
    public func attachStreamer(_ streamer: GCodeStreamer) {
        self.streamer = streamer
    }
}

// MARK: - Errors

public enum MachineSessionError: LocalizedError {
    case notConnected
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a machine"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        }
    }
}
