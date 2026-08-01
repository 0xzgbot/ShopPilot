import Foundation
import SwiftUI
import ShopPilotCore
import ShopPilotSerial

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

// MARK: - Pre-flight Checklist Item

/// A single item in the pre-flight checklist.
public struct PreFlightItem: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let description: String
    
    public static func == (lhs: PreFlightItem, rhs: PreFlightItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transport Factory

/// Factory for creating machine transports based on configuration.
public final class TransportFactory {
    
    /// Create a transport based on the specified type and configuration.
    public static func createTransport(for type: MachineTransportType, config: ShopPilotCore.SerialConfig? = nil) -> TransportFactoryResult {
        switch type {
        case .simulator:
            return createSimulatorTransport()
            
        case .serial:
            let serialConfig = config ?? ShopPilotCore.SerialConfig(baudRate: 115200, portName: "/dev/ttyUSB0", isSimulator: false)
            return createSerialTransport(config: serialConfig)
        }
    }
    
    /// Create a simulator transport for development/testing.
    private static func createSimulatorTransport() -> TransportFactoryResult {
        let transport = ShopPilotCore.SimulatorTransport()
        return TransportFactoryResult(transport: transport)
    }
    
    /// Create a serial transport with the given configuration.
    private static func createSerialTransport(config: ShopPilotCore.SerialConfig) -> TransportFactoryResult {
        // Validate baud rate
        guard [9600, 19200, 38400, 57600, 115200, 250000].contains(config.baudRate) else {
            return TransportFactoryResult(
                transport: nil,
                errorMessage: "Invalid baud rate: \(config.baudRate)"
            )
        }
        
        // Real serial transport (IOKit / FileHandle). Never auto-connect on launch.
        let transport = RealSerialTransport()
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
    var transport: MachineTransport?
    
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
    
    /// Add a system message (internal for SwiftUI view access).
    func addSystemMessage(_ text: String) {
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
    @State private var jogStepSize: Double = 1.0
    @State private var streamer = GCodeStreamer()
    @State private var isStreamingJob = false
    @State private var preflightPassed = false
    @State private var showRawTXRX = false
    @State private var softLimitWarning: String? = nil

    /// Optional G-code lines from the Cut/Preview stages (session golden path).
    private let pendingGCode: [String]
    
    private let preflightItems: [PreFlightItem] = [
        PreFlightItem(title: "Work zero set", description: "Confirm X/Y/Z work coordinates are correct"),
        PreFlightItem(title: "Tool loaded", description: "Verify correct tool is in spindle"),
        PreFlightItem(title: "Material secured", description: "Check material is clamped and level"),
        PreFlightItem(title: "Clear workspace", description: "Ensure no obstructions near machine"),
        PreFlightItem(title: "G-code verified", description: "Preview toolpath before running")
    ]
    
    // MARK: - Pre-flight Actions
    
    /// Mark all preflight items as passed.
    private func markPreflightPassed() {
        withAnimation {
            preflightPassed = true
        }
    }
    
    /// Reset the preflight checklist.
    private func resetPreflight() {
        withAnimation {
            preflightPassed = false
        }
    }
    
    public init(pendingGCode: [String] = []) {
        self.pendingGCode = pendingGCode
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            // Console
            consoleView
            
            // Command input
            commandInputView
            
            // Stream progress (visible when streaming)
            streamProgress
            
            // Connection controls
            connectionControls
            
            // Safety chrome (always visible when connected)
            safetyChrome
            
            // Jog + Home + Work Zero controls
            jogControls
            
            // Pre-flight checklist (shown when connected, before streaming)
            preflightChecklist
        }
        // NOTE: No auto-connect on appear. Safety Req #9: never auto-connect
        // or auto-run on application launch. User must explicitly press Connect.
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
    
    /// Console with optional raw TX/RX toggle (Safety Req #6).
    private var consoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Raw TX/RX toggle bar (Safety Req #6)
            if showRawTXRX {
                HStack {
                    Text("Raw TX/RX mode — shows all raw serial data")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Spacer()
                    Button(action: { withAnimation { showRawTXRX = false } }) {
                        Text("Hide")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(4)
                .background(Color.orange.opacity(0.1))
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(connectionManager.consoleMessages) { message in
                            // In raw mode, show sent/received with TX/RX labels
                            if showRawTXRX && (message.type == .sent || message.type == .received) {
                                let label = message.type == .sent ? "TX: " : "RX: "
                                HStack(alignment: .top, spacing: 4) {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundColor(message.type == .sent ? .blue : .green)
                                        .lineLimit(1)
                                    Text(message.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(message.type.uiColor)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(message.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(message.type.uiColor)
                                    .lineLimit(1)
                            }
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
            
            // Raw TX/RX toggle (Safety Req #6)
            Button(action: { withAnimation { showRawTXRX.toggle() } }) {
                Text(showRawTXRX ? "Hide TX/RX" : "Show TX/RX")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .help("Toggle raw TX/RX console mode for diagnosis")
            
            Button(action: clearConsole) {
                Image(systemName: "trash")
            }
            .help("Clear console")
        }
        .padding(8)
    }
    
    // MARK: - Stream Progress
    
    /// Progress bar shown while streaming a G-code job.
    private var streamProgress: some View {
        Group {
            if isStreamingJob || streamer.state == .streaming || streamer.state == .paused {
                VStack(spacing: 4) {
                    HStack {
                        Text(streamer.state == .paused ? "Paused" : "Streaming")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(streamer.currentLine)/\(streamer.totalLines)")
                            .font(.caption2.monospacedDigit())
                    }
                    
                    ProgressView(value: streamer.progress)
                        .tint(streamer.state == .paused ? .orange : .blue)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Pre-flight Checklist
    
    /// Checklist shown before allowing stream to start.
    private var preflightChecklist: some View {
        Group {
            if connectionManager.connectionState.isConnected && !preflightPassed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pre-Flight Checklist")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    
                    ForEach(Array(preflightItems), id: \.id) { item in
                        PreFlightRow(item: item, passed: preflightPassed)
                    }
                    
                    Button(action: markPreflightPassed) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("I've Verified All Items — Ready to Run")
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            } else if preflightPassed {
                VStack(spacing: 8) {
                    // One-click Run CTA (armed state)
                    Button(action: runJob) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.title2)
                            Text("RUN")
                                .font(.title3.bold())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.extraLarge)
                    
                    HStack {
                        Text("Pre-flight passed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: resetPreflight) {
                            Text("Reset Checklist")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
            }
        }
    }
    
    // MARK: - Pre-flight Row Subview
    
    /// Individual row in the pre-flight checklist.
    private struct PreFlightRow: View {
        let item: PreFlightItem
        let passed: Bool
        
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(passed ? .green : .secondary)
                    .font(.caption2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption2.bold())
                    
                    Text(item.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Jog Controls
    
    /// Step sizes for jogging.
    private let jogStepSizes: [Double] = [10.0, 1.0, 0.1, 0.01]
    
    private var jogControls: some View {
        Group {
            if connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting {
                VStack(spacing: 8) {
                    // Jog step size selector
                    HStack {
                        Text("Step:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $jogStepSize) {
                            ForEach(jogStepSizes, id: \.self) { size in
                                Text("\(size) mm").tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    
                    // Jog pad (X/Y plane + Z up/down)
                    HStack(spacing: 8) {
                        // Left column: Y- / Y+
                        VStack(spacing: 4) {
                            Button(action: { jogAxis("Y", direction: 1) }) {
                                Image(systemName: "arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                            
                            Button(action: { jogAxis("Y", direction: -1) }) {
                                Image(systemName: "arrow.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                        }
                        
                        // Center column: X- / X+ with Home
                        VStack(spacing: 4) {
                            Button(action: { jogAxis("X", direction: -1) }) {
                                Image(systemName: "arrow.left")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                            
                            // Soft home button (G28)
                            Button(action: softHomeAll) {
                                Image(systemName: "house.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                            
                            Button(action: { jogAxis("X", direction: 1) }) {
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                        }
                        
                        // Right column: Z- / Z+
                        VStack(spacing: 4) {
                            Button(action: { jogAxis("Z", direction: -1) }) {
                                Image(systemName: "arrow.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                            
                            Button(action: { jogAxis("Z", direction: 1) }) {
                                Image(systemName: "arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                    }
                    
                    // Work zero buttons (G92 / G10)
                    HStack(spacing: 8) {
                        Button(action: zeroXAxis) {
                            Text("Zero X")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: zeroYAxis) {
                            Text("Zero Y")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: zeroZAxis) {
                            Text("Zero Z")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Stream job button (when connected, not already streaming)
                    if connectionManager.connectionState.isConnected && !isStreamingJob {
                        Button(action: streamJobFromFile) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Stream Job from File")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if isStreamingJob || streamer.state == .streaming {
                        Button(action: stopStreaming) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop Stream")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else if streamer.state == .paused {
                        Button(action: resumeStreaming) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Resume Stream")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Safety Chrome
    
    /// Always-visible safety controls (Hold/Reset) shown when connected, connecting, or in alarm.
    private var safetyChrome: some View {
        Group {
            if connectionManager.connectionState.isConnected
                || connectionManager.connectionState == .connecting
                || connectionManager.connectionState.isInAlarm
            {
                HStack(spacing: 12) {
                    // Hold button — pauses machine motion
                    Button(action: holdMachine) {
                        VStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .font(.title2)
                            Text("Hold")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .keyboardShortcut(KeyEquivalent("h"), modifiers: .command)
                    
                    // Reset button — clears alarms and resets state
                    Button(action: resetMachine) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                            Text("Reset")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .keyboardShortcut(KeyEquivalent("r"), modifiers: .command)
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Actions
    
    private func connectToMachine() async {
        await connectionManager.connect(to: selectedTransportType)
    }
    
    private func disconnectFromMachine() async {
        await connectionManager.disconnect()
    }
    
    /// Send GRBL hold command (pause machine motion).
    private func holdMachine() {
        Task {
            await connectionManager.sendCommand("!") // GRBL hold (exclamation mark)
            connectionManager.addSystemMessage("Hold sent — machine paused")
        }
    }
    
    /// Send GRBL reset command (clear alarms, return to idle).
    private func resetMachine() {
        Task {
            let resetCmd = "\u{18}" // GRBL reset (Ctrl+X)
            await connectionManager.sendCommand(resetCmd)
            connectionManager.addSystemMessage("Reset sent — machine cleared")
        }
    }
    
    // MARK: - Jog Actions
    
    /// Send a jog move command to the specified axis.
    private func jogAxis(_ axis: String, direction: Int) {
        let distance = Double(direction) * jogStepSize
        let cmd = "G91 G0 \(axis)\(String(format: "%.3f", distance))" // Relative rapid move
        Task {
            await connectionManager.sendCommand(cmd)
            connectionManager.addSystemMessage("Jog \(axis) \(direction > 0 ? "+" : "")\(distance)mm")
        }
    }
    
    /// Send soft home command (G28 — return all axes to machine zero).
    private func softHomeAll() {
        Task {
            await connectionManager.sendCommand("G28")
            connectionManager.addSystemMessage("Soft home sent — G28")
        }
    }
    
    // MARK: - Work Zero Actions
    
    /// Set work coordinate X to current position (G92 X0).
    private func zeroXAxis() {
        Task {
            await connectionManager.sendCommand("G92 X0")
            connectionManager.addSystemMessage("Work zero set — X=0")
        }
    }
    
    /// Set work coordinate Y to current position (G92 Y0).
    private func zeroYAxis() {
        Task {
            await connectionManager.sendCommand("G92 Y0")
            connectionManager.addSystemMessage("Work zero set — Y=0")
        }
    }
    
    /// Set work coordinate Z to current position (G92 Z0).
    private func zeroZAxis() {
        Task {
            await connectionManager.sendCommand("G92 Z0")
            connectionManager.addSystemMessage("Work zero set — Z=0")
        }
    }
    
    // MARK: - Stream Job Actions
    
    /// Run the job (one-click CTA after preflight passes).
    private func runJob() {
        streamJobFromFile()
    }
    
    /// Open file picker and stream selected G-code job.
    private func streamJobFromFile() {
        isStreamingJob = true
        
        // Check for recent export files from CutToMachineBridge first,
        // then fall back to user-saved jobs in Documents, then demo G-code.
        let bridgeExportURLs = findRecentBridgeExports()
        let sessionLines = pendingGCode
        
        Task {
            do {
                var lines: [String]
                
                if !sessionLines.isEmpty {
                    connectionManager.addSystemMessage("Using session toolpath (\(sessionLines.count) lines)")
                    lines = sessionLines
                } else if !bridgeExportURLs.isEmpty {
                    // Use the most recent bridge export (Cut stage output)
                    let latestURL = bridgeExportURLs[0]
                    connectionManager.addSystemMessage("Using exported toolpath: \(latestURL.lastPathComponent)")
                    lines = try await streamer.load(from: latestURL)
                } else {
                    // Fall back to user-saved job file
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let gcodeFileURL = documentsURL.appendingPathComponent("job.gcode")
                    
                    if FileManager.default.fileExists(atPath: gcodeFileURL.path) {
                        lines = try await streamer.load(from: gcodeFileURL)
                    } else {
                        // Create demo G-code for testing
                        let demoGcode = """
                        ; Demo G-code file
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
                        try demoGcode.write(to: gcodeFileURL, atomically: true, encoding: .utf8)
                        lines = try await streamer.load(from: gcodeFileURL)
                    }
                }
                
                guard let transport = connectionManager.transport else {
                    isStreamingJob = false
                    return
                }
                
                // Stream the G-code lines to the machine via the active transport.
                // In production, this path receives output from CutToMachineBridge.export()
                // which post-processes toolpath results using the machine profile's auto-selected
                // post processor type (GRBL vs universal) before writing to file.
                try await streamer.stream(lines: lines, to: transport)
                isStreamingJob = false
                connectionManager.addSystemMessage("Stream complete — \(streamer.currentLine) lines")
            } catch {
                isStreamingJob = false
                connectionManager.addSystemMessage("Stream error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Find recent export files from CutToMachineBridge (sorted newest first).
    private func findRecentBridgeExports() -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ShopPilotExports")
        guard FileManager.default.fileExists(atPath: tempDir.path) else { return [] }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            
            // Filter for .gcode and .nc files, sort by modification date (newest first)
            return files
                .filter { $0.pathExtension == "gcode" || $0.pathExtension == "nc" }
                .sorted { urlA, urlB in
                    let dateA = (try? urlA.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let dateB = (try? urlB.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return dateA > dateB
                }
        } catch {
            connectionManager.addSystemMessage("Warning: Could not scan for bridge exports")
            return []
        }
    }
    
    /// Export toolpath results via CutToMachineBridge and stream to the connected machine.
    /// This is the primary handoff path from Cut stage → Machine stage.
    public func exportAndStream(
        gcodeLines: [String],
        toolInfo: String?,
        machineProfile: MachineProfile,
        fileName: String = "job"
    ) async {
        isStreamingJob = true
        
        do {
            // Step 1: Post-process and export via the bridge
            let result = try await CutToMachineBridge.export(
                gcodeLines: gcodeLines,
                toolInfo: toolInfo,
                machineProfile: machineProfile,
                fileName: fileName
            )
            
            connectionManager.addSystemMessage("Exported \(result.postProcessorType.displayName) G-code → \(result.outputFileURL?.lastPathComponent ?? "unknown")")
            
            guard let transport = connectionManager.transport else {
                isStreamingJob = false
                connectionManager.addSystemMessage("Error: Not connected to machine")
                return
            }
            
            // Step 2: Load and stream the exported file
            guard let outputFileURL = result.outputFileURL,
                  FileManager.default.fileExists(atPath: outputFileURL.path) else {
                isStreamingJob = false
                connectionManager.addSystemMessage("Error: Exported file not found")
                return
            }
            
            let lines = try await streamer.load(from: outputFileURL)
            try await streamer.stream(lines: lines, to: transport)
            
            // Step 3: Update result with actual streamed line count
            connectionManager.addSystemMessage("Stream complete — \(streamer.currentLine) lines")
            
        } catch {
            isStreamingJob = false
            connectionManager.addSystemMessage("Export/stream error: \(error.localizedDescription)")
        }
    }
    
    /// Pause the current stream.
    private func pauseStreaming() {
        Task {
            await streamer.pause()
            connectionManager.addSystemMessage("Stream paused")
        }
    }
    
    /// Resume a paused stream.
    private func resumeStreaming() {
        Task {
            await streamer.resume()
            connectionManager.addSystemMessage("Stream resumed")
        }
    }
    
    /// Stop and reset the current stream.
    private func stopStreaming() {
        Task {
            await streamer.reset()
            isStreamingJob = false
            connectionManager.addSystemMessage("Stream stopped")
        }
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
    var isInAlarm: Bool {
        if case .error = self { return true }
        return false
    }
    
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
