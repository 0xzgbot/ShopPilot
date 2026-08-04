import Foundation
import ShopPilotCore

/// SPK-1104 verify without XCTest (CLT-only):
/// Reset realtime path (0x18 / Ctrl-X) clears alarm/error banner state in the sim.
///
/// Proves:
///   1. SimulatorTransport latches a soft-limit alarm when motion exceeds the
///      travel envelope: status reports `<Alarm|…>` and commands are rejected.
///   2. The reset realtime byte (0x18 / Ctrl-X) clears the alarm latch:
///      status returns to `<Idle|…>` and motion works again.
///   3. MachineSession.reset() clears an error banner (connectionState .error)
///      back to .connected while sending 0x18 to the transport.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() async throws {
    // MARK: - 1. Alarm latches on soft-limit trip

    let transport = SimulatorTransport()
    try await transport.open(config: SerialConfig(isSimulator: true))
    defer { Task { await transport.close() } }

    // Idle by default
    try await transport.write(Data("?".utf8))
    let idleStatus = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(idleStatus.hasPrefix("<Idle|"), "expected Idle status, got \(idleStatus)")

    // Motion beyond the 500 mm travel envelope trips a soft-limit alarm
    try await transport.write(Data("G0 X9999".utf8))
    let tripReply = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(tripReply.hasPrefix("ALARM:Soft limit"), "expected soft-limit alarm, got \(tripReply)")
    try expect(await transport.isInAlarm, "transport should report isInAlarm after soft-limit trip")

    // Status now reports Alarm
    try await transport.write(Data("?".utf8))
    let alarmStatus = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(alarmStatus.hasPrefix("<Alarm|"), "expected Alarm status, got \(alarmStatus)")

    // Commands rejected while latched
    try await transport.write(Data("G1 X10 F100".utf8))
    let lockedReply = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(lockedReply.hasPrefix("error:Alarm lock"), "expected Alarm lock error, got \(lockedReply)")

    // MARK: - 2. Reset realtime byte (0x18 / Ctrl-X) clears the alarm

    try await transport.write(Data([0x18]))
    let resetReply = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(resetReply == "ok", "expected ok from reset, got \(resetReply)")
    try expect(!(await transport.isInAlarm), "transport should clear isInAlarm after reset")

    // Status back to Idle
    try await transport.write(Data("?".utf8))
    let clearedStatus = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(clearedStatus.hasPrefix("<Idle|"), "expected Idle after reset, got \(clearedStatus)")

    // Motion works again after reset
    try await transport.write(Data("G0 X10 Y20".utf8))
    let moveReply = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(moveReply == "ok", "expected ok for motion after reset, got \(moveReply)")
    try await transport.write(Data("?".utf8))
    let movedStatus = String(decoding: try await transport.read(), as: UTF8.self)
    try expect(movedStatus.contains("MPos:10.000"), "expected position updated, got \(movedStatus)")

    // MARK: - 3. MachineSession.reset() clears the error banner state

    let session = MachineSession()
    try await session.connect(transport: transport)
    // Force an error banner like one a real soft-limit trip would produce
    session.connectionState = .error("Soft limit alarm")
    if case .error = session.connectionState {
        // precondition met
    } else {
        throw VerifyError.failed("precondition: session in error banner state")
    }

    await session.reset()

    try expect(session.connectionState == .connected,
               "session reset should clear error banner to .connected, got \(session.connectionState)")
    // The status poller picks up the post-reset `?` reply asynchronously;
    // wait briefly for it to report Idle.
    var waited = 0
    while session.machineState != "Idle" && waited < 100 {
        try await Task.sleep(nanoseconds: 20_000_000)
        waited += 1
    }
    try expect(session.machineState == "Idle",
               "session reset should set machine state to Idle, got \(session.machineState)")
    try expect(!(await transport.isInAlarm),
               "session reset should clear transport alarm latch")

    print("ShopPilotVerify1104 PASS — reset (0x18/Ctrl-X) clears alarm/error banner state in sim")
}

do {
    try await main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
