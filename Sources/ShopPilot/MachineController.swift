import Foundation
import Combine
import SwiftUI
import ShopPilotCore

/// App-lifetime owner of everything that talks to the machine.
///
/// The Machine stage used to own the `ConnectionManager`, `GCodeStreamer` and
/// `MachineSession` as view state, so navigating away from the stage tore down
/// the connection, cancelled a running job and left the window chrome with no
/// working Hold or Reset. Ownership lives here instead: the stage is now a view
/// over shared state, and Safety Req #1 (Hold and Reset always reachable while
/// connected) holds from anywhere in the app.
///
/// All published mutation happens on the main queue; the transport's own
/// threading is unchanged.
public final class MachineController: ObservableObject {

    // MARK: - Owned machine objects

    /// Transport lifecycle + console log.
    public let connection = ConnectionManager()

    /// Line-by-line streamer. Its task survives stage changes.
    public let streamer = GCodeStreamer()

    /// Realtime command facade (hold `!`, resume `~`, reset `0x18`) and the
    /// loaded G-code buffer.
    public let machineSession = MachineSession()

    // MARK: - Published chrome + operator state

    /// Glanceable state for the window chrome and the Machine stage header.
    @Published public private(set) var chromeState: MachineChromeState = .offline

    /// Transport choice. Lives here so it survives navigation.
    @Published public var transportType: MachineTransportType = .simulator

    /// SPK-1324 — serial port + baud for the Serial transport (the UI picker
    /// writes these; connect() threads them into the transport factory).
    @Published public var serialPortName: String = "/dev/cu.usbmodem"
    @Published public var serialBaudRate: Int = 115200
    public static let validBaudRates = [9600, 19200, 38400, 57600, 115200, 250000]

    /// SPK-1509 — simulator soft-limit envelope (mm), sourced from the active
    /// MachineProfile's travel (the Machine stage sets it before Connect).
    /// Defaults to the legacy 500mm envelope.
    @Published public var simTravelLimitMM: Double = 500

    /// Jog step in millimetres.
    @Published public var jogStepSize: Double = 1.0

    /// Operator has confirmed the pre-flight checklist. Never auto-set.
    @Published public var preflightPassed = false

    /// A job is being streamed (or is winding down after cancellation).
    @Published public private(set) var isStreamingJob = false

    /// Latched controller fault. GRBL reports an alarm once and then goes back
    /// to emitting ordinary status lines, so the alarm is held until the
    /// operator presses Reset or reconnects — it must not quietly disappear.
    @Published public private(set) var latchedAlarm: String?

    // MARK: - Private state

    /// The running stream task — cancelled by Stop Stream. SPK-UI601: the
    /// stream loop only exits on cancellation (its ok-wait ignores non-ok
    /// text, so an alarm leaves it blocked; a bare streamer.reset() then
    /// unblocks it via the reset's "ok" and it writes the next buffered
    /// move, re-tripping the soft-limit alarm).
    private var jobTask: Task<Void, Never>?

    /// Identity of the G-code last pushed into the buffer, so re-entering the
    /// Machine stage doesn't reload the same job over and over.
    private var loadedGCodeSignature: String?

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        observeMachineState()
    }

    // MARK: - State derivation

    /// Recompute chrome state whenever the transport, streamer or controller
    /// output changes.
    private func observeMachineState() {
        connection.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeChromeState() }
            .store(in: &cancellables)

        // Real controller faults arrive as ordinary received text ("ALARM:1",
        // "error:9"), not as a transport-level error, so the status line is
        // scanned as well.
        connection.$currentStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.noteControllerOutput(status)
                self?.recomputeChromeState()
            }
            .store(in: &cancellables)

        streamer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeChromeState() }
            .store(in: &cancellables)

        streamer.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeChromeState() }
            .store(in: &cancellables)

        streamer.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error, !error.isEmpty {
                    self?.latchedAlarm = error
                }
                self?.recomputeChromeState()
            }
            .store(in: &cancellables)
    }

    /// Latch a controller alarm or error out of raw machine output.
    private func noteControllerOutput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let upper = trimmed.uppercased()

        if upper.contains("ALARM") {
            latchedAlarm = plainAlarmText(trimmed)
        } else if upper.hasPrefix("ERROR:") {
            latchedAlarm = plainAlarmText(trimmed)
        }
    }

    /// Shop-floor phrasing for a raw controller code.
    private func plainAlarmText(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        if cleaned.uppercased().contains("ALARM") {
            return "Machine alarm — \(cleaned). Motion stopped; press Reset to clear."
        }
        return "Machine rejected a command — \(cleaned)."
    }

    private func recomputeChromeState() {
        chromeState = derivedChromeState()
    }

    private func derivedChromeState() -> MachineChromeState {
        switch connection.connectionState {
        case .disconnected:
            return .offline
        case .connecting:
            return .connecting
        case .error(let message):
            return .alarm(message)
        case .connected:
            if let latchedAlarm {
                return .alarm(latchedAlarm)
            }
            switch streamer.state {
            case .streaming:
                return .running(progress: streamer.progress)
            case .paused:
                return .hold
            default:
                return .idle
            }
        }
    }

    // MARK: - Connection

    public func connect() async {
        latchedAlarm = nil
        let serialConfig: ShopPilotCore.SerialConfig?
        switch transportType {
        case .serial:
            serialConfig = ShopPilotCore.SerialConfig(baudRate: serialBaudRate, portName: serialPortName, isSimulator: false)
        case .simulator:
            // SPK-1509 — the simulator's soft limit follows the active
            // MachineProfile's travel (set by the Machine stage before
            // Connect); nil would keep the legacy 500mm envelope.
            serialConfig = ShopPilotCore.SerialConfig(
                isSimulator: true,
                travelLimitMM: simTravelLimitMM
            )
        }
        await connection.connect(to: transportType, serialConfig: serialConfig)
        // Wire up MachineSession transport after connection so hold/resume/reset
        // realtime commands (!, ~, 0x18) reach the connected transport.
        if let transport = connection.transport, connection.connectionState == .connected {
            machineSession.connectionState = connection.connectionState
            machineSession.attach(transport: transport)
            machineSession.attachStreamer(streamer)
        }
        recomputeChromeState()
    }

    public func disconnect() async {
        // Safety Req #3: a job must never keep streaming into a closed port.
        stopStreaming()
        await connection.disconnect()
        // ConnectionManager owns the transport lifecycle — session detaches
        // (no double-close) and resets its own state.
        machineSession.detach()
        preflightPassed = false
        latchedAlarm = nil
        recomputeChromeState()
    }

    // MARK: - Safety actions

    /// Hold: pause motion. Reachable from the window chrome on any stage.
    /// Single realtime writer (SPK-1401e): the session owns the transport —
    /// it writes the one `!` and pauses the attached streamer's loop. The
    /// controller no longer calls streamer.pause() (which would put a
    /// second `!` on the wire).
    public func hold() {
        Task {
            await machineSession.hold()
            connection.addSystemMessage("Hold sent — machine paused")
        }
    }

    /// Resume a held machine.
    public func resume() {
        Task {
            await machineSession.resume()
            connection.addSystemMessage("Resume sent — machine resuming")
        }
    }

    /// Reset: stop the controller and clear alarms.
    public func reset() {
        // Cancel the stream first — the loop only exits on cancellation, and a
        // bare reset's "ok" would otherwise unblock it into the next move.
        jobTask?.cancel()
        jobTask = nil
        Task {
            await machineSession.reset()
            await MainActor.run {
                self.isStreamingJob = false
                self.preflightPassed = false
                self.latchedAlarm = nil
                self.recomputeChromeState()
            }
            connection.addSystemMessage("Reset sent — machine cleared")
        }
    }

    // MARK: - Jog / zero

    public func jog(axis: String, direction: Int) {
        let distance = Double(direction) * jogStepSize
        // SPK-1401c: relative rapid move, then restore absolute mode so the
        // machine does not stay in G91 after jogging.
        let lines = JogCommandFormatter.lines(axis: axis, distanceMm: distance)
        Task {
            for line in lines {
                await connection.sendCommand(line)
            }
            connection.addSystemMessage("Jog \(axis) \(direction > 0 ? "+" : "")\(distance)mm")
        }
    }

    /// Home all axes — GRBL homing cycle (`$H`), not a soft G28 return.
    /// SPK-1608: $H runs the machine's homing switches so the controller
    /// knows true machine zero; G28 only returned to the previous zero
    /// without homing. Requires the machine to be idle + not in alarm.
    public func softHomeAll() {
        Task {
            await connection.sendCommand("$H")
            connection.addSystemMessage("Homing sent — $H (wait for the machine to finish)")
        }
    }

    /// Set the work zero for one axis at the current position (G92).
    public func zeroAxis(_ axis: String) {
        Task {
            await connection.sendCommand("G92 \(axis)0")
            connection.addSystemMessage("Work zero set — \(axis)=0")
        }
    }

    // MARK: - Run controls (SPK-1302)

    /// Live feed-rate override — sends a new F word (GRBL feed override
    /// approach). 100% = multiplier 1.0; range 10%…200%.
    @Published public var feedOverride = FeedRateOverride()

    /// Current spindle RPM for the M3/S commands.
    @Published public var spindleRPM: Double = 12000

    /// Apply the current feed override to the NEXT cut feed... The override
    /// is a modal F word, so this targets the streamer's current feed by
    /// re-emitting it scaled (the streamer sends it before the next move).
    public func applyFeedOverride() {
        Task {
            await connection.sendCommand(feedOverride.gcode(feed: 600))
            connection.addSystemMessage("Feed override → \(Int(feedOverride.multiplier * 100))%")
        }
    }

    /// Spindle on (M3 S<rpm>) / off (M5).
    public func spindleOn() {
        Task {
            await connection.sendCommand(SpindleCommand.on(rpm: spindleRPM))
            connection.addSystemMessage("Spindle ON — \(SpindleCommand.on(rpm: spindleRPM))")
        }
    }

    public func spindleOff() {
        Task {
            await connection.sendCommand(SpindleCommand.off())
            connection.addSystemMessage("Spindle OFF — M5")
        }
    }

    // MARK: - Touch-off probing (SPK-1303)

    /// Run the touch-off probe sequence at the current XY. After the probe
    /// hits, compute + apply the Z work offset so the stock surface reads 0.
    public func touchOffZ(plateThickness: Double = 3.0) {
        let plan = TouchOff.plan(plateThickness: plateThickness)
        let sequence = TouchOff.gcode(plan)
        Task {
            for line in sequence {
                await connection.sendCommand(line)
            }
            connection.addSystemMessage("Touch-off probe sent (plate \(plateThickness)mm) — set Z zero at the plate top")
        }
    }

    /// The Z work offset math for a reported probe hit (used after a manual
    /// or auto probe to display the computed offset).
    public func computedZOffset(probeHitZ: Double, plateThickness: Double) -> Double {
        TouchOff.zOffset(probeHitZ: probeHitZ, plateThickness: plateThickness)
    }

    // MARK: - Work offsets (SPK-1304)

    /// The G54–G59 registry for this machine session.
    @Published public var workOffsets = WorkOffsetRegistry()

    /// Switch the active work offset (G54…G59) on the controller.
    public func selectWorkOffset(_ index: Int) {
        guard workOffsets.setActive(index) else { return }
        Task {
            await connection.sendCommand(workOffsets.activeGcode)
            connection.addSystemMessage("Work offset → \(workOffsets.active.name) (\(workOffsets.activeGcode))")
        }
    }

    // MARK: - Console

    public func sendConsoleCommand(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await connection.sendCommand(trimmed) }
    }

    public func clearConsole() {
        connection.clearConsole()
    }

    // MARK: - G-code buffer

    /// Push toolpath G-code from the Cut stage into the machine buffer. Loading
    /// is idempotent and never happens mid-stream.
    public func loadPendingGCode(_ lines: [String]) {
        guard !lines.isEmpty, !isStreamingJob else { return }
        let signature = "\(lines.count):\(lines.first ?? "")|\(lines.last ?? "")"
        guard signature != loadedGCodeSignature else { return }

        loadedGCodeSignature = signature
        machineSession.loadGCode(lines)
        connection.addSystemMessage("Loaded \(lines.count) G-code lines into session buffer")
    }

    // MARK: - Streaming

    /// Start the job. Only ever called from the armed pre-flight CTA —
    /// Safety Req #2: nothing starts motion on open or on connect.
    public func runJob(fallbackLines: [String]) {
        guard !isStreamingJob else { return }
        jobTask = Task { [weak self] in
            guard let self else { return }
            if !self.machineSession.gcodeBuffer.isEmpty {
                await self.streamSessionBuffer()
            } else {
                await self.streamFallback(lines: fallbackLines)
            }
        }
    }

    private func streamSessionBuffer() async {
        guard let transport = connection.transport else {
            connection.addSystemMessage("Error: Not connected")
            return
        }

        await MainActor.run { self.isStreamingJob = true }
        // SPK-1504 — Start must NOT write GRBL reset (0x18): a fresh job
        // starts by streaming, not by resetting the controller. State-only
        // reset clears progress/line counters without touching the wire.
        streamer.resetStreamState()
        machineSession.attachStreamer(streamer)

        do {
            connection.addSystemMessage("Streaming \(machineSession.gcodeBuffer.count) lines from session buffer")
            try await streamer.stream(lines: machineSession.gcodeBuffer, to: transport)
            await finishStream(message: Task.isCancelled ? nil : "Stream complete — \(streamer.currentLine) lines")
        } catch {
            await finishStream(message: "Stream error: \(error.localizedDescription)")
        }
    }

    private func streamFallback(lines: [String]) async {
        await MainActor.run { self.isStreamingJob = true }

        guard let transport = connection.transport else {
            await finishStream(message: "Not connected — nothing streamed")
            return
        }

        // SPK-1504 — the fallback path must attach the streamer exactly like
        // the buffer path: Hold/Reset route through MachineSession →
        // streamer coordination, so a fallback stream without an attached
        // streamer would break single-writer realtime (1401e).
        streamer.resetStreamState()
        machineSession.attachStreamer(streamer)

        let resolved: [String]
        if !lines.isEmpty {
            connection.addSystemMessage("Using session toolpath (\(lines.count) lines)")
            resolved = lines
        } else if let exportURL = mostRecentBridgeExport() {
            connection.addSystemMessage("Using exported toolpath: \(exportURL.lastPathComponent)")
            do {
                resolved = try await streamer.load(from: exportURL)
            } catch {
                await finishStream(message: "Stream error: \(error.localizedDescription)")
                return
            }
        } else {
            await finishStream(message: "No G-code to run — generate a toolpath in Cut first")
            return
        }

        do {
            try await streamer.stream(lines: resolved, to: transport)
            await finishStream(message: Task.isCancelled ? nil : "Stream complete — \(streamer.currentLine) lines")
        } catch {
            await finishStream(message: "Stream error: \(error.localizedDescription)")
        }
    }

    /// Clear streaming state and re-arm the checklist for the next run.
    private func finishStream(message: String?) async {
        await MainActor.run {
            self.isStreamingJob = false
            self.preflightPassed = false
            self.recomputeChromeState()
        }
        if let message {
            connection.addSystemMessage(message)
        }
    }

    /// Stop and reset the current stream.
    public func stopStreaming() {
        // SPK-UI601: cancel the stream task FIRST — the stream loop only
        // stops on cancellation; without it, streamer.reset()'s "ok" unblocks
        // the alarm-stalled ok-wait and the loop writes the next buffered
        // move, re-tripping the soft-limit alarm.
        jobTask?.cancel()
        jobTask = nil
        Task {
            await streamer.reset()
            await MainActor.run {
                self.isStreamingJob = false
                self.preflightPassed = false
                self.recomputeChromeState()
            }
            connection.addSystemMessage("Stream stopped")
        }
    }

    /// Resume a paused stream.
    public func resumeStreaming() {
        Task {
            await streamer.resume()
            connection.addSystemMessage("Stream resumed")
        }
    }

    /// Most recent CutToMachineBridge export, if any.
    private func mostRecentBridgeExport() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ShopPilotExports")
        guard FileManager.default.fileExists(atPath: tempDir.path) else { return nil }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            return files
                .filter { $0.pathExtension == "gcode" || $0.pathExtension == "nc" }
                .max { urlA, urlB in
                    let dateA = (try? urlA.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let dateB = (try? urlB.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return dateA < dateB
                }
        } catch {
            connection.addSystemMessage("Warning: Could not scan for bridge exports")
            return nil
        }
    }
}
