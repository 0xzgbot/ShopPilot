import Foundation
import Combine
import ShopPilotCore

// SPK-UI609 verification — machine ownership must outlive the Machine stage.
//
// Observed bug: MachineConnectionView owned the ConnectionManager as a
// @StateObject, the job Task and the preflight flag as @State, and the
// MachineSession as @State. `ContentView.stageBody` is a `switch`, so leaving
// the Machine stage destroyed all of it: the connection dropped, a running job
// was cancelled by navigation, and `.onDisappear { chrome?.state = .offline }`
// made the window chrome agree with the damage instead of reporting it. The
// compact Hold/Reset in the top chrome could therefore never work — Safety
// Req #1 (Hold and Reset reachable while connected) was unenforceable.
//
// Ownership now lives in MachineController, held by AppSession for the app
// lifetime. MachineController is compiled into the ShopPilot executable target,
// which SwiftPM cannot link into a second executable, so this verify proves the
// fix from both ends:
//
//   Part 1 (behavioural) — the exact ownership shape, using the real Core
//   MachineSession / GCodeStreamer against a recording transport: commands and
//   a running stream survive the view going away, and the old shape does not.
//
//   Part 2 (structural) — the app sources no longer contain the anti-patterns
//   that caused it, so the class of bug cannot come back unnoticed.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Yield the main actor so background work runs and MainActor.run hops land.
///
/// This must *await*, not block: `RunLoop.main.run(until:)` holds the main
/// thread and starves the cooperative pool, so a `Task.sleep` inside the code
/// under test never resumes and everything appears frozen.
func settle(_ seconds: TimeInterval = 0.3) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - Recording transport

/// A MachineTransport that records every byte written and answers each write
/// with "ok", so the streamer's ok-wait loop makes progress deterministically.
final class RecordingTransport: MachineTransport, @unchecked Sendable {

    private let lock = NSLock()
    private var _writes: [Data] = []
    private var _isOpen = false

    /// Delay before acknowledging a line, so a streamed job takes measurable
    /// wall-clock time the way a real controller does. A zero-delay fake
    /// finishes before the test can look at it.
    private let ackDelayNanoseconds: UInt64

    private var subscribers: [AsyncStream<TransportEvent>.Continuation] = []

    init(ackDelayNanoseconds: UInt64 = 0) {
        self.ackDelayNanoseconds = ackDelayNanoseconds
    }

    /// Live fan-out, like the real transports: every subscriber gets every
    /// event from the moment it subscribes. A single-consumer stream would let
    /// MachineSession's status poller eat the streamer's "ok".
    var events: AsyncStream<TransportEvent> {
        AsyncStream { continuation in
            lock.lock()
            subscribers.append(continuation)
            lock.unlock()
        }
    }

    private func broadcast(_ event: TransportEvent) {
        lock.lock()
        let targets = subscribers
        lock.unlock()
        for target in targets { target.yield(event) }
    }

    // Locking stays in synchronous helpers: NSLock is unavailable from async
    // contexts (a hard error under Swift 6).

    private func record(_ data: Data) {
        lock.lock(); _writes.append(data); lock.unlock()
    }

    private func setOpen(_ open: Bool) {
        lock.lock(); _isOpen = open; lock.unlock()
    }

    /// Every payload written, oldest first.
    var writes: [Data] {
        lock.lock(); defer { lock.unlock() }
        return _writes
    }

    /// Writes decoded as UTF-8 text (realtime bytes come back as escapes).
    var writtenText: [String] {
        writes.map { data in
            if data == Data([0x18]) { return "<0x18>" }
            return String(data: data, encoding: .utf8) ?? "<binary>"
        }
    }

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isOpen
    }

    func open(config: SerialConfig) async throws {
        setOpen(true)
        broadcast(.connected)
    }

    func close() async {
        setOpen(false)
        broadcast(.disconnected)
    }

    func write(_ data: Data) async throws {
        record(data)
        // GRBL answers every accepted line with "ok". Realtime bytes (!, ~,
        // 0x18) are not acknowledged, matching a real controller.
        let text = String(data: data, encoding: .utf8) ?? ""
        let isRealtime = data == Data([0x18]) || text == "!" || text == "~" || text == "?"
        if !isRealtime {
            if ackDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: ackDelayNanoseconds)
            }
            broadcast(.dataReceived(Data("ok\n".utf8)))
        }
    }

    func read() async throws -> Data { Data() }
}

// MARK: - Ownership shapes

/// The shape ShopPilot uses now: an app-lifetime owner (AppSession ->
/// MachineController) holding the transport, session and streamer.
final class LongLivedOwner {
    let transport: RecordingTransport
    let machineSession = MachineSession()
    let streamer = GCodeStreamer()

    init(ackDelayNanoseconds: UInt64 = 0) {
        transport = RecordingTransport(ackDelayNanoseconds: ackDelayNanoseconds)
    }

    func connect() async throws {
        try await transport.open(config: SerialConfig(isSimulator: true))
        machineSession.connectionState = .connected
        machineSession.attach(transport: transport)
        machineSession.attachStreamer(streamer)
    }

    func hold() async { await machineSession.hold() }
    func resume() async { await machineSession.resume() }
    func reset() async { await machineSession.reset() }
}

/// Stand-in for MachineConnectionView: it *borrows* the owner and is thrown
/// away when the operator switches stages. Nothing machine-related may die
/// with it.
struct MachineStageView {
    unowned let owner: LongLivedOwner
}

// MARK: - Part 1: behavioural

/// Test 1 — the whole point: commands still reach the machine after the
/// Machine stage view is gone.
func testSafetyCommandsSurviveViewTeardown() async throws {
    let owner = LongLivedOwner()
    try await owner.connect()

    // Operator is on the Machine stage and connects.
    do {
        let view = MachineStageView(owner: owner)
        _ = view
    } // ...then switches to Design: the view is deallocated here.

    // Safety Req #1: chrome Hold / Resume / Reset must still command the machine.
    await owner.hold()
    await owner.resume()
    await owner.reset()
    await settle()

    let text = owner.transport.writtenText
    try expect(text.contains("!"), "Hold never reached the transport: \(text)")
    try expect(text.contains("~"), "Resume never reached the transport: \(text)")
    try expect(text.contains("<0x18>"), "Reset never reached the transport: \(text)")
    try expect(owner.transport.isOpen, "transport closed when the stage view went away")
    try expect(owner.machineSession.isConnected,
               "session reported disconnected after the stage view went away")
    print("  [1/6] Hold / Resume / Reset work after leaving the Machine stage PASS")
}

/// Test 2 — negative control, so test 1 cannot pass vacuously. Under the old
/// shape the Machine stage owned the session (`@StateObject` /`@State`), so
/// each visit to the stage built a new one and the connection made on the
/// previous visit was gone.
func testOldViewOwnedShapeLosesTheMachine() async throws {

    /// The old shape: machine state declared inside the view.
    final class OldMachineStageView {
        let machineSession = MachineSession()
    }

    let transport = RecordingTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))

    // First visit to the Machine stage: the operator connects.
    let firstVisit = OldMachineStageView()
    firstVisit.machineSession.connectionState = .connected
    firstVisit.machineSession.attach(transport: transport)
    await firstVisit.machineSession.hold()
    await settle(0.1)
    try expect(transport.writtenText.contains("!"),
               "control setup is wrong — Hold did not reach the transport on the first visit")

    let writesBefore = transport.writes.count

    // Operator switches stages and comes back: SwiftUI rebuilds the view, and
    // with it a brand new, unattached session.
    let secondVisit = OldMachineStageView()
    try expect(!secondVisit.machineSession.isConnected,
               "control is broken — a rebuilt view somehow kept the connection")
    await secondVisit.machineSession.hold()
    await secondVisit.machineSession.reset()
    await settle(0.1)

    try expect(transport.writes.count == writesBefore,
               "control is broken — view-owned state reached the machine after a rebuild")
    print("  [2/6] view-owned machine state loses the machine on rebuild (control) PASS")
}

/// Test 3 — a running job keeps streaming after the stage view is gone, and a
/// Hold issued from the window chrome still pauses it mid-cut.
func testRunningJobSurvivesNavigation() async throws {
    // 5ms per line, 200 lines — about a second of cutting, long enough to
    // navigate away and Hold in the middle of it.
    let owner = LongLivedOwner(ackDelayNanoseconds: 5_000_000)
    try await owner.connect()

    let lines = (1...200).map { "G1 X\($0) F600" }
    // Detached: top-level code here is @MainActor, and an inherited MainActor
    // task would be starved by the run-loop pumping below. In the app the
    // stream runs off the main actor for the same reason.
    let job = Task.detached { [owner] in
        try? await owner.streamer.stream(lines: lines, to: owner.transport)
    }

    // Let the stream get going, then "leave the Machine stage".
    await settle(0.3)
    do {
        let view = MachineStageView(owner: owner)
        _ = view
    }

    try expect(owner.streamer.state == .streaming,
               "stream stopped when the stage view went away: \(owner.streamer.state) "
               + "line \(owner.streamer.currentLine)/\(owner.streamer.totalLines) "
               + "writes \(owner.transport.writes.count) err \(owner.streamer.lastError ?? "-")")

    // Hold from the window chrome.
    await owner.hold()
    await settle(0.2)
    try expect(owner.streamer.state == .paused,
               "chrome Hold did not pause the running job: \(owner.streamer.state)")
    let linesAtHold = owner.streamer.currentLine

    await settle(0.3)
    try expect(owner.streamer.currentLine == linesAtHold,
               "job kept cutting through a Hold: \(linesAtHold) -> \(owner.streamer.currentLine)")

    // Resume from the window chrome and let it finish.
    await owner.resume()
    await settle(0.6)
    try expect(owner.streamer.currentLine > linesAtHold,
               "chrome Resume did not restart the job at line \(linesAtHold)")

    job.cancel()
    await settle(0.2)
    print("  [3/6] running job survives navigation; chrome Hold/Resume drive it PASS")
}

// MARK: - Part 2: structural

/// Repo root, derived from this file's compile-time path.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ShopPilotVerifyUI609
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // repo root

func appSource(_ name: String) throws -> String {
    let url = repoRoot.appendingPathComponent("Sources/ShopPilot/\(name)")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        throw VerifyError.failed("cannot read Sources/ShopPilot/\(name)")
    }
    return text
}

/// Test 4 — the controller exists, owns the three machine objects, and
/// AppSession holds it for the app lifetime.
func testControllerOwnsTheMachine() throws {
    let controller = try appSource("MachineController.swift")
    try expect(controller.contains("let connection = ConnectionManager()"),
               "MachineController does not own the ConnectionManager")
    try expect(controller.contains("let streamer = GCodeStreamer()"),
               "MachineController does not own the GCodeStreamer")
    try expect(controller.contains("let machineSession = MachineSession()"),
               "MachineController does not own the MachineSession")

    let session = try appSource("AppSession.swift")
    try expect(session.contains("let machine = MachineController()"),
               "AppSession does not own a MachineController — ownership is not app-lifetime")
    print("  [4/6] MachineController owns the machine; AppSession owns it PASS")
}

/// Test 5 — the Machine stage is a view over shared state, and the offline lie
/// is gone.
func testStageNoLongerOwnsOrLies() throws {
    let stage = try appSource("MachineConnection.swift")

    try expect(!stage.contains("@StateObject private var connectionManager"),
               "Machine stage still owns the ConnectionManager as @StateObject")
    try expect(!stage.contains("@State private var machineSession"),
               "Machine stage still owns the MachineSession as @State")
    try expect(!stage.contains("@State private var jobTask"),
               "Machine stage still owns the stream Task as @State — a job dies on navigation")
    try expect(!stage.contains("@ObservedObject private var streamer = GCodeStreamer()"),
               "streamer is re-created on every view init (@ObservedObject initial values "
               + "are not retained by SwiftUI)")

    // The specific lie: leaving the stage reported an open transport as offline.
    try expect(!stage.contains("chrome?.state = .offline"),
               "onDisappear still fakes .offline while the transport is open")
    try expect(!stage.contains("MachineChromeLink"),
               "the dead MachineChromeLink bridge is still referenced")

    try expect(stage.contains("controller: MachineController"),
               "Machine stage does not take a MachineController")
    print("  [5/6] Machine stage borrows shared state and no longer fakes offline PASS")
}

/// Test 6 — the chrome tells the truth: Idle and Running are visually
/// distinct, and the compact controls offer Resume when motion is held.
func testChromeIsGlanceableAndComplete() throws {
    let design = try appSource("DesignSystem.swift")

    try expect(design.contains("case .idle: return SP.Tint.ready"),
               "Idle still shares Running's tint — the two states are not glanceable")
    try expect(design.contains("case .running: return SP.Tint.running"),
               "Running lost its tint")
    try expect(design.contains("static let ready") && design.contains("static let running"),
               "SP.Tint is missing the ready/running pair")

    // Hold OR Resume, plus Reset whenever the transport is open.
    try expect(design.contains("controller.chromeState.isHeld"),
               "CompactSafetyControls does not switch Hold -> Resume when held")
    try expect(design.contains("Button(action: controller.resume)"),
               "CompactSafetyControls has no Resume action")
    try expect(design.contains("Button(action: controller.hold)"),
               "CompactSafetyControls has no Hold action")
    try expect(design.contains("Button(action: controller.reset)"),
               "CompactSafetyControls has no Reset action")

    let content = try appSource("ContentView.swift")
    try expect(content.contains("controller.chromeState.isLive && session.selectedStage != .machine"),
               "top chrome does not show safety controls off the Machine stage")
    print("  [6/6] Idle != Running; compact chrome offers Hold/Resume + Reset PASS")
}

// MARK: - Runner

func run() async -> Int32 {
    print("SPK-UI609 — machine ownership survives stage navigation")
    do {
        try await testSafetyCommandsSurviveViewTeardown()
        try await testOldViewOwnedShapeLosesTheMachine()
        try await testRunningJobSurvivesNavigation()
        try testControllerOwnsTheMachine()
        try testStageNoLongerOwnsOrLies()
        try testChromeIsGlanceableAndComplete()
        print("SPK-UI609 PASS — 6/6")
        return 0
    } catch let VerifyError.failed(message) {
        print("SPK-UI609 FAIL — \(message)")
        return 1
    } catch {
        print("SPK-UI609 FAIL — \(error)")
        return 1
    }
}

exit(await run())
