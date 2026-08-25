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

    // MARK: - SPK-2022d — device profile library

    /// The active device profile (nil until a pick is made). Drives §2.4
    /// soft-limit jog awareness and carries the chosen post id.
    @Published public private(set) var activeDeviceProfile: DeviceProfile?

    /// Id of the active profile ("" when untouched this session).
    @Published public private(set) var deviceProfileID: String = ""

    /// One pick sets baud + post + travel + origin, persists last-used, and
    /// never blocks connect: an unknown/stale id resolves to the Generic GRBL
    /// fallback instead of failing.
    public func selectDeviceProfile(id: String) {
        applyDeviceProfile(DeviceProfileCatalog.resolved(id: id))
    }

    /// Apply a resolved profile. `announce: false` for the silent launch-time
    /// restore of last-used (no console spam on startup).
    private func applyDeviceProfile(_ profile: DeviceProfile, announce: Bool = true) {
        deviceProfileID = profile.id
        activeDeviceProfile = profile
        LastDeviceProfileStore.save(profile.id)

        // Baud follows the machine (GRBL-class: 115200).
        serialBaudRate = profile.baud

        // Travel feeds the simulator soft-limit envelope (SPK-1509 hook);
        // placeholder/unknown travel keeps the legacy envelope.
        if let simLimit = profile.simTravelLimitMM {
            simTravelLimitMM = simLimit
        }

        if announce {
            let travel = profile.travelKnown
                ? "\(Int(profile.travelXMm))×\(Int(profile.travelYMm))×\(Int(profile.travelZMm))mm"
                : "travel unknown"
            connection.addSystemMessage(
                "Machine profile: \(profile.name) — \(profile.baud) baud · post '\(profile.postID)' · travel \(travel) · origin \(profile.originConvention.displayName)")
        }
    }

    /// Operator has confirmed the pre-flight checklist. Never auto-set.
    @Published public var preflightPassed = false

    /// SPK-2022c — "bit already loaded": when ON, the send path suppresses
    /// EXACTLY the first M6 (+ its immediate dwell) in the outgoing program.
    /// Pure send-time filter: no document mutation, and toggling OFF restores
    /// the full program byte-for-byte.
    @Published public var bitAlreadyLoaded = false

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
        // SPK-2022d — restore last-used profile silently. A stale id resolves
        // to Generic; resolution never fails, so connect is never blocked.
        if let saved = LastDeviceProfileStore.load() {
            applyDeviceProfile(DeviceProfileCatalog.resolved(id: saved), announce: false)
        }
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
        // SPK-DOGFOOD-02 — the 500ms status poller fires `$currentStatus` even
        // when the report text is identical, and writing the same value back
        // still fires objectWillChange → the whole Machine stage body (and
        // every observer of the window chrome) rebuilds twice a second. During
        // an alarm with raw TX/RX on, that stacked with console appends into a
        // permanent AttributeGraph storm. Only publish when the glanceable
        // state actually changed; `.running(progress:)` still flows on real
        // progress deltas because progress participates in equality.
        let next = derivedChromeState()
        if next != chromeState {
            chromeState = next
        }
    }

    /// Main-actor wrapper for chrome recomputes fired from non-main contexts
    /// (button-action Tasks, async stream paths). SPK-DOGFOOD-02: publishing
    /// `chromeState` from a BACKGROUND thread drives SwiftUI's AttributeGraph
    /// off-main — that path blocks on `_MovableLockSyncMain` while the main
    /// thread holds the AttributeGraph lock in its own update and waits on the
    /// same publisher's unfair lock → ABBA deadlock (the reconnect beachball).
    @MainActor
    func recomputeChromeStateOnMain() async {
        recomputeChromeState()
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
        await recomputeChromeStateOnMain()
    }

    public func disconnect() async {
        // Safety Req #3: a job must never keep streaming into a closed port.
        stopStreaming()
        await connection.disconnect()
        // ConnectionManager owns the transport lifecycle — session detaches
        // (no double-close) and resets its own state.
        machineSession.detach()
        // SPK-DOGFOOD-02 — the streamer must not carry the old transport into
        // the next connection: reset()/hold/resume would write into a closed
        // wire and block the awaiting main thread forever.
        streamer.finishStreaming()
        preflightPassed = false
        latchedAlarm = nil
        await recomputeChromeStateOnMain()
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

    // MARK: - SPK-1900b — Frame job / click-to-jog

    /// True when motion commands are safe to send: transport open, not
    /// streaming, not in alarm. Mirrors the softHomeAll gate.
    public var canSendMotion: Bool {
        connection.connectionState.isConnected && chromeState == .idle
    }

    /// Trace the job bounds in air at a safe clearance height so the operator
    /// can verify stock placement before cutting. No-op unless connected AND
    /// idle; never sends spindle or Z-cutting motion.
    public func frameJob(widthMm: Double, heightMm: Double) {
        guard canSendMotion else {
            connection.addSystemMessage("Frame needs a connected, idle machine")
            return
        }
        let lines = FrameJobFormatter.lines(widthMm: widthMm, heightMm: heightMm)
        Task {
            for line in lines {
                await connection.sendCommand(line)
            }
            connection.addSystemMessage("Frame sent — \(Int(widthMm))×\(Int(heightMm))mm at safe Z")
        }
    }

    /// Click-to-jog: absolute rapid to the clicked canvas point. No-op unless
    /// connected AND idle.
    public func jogTo(xMm: Double, yMm: Double) {
        guard canSendMotion else {
            connection.addSystemMessage("Jog-to needs a connected, idle machine")
            return
        }
        let line = JogToFormatter.line(xMm: xMm, yMm: yMm)
        Task {
            await connection.sendCommand(line)
            connection.addSystemMessage("Jog to X\(String(format: "%.1f", xMm)) Y\(String(format: "%.1f", yMm))")
        }
    }

    // MARK: - Touch-off probing (SPK-1303)

    /// Run the touch-off probe sequence at the current XY. After the probe
    /// hits, compute + apply the Z work offset so the stock surface reads 0.
    /// SPK-1920f: a disconnected (or busy) machine makes this an honest no-op —
    /// nothing is queued and the status names why.
    public func touchOffZ(plateThickness: Double = 3.0) {
        guard canSendMotion else {
            connection.addSystemMessage("Touch-off probe needs a connected, idle machine — connect first")
            return
        }
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

    // MARK: - XYZ plate probe cycle (SPK-2022a)

    /// Run the full XYZ plate probe cycle: three legs in order Z → X → Y.
    /// Each leg probes its axis (`G38.2`) then immediately commits its own
    /// `G10 L20 P1` work offset, so aborting mid-cycle keeps every
    /// already-committed leg's offset intact while applying nothing from
    /// uncompleted legs. SPK-1920f precedent: a disconnected (or busy) machine
    /// makes this an honest no-op — nothing is queued, the status names why.
    public func touchOffXYZPlate(plateThickness: Double = 3.0, userXYOffset: Double = 0.0) {
        guard canSendMotion else {
            connection.addSystemMessage("XYZ plate probe needs a connected, idle machine — connect first")
            return
        }
        let plan = TouchOff.planXYZPlate(plateThickness: plateThickness, userXYOffset: userXYOffset)
        let legs = TouchOff.xyzPlateLegs(plan)
        let legAxes = ["Z", "X", "Y"]
        Task {
            var committedLegs = 0
            for (index, leg) in legs.enumerated() {
                // All-or-nothing per leg: if the machine dropped between legs,
                // stop here — committed legs keep their offsets, uncompleted
                // legs apply nothing.
                guard connection.connectionState.isConnected else {
                    connection.addSystemMessage(
                        "XYZ plate probe stopped after \(committedLegs)/\(legs.count) legs — disconnected; committed offsets kept"
                    )
                    return
                }
                for line in leg {
                    await connection.sendCommand(line)
                }
                committedLegs += 1
                connection.addSystemMessage("XYZ plate: \(legAxes[index]) leg committed (\(committedLegs)/\(legs.count))")
            }
            connection.addSystemMessage(
                "XYZ plate cycle complete (plate \(plateThickness)mm) — Z→X→Y zeroed at the plate"
            )
        }
    }

    // MARK: - Tool-length offset (SPK-2022b)

    /// Run the tool-length-offset cycle: send the tool change (`M6 T<n>`),
    /// then re-probe **Z only** against the touch plate and commit
    /// `G10 L20 P1 Z<thickness>` so the stock surface reads Z = 0 under the
    /// new bit. The emitted sequence carries no X or Y words, so XY work
    /// registers cannot move (proven by `ShopPilotVerify2022b`). Follows the
    /// touch-off flow: lines go through `connection.sendCommand` exactly like
    /// `touchOffZ`/`touchOffXYZPlate`; streamer internals untouched.
    /// SPK-1920f precedent: a disconnected (or busy) machine makes this an
    /// honest no-op — nothing is queued, the status names why.
    public func probeToolLengthOffset(toolNumber: Int = 1, plateThickness: Double = 3.0) {
        guard canSendMotion else {
            connection.addSystemMessage("Tool length offset needs a connected, idle machine — connect first")
            return
        }
        let plan = TouchOff.planToolLengthOffset(toolNumber: toolNumber, plateThickness: plateThickness)
        let sequence = TouchOff.toolLengthOffsetSequence(plan)
        Task {
            for line in sequence {
                await connection.sendCommand(line)
            }
            connection.addSystemMessage(
                "Tool length offset sent (T\(toolNumber), plate \(plateThickness)mm) — Z re-probed after tool change; XY untouched"
            )
        }
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
            // SPK-2022c — "bit already loaded": suppress exactly the first
            // M6 (+ immediate dwell) on the way out. Pure send-time filter —
            // the session buffer itself is never mutated.
            let outgoing = SendTimeM6Filter.apply(
                machineSession.gcodeBuffer,
                skipEnabled: bitAlreadyLoaded
            )
            if outgoing.suppressedCount > 0 {
                connection.addSystemMessage(
                    "Bit already loaded — skipped first M6 (\(outgoing.suppressedCount) line\(outgoing.suppressedCount == 1 ? "" : "s") suppressed)"
                )
            }
            connection.addSystemMessage("Streaming \(machineSession.gcodeBuffer.count) lines from session buffer")
            try await streamer.stream(lines: outgoing.lines, to: transport)
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
            // SPK-2022c — same send-time first-M6 filter as the buffer path;
            // the fallback lines themselves are never mutated.
            let outgoing = SendTimeM6Filter.apply(resolved, skipEnabled: bitAlreadyLoaded)
            if outgoing.suppressedCount > 0 {
                connection.addSystemMessage(
                    "Bit already loaded — skipped first M6 (\(outgoing.suppressedCount) line\(outgoing.suppressedCount == 1 ? "" : "s") suppressed)"
                )
            }
            try await streamer.stream(lines: outgoing.lines, to: transport)
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
            // SPK-DOGFOOD-02 — drop the streamer's transport reference the
            // moment a stream ends (ok, error, or cancel). A stale reference
            // to a closed transport made the next disconnect→reconnect hang
            // the main thread (dogfood beachball 2026-08-22).
            self.streamer.finishStreaming()
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
