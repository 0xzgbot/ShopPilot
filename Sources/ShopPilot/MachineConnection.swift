import Foundation
import Combine
import SwiftUI
import ShopPilotCore
import ShopPilotSerial

// MARK: - Console Message

/// Console message type + SwiftUI color (base type lives in ShopPilotCore —
/// SPK-UI601: message buffering moved to `ConsoleLog` for deadlock-free,
/// CLT-verifiable appends).
extension ConsoleMessage.ConsoleMessageType {
    public var uiColor: Color {
        switch self {
        case .sent: return .blue
        case .received: return .green
        case .system: return .gray
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
    /// Console messages are served from `consoleLog` (SPK-UI601). The view
    /// reads `consoleLog.messages` directly + observes `$messages` — there is
    /// deliberately NO mirror @Published here: a sink that re-publishes
    /// creates a nested send (log send -> sink -> this @Published send) that
    /// can contend with the streaming thread's own publishes and stall the
    /// main thread (observed mid-stream freeze, 2026-08-04).
    @Published public var currentStatus: String = ""

    /// Single chokepoint for console message appends (Core, deadlock-free).
    public let consoleLog: ConsoleLog = ConsoleLog()
    
    /// The active transport (if connected).
    var transport: MachineTransport?
    
    /// Task handling the event stream.
    private var eventTask: Task<Void, Never>?
    
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
    
    /// Add a console message. All appends are deferred to the main queue by
    /// ConsoleLog so a message arriving mid-Combine-send can never deadlock
    /// the main thread (SPK-UI601).
    private func addConsoleMessage(text: String, type: ConsoleMessage.ConsoleMessageType) {
        let message = ConsoleMessage(
            timestamp: Date(),
            text: text,
            type: type
        )
        consoleLog.append(message)
    }
    
    /// Add a system message (internal for SwiftUI view access).
    func addSystemMessage(_ text: String) {
        addConsoleMessage(text: text, type: .system)
    }
    
    /// Clear the console.
    public func clearConsole() {
        consoleLog.clear()
    }
}

// MARK: - Connection View (SwiftUI)

/// SwiftUI view for connecting to and controlling a machine.
public struct MachineConnectionView: View {
    
    @StateObject private var connectionManager = ConnectionManager()
    
    @State private var commandInput = ""
    @State private var selectedTransportType: MachineTransportType = .simulator
    @State private var jogStepSize: Double = 1.0
    @ObservedObject private var streamer = GCodeStreamer()
    @State private var isStreamingJob = false
    /// The running stream task — cancelled by Stop Stream. SPK-UI601: the
    /// stream loop only exits on cancellation (its ok-wait ignores non-ok
    /// text, so an alarm leaves it blocked; a bare streamer.reset() then
    /// unblocks it via the reset's "ok" and it writes the next buffered
    /// move, re-tripping the soft-limit alarm).
    @State private var jobTask: Task<Void, Never>?
    @State private var preflightPassed = false
    @State private var showRawTXRX = false
    @State private var softLimitWarning: String? = nil

    /// Optional G-code lines from the Cut/Preview stages (session golden path).
    private let pendingGCode: [String]

    /// Window-chrome bridge: state out, Hold/Reset back in. Optional so the
    /// view stays usable standalone (previews, verifiers).
    private let chrome: MachineChromeLink?
    
    /// MachineSession facade for hold/resume/reset and buffer loading.
    @State private var machineSession = MachineSession()
    
    /// Load pending G-code into MachineSession when the view appears.
    private func loadPendingGCode() {
        if !pendingGCode.isEmpty {
            machineSession.loadGCode(pendingGCode)
            connectionManager.addSystemMessage("Loaded \(pendingGCode.count) G-code lines into session buffer")
        }
    }
    
    private let preflightItems: [PreFlightItem] = [
        PreFlightItem(title: "Work zero set", description: "Confirm X/Y/Z work coordinates are correct"),
        PreFlightItem(title: "Z0 = material surface confirmed", description: "Confirm Z0 sits on the material surface and the XY datum matches the job setup (FM-09 → R016)"),
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
    
    /// Reset preflight after a completed stream.
    private func resetPreflightAfterStream() {
        withAnimation {
            preflightPassed = false
        }
    }
    
    public init(pendingGCode: [String] = [], chrome: MachineChromeLink? = nil) {
        self.pendingGCode = pendingGCode
        self.chrome = chrome
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Machine state + connect/disconnect — the first thing read.
            machineHeader

            // Safety chrome sits directly under the state, above everything
            // else on the stage (Safety Req #1: never buried).
            safetyChrome

            Divider()

            // Stream progress (visible when streaming)
            streamProgress

            // Pre-flight checklist / armed Run CTA
            preflightChecklist

            // Jog + Home + Work Zero controls
            jogControls

            Divider()

            // Console
            consoleView

            // Command input
            commandInputView
        }
        .task { loadPendingGCode() }
        .onAppear { registerChromeHandlers() }
        .onDisappear { chrome?.state = .offline }
        .onChange(of: connectionManager.connectionState) { _ in publishChromeState() }
        .onChange(of: streamer.state) { _ in publishChromeState() }
        .onChange(of: streamer.progress) { _ in publishChromeState() }
        // NOTE: No auto-connect on appear. Safety Req #9: never auto-connect
        // or auto-run on application launch. User must explicitly press Connect.
    }

    // MARK: - Window chrome bridge

    /// Hand the window chrome its Hold/Reset actions so the safety controls
    /// keep working from anywhere in the app.
    private func registerChromeHandlers() {
        chrome?.onHold = holdMachine
        chrome?.onResume = resumeMachine
        chrome?.onReset = resetMachine
        publishChromeState()
    }

    /// Mirror connection + streamer state into the glanceable chrome state.
    private func publishChromeState() {
        guard let chrome else { return }
        switch connectionManager.connectionState {
        case .disconnected:
            chrome.state = .offline
        case .connecting:
            chrome.state = .connecting
        case .error(let message):
            chrome.state = .alarm(message)
        case .connected:
            switch streamer.state {
            case .streaming:
                chrome.state = .running(progress: streamer.progress)
            case .paused:
                chrome.state = .hold
            default:
                chrome.state = .idle
            }
        }
    }

    // MARK: - Machine Header

    /// Connection state, transport choice and connect/disconnect in one row.
    /// The state text is the largest thing on the stage after the safety
    /// buttons, so machine condition is readable across a shop.
    private var machineHeader: some View {
        HStack(spacing: SP.Space.m) {
            HStack(spacing: SP.Space.s) {
                Image(systemName: chromeState.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(chromeState.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(chromeState.label)
                        .font(.system(size: 15, weight: .semibold))

                    Text(machineDetailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Machine state: \(chromeState.label). \(machineDetailLine)")

            Spacer(minLength: SP.Space.m)

            Picker("Transport", selection: $selectedTransportType) {
                ForEach(MachineTransportType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)

            if connectionManager.connectionState.isDisconnected {
                Button {
                    Task { await connectToMachine() }
                } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .help("Open the port — no motion happens until you press Run")
            } else {
                Button {
                    Task { await disconnectFromMachine() }
                } label: {
                    Label("Disconnect", systemImage: "cable.connector.slash")
                }
                .buttonStyle(.bordered)
                .help("Close the port and stop talking to the machine")
            }
        }
        .padding(.horizontal, SP.Space.m)
        .frame(height: 52)
        .background(.bar)
    }

    /// Local mirror of the chrome state so the header can render it even when
    /// no `MachineChromeLink` was supplied.
    private var chromeState: MachineChromeState {
        switch connectionManager.connectionState {
        case .disconnected: return .offline
        case .connecting: return .connecting
        case .error(let message): return .alarm(message)
        case .connected:
            switch streamer.state {
            case .streaming: return .running(progress: streamer.progress)
            case .paused: return .hold
            default: return .idle
            }
        }
    }

    /// Second line under the state: the machine's own last report, or what is
    /// loaded and waiting.
    private var machineDetailLine: String {
        if let detail = chromeState.detail, !detail.isEmpty {
            return detail
        }
        if !connectionManager.currentStatus.isEmpty {
            return String(connectionManager.currentStatus.prefix(60))
        }
        if machineSession.gcodeBuffer.isEmpty {
            return "No job loaded"
        }
        return "\(machineSession.gcodeBuffer.count) lines ready"
    }
    
    // MARK: - Console View
    
    /// Console with optional raw TX/RX toggle (Safety Req #6).
    private var consoleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Console header — raw TX/RX and clear live here so the toggle sits
            // with the log it changes (Safety Req #6).
            HStack(spacing: SP.Space.s) {
                SectionLabel(showRawTXRX ? "Console — raw TX/RX" : "Console")

                Spacer()

                Toggle("Raw TX/RX", isOn: $showRawTXRX)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .font(.caption)
                    .help("Show every byte sent and received, for diagnosis")

                Button {
                    clearConsole()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Clear console")
                .accessibilityLabel("Clear console")
            }
            .padding(.horizontal, SP.Space.m)
            .frame(height: 26)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(connectionManager.consoleLog.messages)) { message in
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
                    .onChange(of: connectionManager.consoleLog.messages.count) { count in
                        withAnimation {
                            if let lastMessage = connectionManager.consoleLog.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    // SPK-UI601: re-render when the (deferred) log appends land.
                    // Observing the log directly avoids a mirror @Published.
                    .onReceive(connectionManager.consoleLog.$messages) { _ in }
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
    
    // MARK: - Stream Progress
    
    /// Progress bar shown while streaming a G-code job.
    private var streamProgress: some View {
        Group {
            if isStreamingJob || streamer.state == .streaming || streamer.state == .paused {
                VStack(spacing: SP.Space.xs) {
                    HStack {
                        Text(streamer.state == .paused ? "Held — motion paused" : "Running")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(streamer.state == .paused ? SP.Tint.hold : .primary)
                        
                        Spacer()
                        
                        Text("\(streamer.currentLine)/\(streamer.totalLines)")
                            .font(SP.Typography.dro)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: streamer.progress)
                        .tint(streamer.state == .paused ? SP.Tint.hold : .accentColor)
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
                .transition(.opacity)
            }
        }
        .animation(SP.Motion.state, value: streamer.state)
    }
    
    // MARK: - Pre-flight Checklist
    
    /// Checklist shown before allowing stream to start.
    private var preflightChecklist: some View {
        Group {
            if connectionManager.connectionState.isConnected && !preflightPassed {
                VStack(alignment: .leading, spacing: SP.Space.s) {
                    SectionLabel("Before you run")

                    ForEach(Array(preflightItems), id: \.id) { item in
                        PreFlightRow(item: item, passed: preflightPassed)
                    }

                    // Run stays unavailable — and looks it — until the operator
                    // confirms the checklist.
                    HStack(spacing: SP.Space.s) {
                        Button(action: markPreflightPassed) {
                            Label("I've checked all of these", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel("Confirm pre-flight checklist")

                        Button {
                            runJob()
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(true)
                        .help("Confirm the checklist first")
                        .accessibilityLabel("Run. Unavailable until the pre-flight checklist is confirmed")
                    }
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
            } else if preflightPassed {
                HStack(spacing: SP.Space.m) {
                    Button(action: runJob) {
                        Label("Run Job", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SP.Tint.running)
                    .controlSize(.large)
                    .accessibilityLabel("Run job. Start cutting")

                    Button("Re-check", action: resetPreflight)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .help("Clear the pre-flight confirmation")
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
            }
        }
        .animation(SP.Motion.state, value: preflightPassed)
    }
    
    // MARK: - Pre-flight Row Subview
    
    /// Individual row in the pre-flight checklist.
    private struct PreFlightRow: View {
        let item: PreFlightItem
        let passed: Bool
        
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: SP.Space.s) {
                Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(passed ? AnyShapeStyle(SP.Tint.running) : AnyShapeStyle(.tertiary))
                    .font(.system(size: 11))

                Text(item.title)
                    .font(.caption.weight(.medium))
                    .frame(width: 180, alignment: .leading)

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title). \(item.description)")
        }
    }
    
    // MARK: - Jog Controls
    
    /// Step sizes for jogging.
    private let jogStepSizes: [Double] = [10.0, 1.0, 0.1, 0.01]
    
    private var jogControls: some View {
        Group {
            if connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting {
                VStack(alignment: .leading, spacing: SP.Space.s) {
                    HStack {
                        SectionLabel("Jog")
                        Spacer()
                        Picker("", selection: $jogStepSize) {
                            ForEach(jogStepSizes, id: \.self) { size in
                                Text(stepLabel(size)).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 230)
                        .help("Distance each jog press moves the machine")
                    }

                    HStack(alignment: .top, spacing: SP.Space.l) {
                        // X/Y pad — arrows sit where the axes point.
                        Grid(horizontalSpacing: SP.Space.xs, verticalSpacing: SP.Space.xs) {
                            GridRow {
                                Color.clear.frame(width: 40, height: 34)
                                JogButton(symbol: "arrow.up", voiceOver: "Jog Y plus", action: { jogAxis("Y", direction: 1) })
                                Color.clear.frame(width: 40, height: 34)
                            }
                            GridRow {
                                JogButton(symbol: "arrow.left", voiceOver: "Jog X minus", action: { jogAxis("X", direction: -1) })
                                JogButton(symbol: "house.fill", tint: SP.Tint.hold, voiceOver: "Home all axes", action: softHomeAll)
                                JogButton(symbol: "arrow.right", voiceOver: "Jog X plus", action: { jogAxis("X", direction: 1) })
                            }
                            GridRow {
                                Color.clear.frame(width: 40, height: 34)
                                JogButton(symbol: "arrow.down", voiceOver: "Jog Y minus", action: { jogAxis("Y", direction: -1) })
                                Color.clear.frame(width: 40, height: 34)
                            }
                        }

                        VStack(spacing: SP.Space.xs) {
                            Text("Z")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            JogButton(symbol: "arrow.up", voiceOver: "Jog Z up", action: { jogAxis("Z", direction: 1) })
                            JogButton(symbol: "arrow.down", voiceOver: "Jog Z down", action: { jogAxis("Z", direction: -1) })
                        }

                        VStack(alignment: .leading, spacing: SP.Space.xs) {
                            Text("Set work zero here")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: SP.Space.xs) {
                                Button("X", action: zeroXAxis)
                                    .accessibilityLabel("Set work zero X")
                                Button("Y", action: zeroYAxis)
                                    .accessibilityLabel("Set work zero Y")
                                Button("Z", action: zeroZAxis)
                                    .accessibilityLabel("Set work zero Z")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }

                        Spacer(minLength: 0)
                    }
                    
                    // Stream controls. Starting a job lives with the pre-flight
                    // checklist above, so nothing here can begin motion.
                    if isStreamingJob || streamer.state == .streaming {
                        Button(action: stopStreaming) {
                            Label("Stop Stream", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(SP.Tint.safety)
                        .help("Stop sending the job — the controller keeps its current state")
                        .accessibilityLabel("Stop stream. Stop sending the job")
                    } else if streamer.state == .paused {
                        Button(action: resumeStreaming) {
                            Label("Resume Stream", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(SP.Tint.hold)
                        .accessibilityLabel("Resume stream. Continue sending the job")
                    }
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
            }
        }
    }

    /// Short label for a jog step, so "0.01 mm" doesn't render as "0.010000".
    private func stepLabel(_ size: Double) -> String {
        size >= 1 ? String(format: "%.0f mm", size) : String(format: "%g mm", size)
    }

    // MARK: - Jog Button

    /// A single jog target. Large enough to hit with gloves on.
    private struct JogButton: View {
        let symbol: String
        var tint: Color = .accentColor
        let voiceOver: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 40, height: 34)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .accessibilityLabel(voiceOver)
        }
    }
    
    // MARK: - Safety Chrome
    
    /// Always-visible safety controls (Hold/Resume/Reset) shown when connected,
    /// connecting, or in alarm. These are the largest hit targets on the stage
    /// — sized for gloves and shop lighting, not for a mouse in an office.
    private var safetyChrome: some View {
        Group {
            if connectionManager.connectionState.isConnected
                || connectionManager.connectionState == .connecting
                || connectionManager.connectionState.isInAlarm
            {
                HStack(spacing: SP.Space.s) {
                    SafetyButton(
                        title: "Hold",
                        subtitle: "Pause motion",
                        symbol: "pause.fill",
                        tint: SP.Tint.hold,
                        voiceOver: "Hold. Pause machine motion now",
                        action: holdMachine
                    )
                    .keyboardShortcut(KeyEquivalent("h"), modifiers: .command)

                    SafetyButton(
                        title: "Resume",
                        subtitle: "Continue the cut",
                        symbol: "play.fill",
                        tint: SP.Tint.running,
                        voiceOver: "Resume. Continue machine motion",
                        action: resumeMachine
                    )
                    .keyboardShortcut(KeyEquivalent("r"), modifiers: .command)

                    SafetyButton(
                        title: "Reset",
                        subtitle: "Stop and clear",
                        symbol: "arrow.counterclockwise",
                        tint: SP.Tint.safety,
                        voiceOver: "Reset. Stop the machine and clear the controller",
                        action: resetMachine
                    )
                    .keyboardShortcut(KeyEquivalent("x"), modifiers: .command)
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
                .background(
                    SP.Tint.safety.opacity(connectionManager.connectionState.isInAlarm ? 0.10 : 0.0)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Not connected: state the software-only limit once, quietly.
                HStack(spacing: SP.Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Software Hold is not a substitute for your machine's hardware e-stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
            }
        }
        .animation(SP.Motion.state, value: connectionManager.connectionState)
    }

    // MARK: - Safety Button

    /// One shop-floor safety control: big target, verb first, plain-English
    /// second line, VoiceOver label that says what it does to the machine.
    private struct SafetyButton: View {
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let voiceOver: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: SP.Space.s) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(subtitle)
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .controlSize(.large)
            .help("\(title) — \(subtitle.lowercased())")
            .accessibilityLabel(voiceOver)
        }
    }
    
    // MARK: - Actions
    
    private func connectToMachine() async {
        await connectionManager.connect(to: selectedTransportType)
        // Wire up MachineSession transport after connection so hold/resume/reset
        // realtime commands (!, ~, 0x18) reach the connected transport.
        if let transport = connectionManager.transport, connectionManager.connectionState == .connected {
            machineSession.connectionState = connectionManager.connectionState
            machineSession.attach(transport: transport)
            machineSession.attachStreamer(streamer)
        }
    }
    
    private func disconnectFromMachine() async {
        await connectionManager.disconnect()
        // ConnectionManager owns the transport lifecycle — session detaches
        // (no double-close) and resets its own state.
        machineSession.detach()
    }
    
    /// Send GRBL hold command (pause machine motion) via MachineSession.
    private func holdMachine() {
        Task {
            await machineSession.hold()
            await streamer.pause()
            connectionManager.addSystemMessage("Hold sent — machine paused")
        }
    }
    
    /// Resume a held machine via MachineSession.
    private func resumeMachine() {
        Task {
            await machineSession.resume()
            await streamer.resume()
            connectionManager.addSystemMessage("Resume sent — machine resuming")
        }
    }
    
    /// Send GRBL reset command (clear alarms, return to idle) via MachineSession.
    private func resetMachine() {
        Task {
            await machineSession.reset()
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
    
    /// Run the job (preflight CTA). Uses MachineSession buffer when available,
    /// otherwise falls back to file-based streaming.
    private func runJob() {
        if !machineSession.gcodeBuffer.isEmpty {
            jobTask = Task { await runJobFromSession() }
        } else {
            jobTask = Task { await streamJobFromFile() }
        }
    }
    
    /// Stream G-code from the MachineSession buffer via the connected transport.
    private func runJobFromSession() async {
        guard let transport = connectionManager.transport else {
            connectionManager.addSystemMessage("Error: Not connected")
            return
        }
        
        isStreamingJob = true
        await streamer.reset()
        machineSession.attachStreamer(streamer)
        
        do {
            connectionManager.addSystemMessage("Streaming \(machineSession.gcodeBuffer.count) lines from session buffer")
            try await streamer.stream(lines: machineSession.gcodeBuffer, to: transport)
            await MainActor.run {
                isStreamingJob = false
                preflightPassed = false
            }
            if !Task.isCancelled {
                connectionManager.addSystemMessage("Stream complete — \(streamer.currentLine) lines")
            }
        } catch {
            await MainActor.run {
                isStreamingJob = false
                preflightPassed = false
            }
            connectionManager.addSystemMessage("Stream error: \(error.localizedDescription)")
        }
    }
    
    /// Open file picker and stream selected G-code job.
    private func streamJobFromFile() async {
        isStreamingJob = true
        
        // Check for recent export files from CutToMachineBridge first,
        // then fall back to user-saved jobs in Documents, then demo G-code.
        let bridgeExportURLs = findRecentBridgeExports()
        let sessionLines = pendingGCode
        
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
                    await MainActor.run {
                        isStreamingJob = false
                        preflightPassed = false
                    }
                    return
                }
                
                // Stream the G-code lines to the machine via the active transport.
                // In production, this path receives output from CutToMachineBridge.export()
                // which post-processes toolpath results using the machine profile's auto-selected
                // post processor type (GRBL vs universal) before writing to file.
                try await streamer.stream(lines: lines, to: transport)
                await MainActor.run {
                    isStreamingJob = false
                    preflightPassed = false
                }
                if !Task.isCancelled {
                    connectionManager.addSystemMessage("Stream complete — \(streamer.currentLine) lines")
                }
            } catch {
                await MainActor.run {
                    isStreamingJob = false
                    preflightPassed = false
                }
                connectionManager.addSystemMessage("Stream error: \(error.localizedDescription)")
            }
    }
    
    /// Stream G-code from the MachineSession buffer (called from the "Run Job" button).
    private func streamJob() async {
        if !machineSession.gcodeBuffer.isEmpty {
            await runJobFromSession()
        } else {
            await streamJobFromFile()
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
            
            // Step 2: Load into MachineSession buffer (primary handoff path)
            guard let outputFileURL = result.outputFileURL,
                  FileManager.default.fileExists(atPath: outputFileURL.path) else {
                await MainActor.run {
                    isStreamingJob = false
                    preflightPassed = false
                }
                connectionManager.addSystemMessage("Error: Exported file not found")
                return
            }
            
            let lines = try await streamer.load(from: outputFileURL)
            machineSession.loadGCode(lines)
            connectionManager.addSystemMessage("Loaded \(lines.count) lines into MachineSession buffer")
            
            // Step 3: Stream if connected
            guard let transport = connectionManager.transport else {
                await MainActor.run {
                    isStreamingJob = false
                    preflightPassed = false
                }
                connectionManager.addSystemMessage("Not connected — G-code loaded into buffer for later use")
                return
            }
            
            machineSession.attachStreamer(streamer)
            try await streamer.stream(lines: lines, to: transport)
            await MainActor.run {
                isStreamingJob = false
                preflightPassed = false
            }
            
            // Step 4: Update result with actual streamed line count
            connectionManager.addSystemMessage("Stream complete — \(streamer.currentLine) lines")
            
        } catch {
            await MainActor.run {
                isStreamingJob = false
                preflightPassed = false
            }
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
        // SPK-UI601: cancel the stream task FIRST — the stream loop only
        // stops on cancellation; without it, streamer.reset()'s "ok" unblocks
        // the alarm-stalled ok-wait and the loop writes the next buffered
        // move, re-tripping the soft-limit alarm.
        jobTask?.cancel()
        jobTask = nil
        Task {
            await streamer.reset()
            await MainActor.run {
                isStreamingJob = false
                preflightPassed = false
            }
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
