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

    /// SPK-1506 — one factory: the UI-facing enum maps to the Core
    /// `TransportType` consumed by `ShopPilotCore.TransportFactory`
    /// (the duplicate app-side factory was deleted).
    public var coreType: TransportType {
        switch self {
        case .simulator: return .simulator
        case .serial: return .serial
        }
    }
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
    public func connect(to type: MachineTransportType, serialConfig: ShopPilotCore.SerialConfig? = nil) async {
        guard connectionState.isDisconnected else { return }

        // SPK-DOGFOOD-02 — a previous session's event task may still be
        // draining its (now-finished) stream; cancel it before opening so
        // exactly one event loop exists per connection and the old loop can
        // never interleave with the new one during reconnect.
        eventTask?.cancel()
        eventTask = nil

        connectionState = .connecting
        addSystemMessage("Connecting...")

        // SPK-1401a: the config the factory validates must be the SAME one
        // handed to open(config:) — the UI's port/baud were being discarded
        // here by opening with a fresh default `SerialConfig()`.
        let effectiveConfig = serialConfig ?? ShopPilotCore.SerialConfig()

        // SPK-1506 — one factory: the Core TransportFactory (which validates
        // baud, uses the App-registered serialTransportBuilder for real
        // serial, and SimulatorTransport for sim). The app-side duplicate
        // was deleted.
        let result = ShopPilotCore.TransportFactory.createTransport(
            for: type.coreType,
            config: effectiveConfig
        )
        
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
            try await transport.open(config: effectiveConfig)
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
            // SPK-1401c: GRBL only executes a line once its '\n' terminator
            // arrives — guarantee it on every command written.
            try await transport.write(Data(GCodeLine.sending(trimmed).utf8))
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
    ///
    /// SPK-DOGFOOD-02 — this MUST stay `@MainActor`. The handler writes
    /// `@Published` properties (`connectionState`, `currentStatus`), and a
    /// Combine send from a BACKGROUND cooperative thread runs the SwiftUI
    /// observers synchronously on that thread: it takes the AttributeGraph
    /// lock off-main while the main thread can simultaneously hold that lock
    /// inside its own view update and wait on the same publisher's unfair
    /// lock — an ABBA deadlock observed as a permanent "Connecting…" hang
    /// with 0% CPU after Disconnect→Reconnect (dogfood beachball). Hopping
    /// every event onto the main actor serializes all publishes with view
    /// updates; identical-value guards above keep the cost trivial.
    @MainActor
    private func handleTransportEvent(_ event: TransportEvent) async {
        switch event {
        case .connected:
            connectionState = .connected
            addSystemMessage("Transport connected")

        case .disconnected:
            await disconnect()

        case .dataReceived(let data):
            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // SPK-DOGFOOD-02 — the 500ms status poller delivers an
                // identical report most ticks; writing it back anyway fires
                // objectWillChange and rebuilds every observer of this
                // manager (the whole Machine stage) twice a second. Only
                // publish when the report actually changed.
                if trimmed != currentStatus {
                    currentStatus = trimmed
                }
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

    /// App-lifetime machine owner. The stage renders and commands it but never
    /// owns it, so navigating away no longer drops the connection or the job.
    @ObservedObject private var controller: MachineController

    /// Console log and streamer are observed directly so their published
    /// changes redraw this view.
    @ObservedObject private var connectionManager: ConnectionManager
    @ObservedObject private var streamer: GCodeStreamer

    @State private var commandInput = ""
    @State private var showRawTXRX = false

    /// Optional G-code lines from the Cut/Preview stages (session golden path).
    private let pendingGCode: [String]

    /// SPK-1920g — asks the session to generate the wasteboard surfacing op
    /// as an explicit Cut-tree node (never auto-runs; Run Job is the only path
    /// to motion, per the safety non-negotiables).
    private let onSurfaceWasteboard: () -> Void
    
    private let preflightItems: [PreFlightItem] = [
        PreFlightItem(title: "Work zero set", description: "Confirm X/Y/Z work coordinates are correct"),
        PreFlightItem(title: "Z0 = material surface confirmed", description: "Confirm Z0 sits on the material surface and the XY datum matches the job setup (FM-09 → R016)"),
        PreFlightItem(title: "Tool loaded", description: "Verify correct tool is in spindle"),
        PreFlightItem(title: "Material secured", description: "Check material is clamped and level"),
        PreFlightItem(title: "Clear workspace", description: "Ensure no obstructions near machine"),
        PreFlightItem(title: "G-code verified", description: "Preview toolpath before running")
    ]
    
    // MARK: - Pre-flight Actions

    /// Operator confirmation lives on the controller so it survives a stage
    /// change mid-job.
    private var preflightPassed: Bool { controller.preflightPassed }

    /// Mark all preflight items as passed.
    private func markPreflightPassed() {
        withAnimation(SP.Motion.state) {
            controller.preflightPassed = true
        }
    }
    
    /// Reset the preflight checklist.
    private func resetPreflight() {
        withAnimation(SP.Motion.state) {
            controller.preflightPassed = false
        }
    }

    public init(pendingGCode: [String] = [], controller: MachineController,
                simTravelLimitMM: Double? = nil,
                onSurfaceWasteboard: (() -> Void)? = nil) {
        self.pendingGCode = pendingGCode
        self.controller = controller
        self.onSurfaceWasteboard = onSurfaceWasteboard ?? {}
        self.connectionManager = controller.connection
        self.streamer = controller.streamer
        // SPK-1509 — the stage hands the profile's travel envelope to the
        // controller before Connect so the sim soft limit matches the
        // configured machine (nil keeps the controller's 500 default).
        if let simTravelLimitMM {
            controller.simTravelLimitMM = simTravelLimitMM
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Machine state + connect/disconnect — the first thing read.
            machineHeader

            // Safety chrome sits directly under the state, above everything
            // else on the stage (Safety Req #1: never buried).
            safetyChrome

            // SPK-1800g: large Machine DRO — X/Y/Z from parsed mPos.
            machineDRO

            Divider()

            // Stream progress (visible when streaming)
            streamProgress

            // Pre-flight checklist / armed Run CTA
            preflightChecklist

            // Jog + Home + Work Zero controls
            jogControls

            // SPK-1302/1303/1304 — live run controls: feed override,
            // spindle on/off, touch-off probing, work-offset switching.
            runControlsPanel

            Divider()

            // Console
            consoleView

            // Command input
            commandInputView
        }
        .task { controller.loadPendingGCode(pendingGCode) }
        // NOTE: No auto-connect on appear. Safety Req #9: never auto-connect
        // or auto-run on application launch. User must explicitly press Connect.
        //
        // There is deliberately no `onDisappear` teardown: the connection and
        // any running job outlive this view, and the chrome must keep telling
        // the truth about the machine after the operator leaves the stage.
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

            // SPK-2022d — one pick sets baud + post + travel + origin. An
            // unknown machine lands on Generic GRBL; the fallback never
            // blocks connect. Disabled while live, like the other pickers.
            Picker("Machine", selection: Binding(
                get: {
                    controller.deviceProfileID.isEmpty
                        ? DeviceProfileCatalog.genericID
                        : controller.deviceProfileID
                },
                set: { controller.selectDeviceProfile(id: $0) }
            )) {
                ForEach(DeviceProfileCatalog.bundled) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)
            .help("Device profile — one choice sets baud, post, travel and work-origin convention")

            Picker("Transport", selection: $controller.transportType) {
                ForEach(MachineTransportType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)

            // SPK-1324 — when Serial is selected, pick the actual port +
            // baud instead of the factory's hardcoded /dev/ttyUSB0 default.
            if controller.transportType == .serial {
                Picker("Port", selection: $controller.serialPortName) {
                    ForEach(ShopPilotCore.TransportFactory.listAvailablePorts(), id: \.self) { port in
                        Text(port).tag(port)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
                .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)
                .help("USB serial port (auto-scanned from /dev)")

                Picker("Baud", selection: $controller.serialBaudRate) {
                    ForEach(MachineController.validBaudRates, id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
                .disabled(connectionManager.connectionState.isConnected || connectionManager.connectionState == .connecting)
                .help("Serial baud rate (GRBL: 115200)")
            }

            if connectionManager.connectionState.isDisconnected {
                Button {
                    Task { await controller.connect() }
                } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .help("Open the port — no motion happens until you press Run")
            } else {
                Button {
                    Task { await controller.disconnect() }
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

    /// Single source of truth, shared with the window chrome.
    private var chromeState: MachineChromeState { controller.chromeState }

    /// Second line under the state: the machine's own last report, or what is
    /// loaded and waiting.
    private var machineDetailLine: String {
        if let detail = chromeState.detail, !detail.isEmpty {
            return detail
        }
        if !connectionManager.currentStatus.isEmpty {
            return String(connectionManager.currentStatus.prefix(60))
        }
        if controller.machineSession.gcodeBuffer.isEmpty {
            return "No job loaded"
        }
        return "\(controller.machineSession.gcodeBuffer.count) lines ready"
    }
    
    // MARK: - Console View
    
    /// Console with optional raw TX/RX toggle (Safety Req #6).
    ///
    /// SPK-DOGFOOD-02 — the message list lives in `ConsoleLogView`, which
    /// observes the `ConsoleLog` directly. This outer view no longer reads
    /// `consoleLog.messages` (the previous `.onReceive($messages)` here
    /// invalidated the WHOLE Machine stage body — header, DRO, safety chrome,
    /// preflight, jog — on every 500ms poll append and re-diffed up to
    /// ConsoleLog.maxMessages rows each time; stacked on identical-status
    /// chrome writes it pinned the main thread at ~95% CPU). The toggle stays
    /// in this view: flipping it only re-renders this small row.
    private var consoleView: some View {
        ConsoleView(showRawTXRX: $showRawTXRX, connectionManager: connectionManager)
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
            if controller.isStreamingJob || streamer.state == .streaming || streamer.state == .paused {
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
                        Picker("", selection: $controller.jogStepSize) {
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

                    // SPK-2022d / §2.4 — soft-limit awareness. Known travel:
                    // warn BEFORE the proposed step leaves the envelope.
                    // Unknown travel keeps today's behavior but says so
                    // honestly instead of pretending it is safe.
                    let softLimitWarnings = SoftLimitAdvisor.warnings(
                        currentX: controller.machineSession.mPosX,
                        currentY: controller.machineSession.mPosY,
                        currentZ: controller.machineSession.mPosZ,
                        stepMm: controller.jogStepSize,
                        profile: controller.activeDeviceProfile)
                    if !softLimitWarnings.isEmpty {
                        Label(softLimitWarnings.joined(separator: " · "),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SP.Tint.hold)
                            .help("Proposed jog would leave the machine's known travel envelope")
                            .accessibilityLabel("Soft limit warning. \(softLimitWarnings.joined(separator: ". "))")
                    } else if let travelNotice = SoftLimitAdvisor.unknownTravelNotice(profile: controller.activeDeviceProfile) {
                        Label(travelNotice, systemImage: "questionmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(travelNotice)
                    }

                    // Stream controls. Starting a job lives with the pre-flight
                    // checklist above, so nothing here can begin motion.
                    if controller.isStreamingJob || streamer.state == .streaming {
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

    // MARK: - Run controls (SPK-1302/1303/1304 / 1503)

    /// Live machine controls that only make sense while connected: feed
    /// override, spindle on/off, touch-off probing, work-offset switching.
    /// SPK-1503 — the fine-tune cluster lives under one collapsed "More"
    /// disclosure (feed/spindle/probe/offsets are occasional), while Jog,
    /// Hold/Resume/Reset, Run/Stop and the alarm banner stay in the main
    /// chrome.
    private var runControlsPanel: some View {
        Group {
            if connectionManager.connectionState.isConnected {
                VStack(alignment: .leading, spacing: SP.Space.s) {
                    DisclosureGroup("More") {
                        // SPK-2022c — "bit already loaded": suppresses exactly
                        // the first M6 (+ immediate dwell) in the outgoing
                        // program at send time. Pure send-path filter; OFF
                        // restores the full program byte-for-byte.
                        Toggle(isOn: $controller.bitAlreadyLoaded) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Bit already loaded")
                                    .font(.caption.weight(.medium))
                                Text("Skip the first tool change (M6) + its dwell when sending this job")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Bit already loaded — skip first M6 at send")

                        // Feed override + spindle.
                        HStack(spacing: SP.Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Feed \(Int(controller.feedOverride.multiplier * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { controller.feedOverride.multiplier },
                                        set: { controller.feedOverride = FeedRateOverride(multiplier: $0) }
                                    ),
                                    in: 0.1...2.0
                                )
                                .frame(width: 160)
                                .help("Feed-rate override: 10%…200% (sends a scaled F word)")
                            }
                            Button("Apply") { controller.applyFeedOverride() }
                                .controlSize(.small)

                            Spacer()

                            Button("Spindle ON") { controller.spindleOn() }
                                .controlSize(.small)
                            Button("Spindle OFF") { controller.spindleOff() }
                                .controlSize(.small)
                        }

                        // Touch-off probe + work offsets.
                        HStack(spacing: SP.Space.m) {
                            Button {
                                controller.touchOffZ(plateThickness: 3.0)
                            } label: {
                                Label("Touch-Off (3mm plate)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            }
                            .controlSize(.small)
                            .help("Probe Z with a 3mm touch plate, then zero at the plate top")

                            // SPK-2022a — full XYZ plate probe wizard: three
                            // legs Z → X → Y, each committing its own G10 L20
                            // offset as it completes.
                            Button {
                                controller.touchOffXYZPlate(plateThickness: 3.0)
                            } label: {
                                Label("XYZ plate", systemImage: "axis.3d")
                            }
                            .controlSize(.small)
                            .help("Probe Z, then X, then Y against the 3mm touch plate — each axis's work offset commits as its leg completes")

                            // SPK-2022b — tool-length offset: after a tool
                            // change (M6), re-probe Z ONLY and commit
                            // G10 L20 P1 Z[t]; XY never moves.
                            Button {
                                controller.probeToolLengthOffset(toolNumber: 1, plateThickness: 3.0)
                            } label: {
                                Label("Tool length offset", systemImage: "wrench.and.screwdriver")
                            }
                            .controlSize(.small)
                            .help("Probe Z after tool change: send M6, re-probe Z against the 3mm touch plate, set G10 L20 P1 Z — XY work offsets stay untouched")

                            // SPK-1920g — wasteboard surfacing as an explicit
                            // Cut-tree op; Run Job discipline applies.
                            Button {
                                onSurfaceWasteboard()
                            } label: {
                                Label("Surface Wasteboard…", systemImage: "rectangle.compress.vertical")
                            }
                            .controlSize(.small)
                            .help("Generate a facing program for the spoilboard as a Cut operation — nothing runs until you press Run Job")

                            Spacer()

                            Picker("Offset", selection: Binding(
                                get: { controller.workOffsets.activeIndex },
                                set: { controller.selectWorkOffset($0) }
                            )) {
                                ForEach(Array(controller.workOffsets.offsets.enumerated()), id: \.element.id) { index, offset in
                                    Text("\(offset.name) (\(offset.gcode))").tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 150)
                            .help("Switch the active work offset (G54–G59)")
                        }
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

    // MARK: - Machine DRO (SPK-1800g)

    /// Large monospaced X Y Z readout from the parsed mPos status report.
    /// Updates when the simulator/controller reports `<Idle|MPos:…>`.
    private var machineDRO: some View {
        Group {
            if chromeState.isLive {
                VStack(spacing: 2) {
                    Text("MPos")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        droColumn("X", controller.machineSession.mPosX)
                        droColumn("Y", controller.machineSession.mPosY)
                        droColumn("Z", controller.machineSession.mPosZ)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func droColumn(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.3f", value))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 60)
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
            // Driven by the shared chrome state so a latched controller alarm
            // (ALARM:/error: on the wire, not just a transport failure) keeps
            // the safety controls on screen.
            if chromeState.isLive {
                HStack(spacing: SP.Space.s) {
                    SafetyButton(
                        title: "Hold",
                        subtitle: "Pause motion",
                        symbol: "pause.fill",
                        tint: SP.Tint.hold,
                        voiceOver: "Hold. Pause machine motion now",
                        action: holdMachine
                    )
                    // ⌘H/⌘R/⌘X are Hide, Refresh-ish and Edit ▸ Cut — the
                    // system wins those. Safety chords take Option as well.
                    .keyboardShortcut(KeyEquivalent("h"), modifiers: [.command, .option])

                    SafetyButton(
                        title: "Resume",
                        subtitle: "Continue the cut",
                        symbol: "play.fill",
                        tint: SP.Tint.running,
                        voiceOver: "Resume. Continue machine motion",
                        action: resumeMachine
                    )
                    .keyboardShortcut(KeyEquivalent("r"), modifiers: [.command, .option])

                    SafetyButton(
                        title: "Reset",
                        subtitle: "Stop and clear",
                        symbol: "arrow.counterclockwise",
                        tint: SP.Tint.safety,
                        voiceOver: "Reset. Stop the machine and clear the controller",
                        action: resetMachine
                    )
                    .keyboardShortcut(KeyEquivalent("x"), modifiers: [.command, .option])
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
                .background(
                    SP.Tint.safety.opacity(chromeState.detail == nil ? 0.0 : 0.10)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Not connected: state the software-only limit once, quietly.
                HStack(spacing: SP.Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Software Hold is a complement to, not a replacement for, your machine's hardware e-stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, SP.Space.m)
                .padding(.vertical, SP.Space.s)
            }
        }
        .animation(SP.Motion.state, value: chromeState)
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

    // Everything that talks to the machine lives on `MachineController` so it
    // outlives this view. These are thin forwarders for readability.

    private func holdMachine() { controller.hold() }
    private func resumeMachine() { controller.resume() }
    private func resetMachine() { controller.reset() }
    private func jogAxis(_ axis: String, direction: Int) { controller.jog(axis: axis, direction: direction) }
    private func softHomeAll() { controller.softHomeAll() }
    private func zeroXAxis() { controller.zeroAxis("X") }
    private func zeroYAxis() { controller.zeroAxis("Y") }
    private func zeroZAxis() { controller.zeroAxis("Z") }
    private func runJob() { controller.runJob(fallbackLines: pendingGCode) }
    private func stopStreaming() { controller.stopStreaming() }
    private func resumeStreaming() { controller.resumeStreaming() }
    private func clearConsole() { controller.clearConsole() }

    private func sendCommand() {
        controller.sendConsoleCommand(commandInput)
        commandInput = ""
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
        MachineConnectionView(controller: MachineController())
            .previewDisplayName("Machine Connection")
    }
}
#endif

// MARK: - SPK-DOGFOOD-02 — isolated console view

/// The machine console as its own observing view. Appends to the log only
/// invalidate this small subtree — the Machine stage body (header, DRO,
/// safety chrome, preflight, jog) no longer rebuilds on every 500ms poll
/// append, and the row ForEach diffs at most `visibleTail` rows instead of
/// the whole `ConsoleLog.maxMessages` buffer.
///
/// Raw traffic still renders with TX/RX labels (Safety Req #6); windowing
/// drops only the OLDEST rows off-screen history, never live traffic.
struct ConsoleView: View {
    @Binding var showRawTXRX: Bool
    @ObservedObject var connectionManager: ConnectionManager
    @ObservedObject private var log: ConsoleLog

    /// Rows SwiftUI diffs per append. Deep enough to fill the pane; small
    /// enough that a 2-per-second append cadence costs nothing.
    private let visibleTail = 80

    init(showRawTXRX: Binding<Bool>, connectionManager: ConnectionManager) {
        self._showRawTXRX = showRawTXRX
        self.connectionManager = connectionManager
        self.log = connectionManager.consoleLog
    }

    /// The last `visibleTail` messages — a stable slice, not the full buffer.
    private var tail: ArraySlice<ConsoleMessage> {
        let messages = log.messages
        guard messages.count > visibleTail else { return messages[...] }
        return messages[(messages.count - visibleTail)...]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SP.Space.s) {
                SectionLabel(showRawTXRX ? "Console — raw TX/RX" : "Console")

                Spacer()

                Toggle("Raw TX/RX", isOn: $showRawTXRX)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .font(.caption)
                    .help("Show every byte sent and received, for diagnosis")

                Button {
                    log.clear()
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
                        ForEach(Array(tail)) { message in
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
                }
                .onChange(of: log.messages.count) { _ in
                    withAnimation {
                        if let lastMessage = log.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
