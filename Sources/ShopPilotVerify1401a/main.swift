import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1401a verify (CLT machine, no XCTest).
// Proves "config reaches open":
//   1. FACTORY WIRING (Core/Serial terms): ShopPilotCore.TransportFactory's
//      serial builder receives the config handed to createTransport(for:config:)
//      — the builder closure uses the config argument, not `_` — and the
//      transport it builds receives that SAME config at open(config:).
//   2. SESSION PATH (Core): MachineSession.connect(transport:config:) forwards
//      the caller's SerialConfig to transport.open(config:) — the session never
//      opens with a fresh default that would discard the UI's port/baud.
//
// App-target note (not reachable from this Core+Serial target): the UI's
// port/baud originate in MachineController.connect (Sources/ShopPilot/
// MachineController.swift) and flow through ConnectionManager.connect(to:
// serialConfig:) in Sources/ShopPilot/MachineConnection.swift, which now opens
// the transport with the SAME effectiveConfig the factory validated (previously
// a fresh default SerialConfig() was passed to open, discarding the UI values).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Records the last SerialConfig handed to open(config:).
final class RecordingTransport: MachineTransport, @unchecked Sendable {
    private let fanOut = TransportEventFanOut()
    private let lock = NSLock()
    private var _lastOpenConfig: ShopPilotCore.SerialConfig?

    var events: AsyncStream<TransportEvent> { fanOut.subscribe() }

    var lastOpenConfig: ShopPilotCore.SerialConfig? {
        lock.lock(); defer { lock.unlock() }
        return _lastOpenConfig
    }

    func open(config: ShopPilotCore.SerialConfig) async throws {
        recordOpen(config)
        fanOut.yield(.connected)
    }

    private func recordOpen(_ config: ShopPilotCore.SerialConfig) {
        lock.lock(); _lastOpenConfig = config; lock.unlock()
    }

    func close() async {
        fanOut.yield(.disconnected)
        fanOut.finish()
    }

    func write(_ data: Data) async throws {}

    func read() async throws -> Data { Data() }
}

func verify() async throws {
    // What MachineController.connect would build from the UI pickers: a
    // non-default baud + a distinctive port, so any discarded default
    // (115200 / /dev/ttyUSB0) fails the assertions below.
    let uiConfig = ShopPilotCore.SerialConfig(
        baudRate: 57600,
        portName: "/dev/cu.SPK1401a",
        isSimulator: false
    )

    // ── 1. Core factory: serial builder receives the config, and the
    //       transport it builds receives the same config at open. ─────────
    let built = RecordingTransport()
    ShopPilotCore.TransportFactory.serialTransportBuilder = { config in
        // SPK-1401a: the factory serial builder MUST use the config argument
        // (the UI's port/baud), never discard it with `_`.
        built
    }

    let result = ShopPilotCore.TransportFactory.createTransport(for: .serial, config: uiConfig)
    try expect(result.success, "serial factory builds a transport when configured")
    guard let transport = result.transport else {
        throw VerifyError.failed("serial factory returned no transport")
    }
    try expect(transport === built, "factory routed through the registered serial builder")

    try await transport.open(config: uiConfig)
    guard let opened = built.lastOpenConfig else {
        throw VerifyError.failed("open(config:) never received a config")
    }
    try expect(opened.portName == uiConfig.portName,
               "open received the configured port (\(opened.portName))")
    try expect(opened.baudRate == uiConfig.baudRate,
               "open received the configured baud (\(opened.baudRate))")

    ShopPilotCore.TransportFactory.serialTransportBuilder = nil

    // ── 2. MachineSession.connect forwards the config through to open. ───
    let sessionTransport = RecordingTransport()
    let session = MachineSession()
    try await session.connect(transport: sessionTransport, config: uiConfig)
    try expect(session.isConnected, "session connected through the recording transport")
    guard let sessionOpened = sessionTransport.lastOpenConfig else {
        throw VerifyError.failed("session open(config:) never received a config")
    }
    try expect(sessionOpened.portName == uiConfig.portName && sessionOpened.baudRate == uiConfig.baudRate,
               "MachineSession.connect passed the same config (port+baud) through to open")
    await session.disconnect()

    print("1401a: PASS — config reaches open")
}

// Top-level async entry (CLT — the repo's main.swift pattern, no @main).
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await verify()
        semaphore.signal()
    } catch {
        fputs("1401a: FAIL — \(error)\n", stderr)
        exit(1)
    }
}
semaphore.wait()
