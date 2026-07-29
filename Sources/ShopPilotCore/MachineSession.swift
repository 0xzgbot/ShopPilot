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
    private var statusPollTask: Task<Void, Never>?

    // MARK: - Computed Properties

    public var isConnected: Bool { connectionState == .connected }

    // MARK: - Lifecycle

    public init() {}

    deinit {
        statusPollTask?.cancel()
    }

    // MARK: - Connection Management

    public func connect(transport: MachineTransport) async throws {
        guard !isConnected else { return }

        self.transport = transport
        connectionState = .connecting

        do {
            try await transport.open(config: SerialConfig())
            connectionState = .connected
            startStatusPolling(transport: transport)
        } catch {
            connectionState = .error(error.localizedDescription)
            self.transport = nil
            throw error
        }
    }

    public func disconnect() async {
        statusPollTask?.cancel()
        statusPollTask = nil
        await transport?.close()
        transport = nil
        connectionState = .disconnected
        machineState = "unknown"
        mPosX = 0.0; mPosY = 0.0; mPosZ = 0.0
        wPosX = 0.0; wPosY = 0.0; wPosZ = 0.0
    }

    // MARK: - Status Polling

    private func startStatusPolling(transport: MachineTransport) {
        statusPollTask = Task { [weak self] in
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
    }

    // MARK: - Command Sending

    public func sendCommand(_ command: String) async throws {
        guard isConnected else {
            throw MachineSessionError.notConnected
        }
        let data = (command + "\n").data(using: .utf8) ?? Data()
        try await transport?.write(data)
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
