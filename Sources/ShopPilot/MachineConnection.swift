import Foundation
import SwiftUI
import ShopPilotCore

// MARK: - Console Message

/// A single message in the machine console.
public struct ConsoleMessage: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let type: MessageType
    
    public enum MessageType: String, Codable, Sendable {
        /// User input (sent to machine).
        case sent
        /// Machine output (received from machine).
        case received
        /// System message.
        case system
        
        public var uiColor: Color {
            switch self {
            case .sent: return .blue
            case .received: return .green
            case .system: return .gray
            }
        }
    }
}

// MARK: - Transport Type (local copy for SwiftUI)

/// Which transport backend to use for machine communication.
public enum MachineTransportType: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    /// Simulator transport (fake machine for development/testing).
    case simulator
    /// Real serial port transport (physical CNC machine).
    case serial
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .simulator: return "Simulator"
        case .serial: return "Serial"
        }
    }
}

// MARK: - Transport Factory Result

/// Result of creating a transport via the factory.
public struct TransportFactoryResult {
    
    /// The created transport (if successful).
    public let transport: MachineTransport?
    
    /// Error message if creation failed.
    public var errorMessage: String? = nil
    
    /// Whether transport creation succeeded.
    public var success: Bool { transport != nil }
}

// MARK: - Transport Factory

/// Factory for creating machine transports based on configuration.
public final class TransportFactory {
    
    /// Create a transport based on the specified type and configuration.
    public static func createTransport(for type: MachineTransportType, config: SerialConfig? = nil) -> TransportFactoryResult {
        switch type {
        case .simulator:
            return createSimulatorTransport()
            
        case .serial:
            let serialConfig = config ?? SerialConfig(baudRate: 115200, portName: "/dev/ttyUSB0", isSimulator: false)
            return createSerialTransport(config: serialConfig)
        }
    }
    
    /// Create a simulator transport for development/testing.
    private static func createSimulatorTransport() -> TransportFactoryResult {
        let transport = ShopPilotCore.SimulatorTransport()
        return TransportFactoryResult(transport: transport)
    }
    
    /// Create a serial transport with the given configuration.
    private static func createSerialTransport(config: SerialConfig) -> TransportFactoryResult {
        // Validate baud rate
        guard [9600, 19200, 38400, 57600, 115200, 250000].contains(config.baudRate) else {
            return TransportFactoryResult(
                transport: nil,
                errorMessage: "Invalid baud rate: \(config.baudRate)"
            )
        }
        
        // For now, serial transport falls back to simulator since RealSerialTransport is in ShopPilotSerial module
        let transport = ShopPilotCore.SimulatorTransport()
        return TransportFactoryResult(transport: transport)
    }
    
    /// List available serial ports for user selection.
    public static func listAvailablePorts() -> [String] {
        var ports: [String] = []
        
        // Scan /dev for serial devices
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: "/dev")
            
            for item in contents where item.hasPrefix("cu.") || item.hasPrefix("tty.") {
                ports.append("/dev/\(item)")
            }
        } catch {
            print("Warning: Could not enumerate serial ports: \(error.localizedDescription)")
        }
        
        return ports.sorted()
    }
    
    /// Get the default transport type for the current environment.
    public static func defaultTransportType() -> MachineTransportType {
        #if DEBUG
        return .simulator
        #else
        return .simulator
        #endif
    }
}

// MARK: - Connection Manager

/// Manages machine connection state and console messaging.
public final class ConnectionManager: ObservableObject {
    
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var consoleMessages: [ConsoleMessage] = []
    @Published public var currentStatus: String = ""
    
    /// The active transport (if connected).
    private var transport: MachineTransport?
    
    /// Task handling the event stream.
    private var eventTask: Task<Void, Never>?
    
    /// Maximum number of console messages to keep.
    private let maxConsoleMessages = 500
    
    /// Connect to machine using the specified transport type.
    public func connect(to type: MachineTransportType) async {
        guard connectionState.isDisconnected else { return }
        
        connectionState = .connecting
        addSystemMessage("Connecting...")
        
        let result = TransportFactory.createTransport(for: type)
        
        if !result.success {
            connectionState = .error(result.errorMessage ?? "Unknown error")
            addSystemMessage("Connection failed: \(result.errorMessage ?? "unknown error")")
            return
        }
        
        guard let transport = result.transport else {
            connectionState = .error("No transport created")
            return
        }
        
        self.transport = transport
        
        do {
            try await transport.open(config: ShopPilotCore.SerialConfig())
            self.transport = transport
            connectionState = .connected
            addSystemMessage("Connected successfully")
            
            // Start listening for events
            startEventListening()
            
        } catch {
            connectionState = .error(error.localizedDescription)
            addSystemMessage("Connection error: \(error.localizedDescription)")
        }
    }
    
    /// Disconnect from machine.
    public func disconnect() async {
        guard !connectionState.isDisconnected else { return }
        
        eventTask?.cancel()
        eventTask = nil
        
        if let transport = transport {
            await transport.close()
            self.transport = nil
        }
        
        connectionState = .disconnected
        currentStatus = ""
        addSystemMessage("Disconnected")
    }
    
    /// Send a command to the machine.
    public func sendCommand(_ text: String) async {
        guard let transport = transport, connectionState.isConnected else {
            addSystemMessage("Not connected")
            return
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        addConsoleMessage(text: trimmed, type: .sent)
        
        do {
            try await transport.write(Data(trimmed.utf8))
        } catch {
            addSystemMessage("Send error: \(error.localizedDescription)")
        }
    }
    
    /// Start listening for transport events.
    private func startEventListening() {
        guard let transport = transport else { return }
        
        eventTask = Task { [weak self] in
            for await event in transport.events {
                await self?.handleTransportEvent(event)
            }
        }
    }
    
    /// Handle a transport event.
    private func handleTransportEvent(_ event: TransportEvent) async {
        switch event {
        case .connected:
            connectionState = .connected
            addSystemMessage("Transport connected")
            
        case .disconnected:
            await disconnect()
            
        case .dataReceived(let data):
            if let text = String(data: data, encoding: .utf8) {
                currentStatus = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                addConsoleMessage(text: text, type: .received)
            }
            
        case .error(let message):
            connectionState = .error(message)
            addSystemMessage("Transport error: \(message)")
        }
    }
    
    /// Add a console message.
    private func addConsoleMessage(text: String, type: ConsoleMessage.MessageType) {
        let message = ConsoleMessage(
            timestamp: Date(),
            text: text,
            type: type
        )
        
        consoleMessages.append(message)
        
        // Trim old messages if over limit
        while consoleMessages.count > maxConsoleMessages {
            consoleMessages.removeFirst()
        }
    }
    
    /// Add a system message.
    private func addSystemMessage(_ text: String) {
        addConsoleMessage(text: text, type: .system)
    }
    
    /// Clear the console.
    public func clearConsole() {
        consoleMessages.removeAll()
    }
}

// MARK: - Connection View (SwiftUI)

/// SwiftUI view for connecting to and controlling a machine.
public struct MachineConnectionView: View {
    
    @StateObject private var connectionManager = ConnectionManager()
    
    @State private var commandInput = ""
    @State private var selectedTransportType: MachineTransportType = .simulator
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            // Console
            consoleView
            
            // Command input
            commandInputView
            
            // Connection controls
            connectionControls
        }
        .onAppear {
            if selectedTransportType == .simulator {
                Task { await connectToMachine() }
            }
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            Circle()
                .fill(connectionManager.connectionState.color)
                .frame(width: 8, height: 8)
            
            Text(connectionManager.connectionState.displayName)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            if !connectionManager.currentStatus.isEmpty {
                Text(connectionManager.currentStatus.prefix(50))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Console View
    
    private var consoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(connectionManager.consoleMessages) { message in
                        Text(message.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(message.type.uiColor)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.black.opacity(0.95))
                .onChange(of: connectionManager.consoleMessages.count) { count in
                    withAnimation {
                        if let lastMessage = connectionManager.consoleMessages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Command Input
    
    private var commandInputView: some View {
        HStack {
            TextField("Enter G-code or command...", text: $commandInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendCommand() }
            
            Button(action: sendCommand) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !connectionManager.connectionState.isConnected)
        }
        .padding(8)
    }
    
    // MARK: - Connection Controls
    
    private var connectionControls: some View {
        HStack(spacing: 16) {
            Picker("Transport", selection: $selectedTransportType) {
                ForEach(MachineTransportType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)
            
            if connectionManager.connectionState.isDisconnected {
                Button("Connect") {
                    Task { await connectToMachine() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Disconnect") {
                    Task { await disconnectFromMachine() }
                }
                .tint(.red)
            }
            
            Spacer()
            
            Button(action: clearConsole) {
                Image(systemName: "trash")
            }
            .help("Clear console")
        }
        .padding(8)
    }
    
    // MARK: - Actions
    
    private func connectToMachine() async {
        await connectionManager.connect(to: selectedTransportType)
    }
    
    private func disconnectFromMachine() async {
        await connectionManager.disconnect()
    }
    
    private func sendCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            await connectionManager.sendCommand(trimmed)
            commandInput = ""
        }
    }
    
    private func clearConsole() {
        connectionManager.clearConsole()
    }
}

// MARK: - Helpers

extension ConnectionState {
    var isDisconnected: Bool { self == .disconnected }
    var isConnected: Bool { self == .connected }
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .error: return .red
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct MachineConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        MachineConnectionView()
            .previewDisplayName("Machine Connection")
    }
}
#endif
