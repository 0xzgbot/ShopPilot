import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1401c verify (CLT machine, no XCTest).
// Proves the GRBL line-shaping seam the jog/console send path is wired to:
//   1. NEWLINE GUARANTEE: every command line carries exactly one trailing '\n'
//      — appended when missing, already-terminated lines left unchanged (no
//      double '\n').
//   2. JOG RESTORE: jog emits the G91 relative-rapid block followed by a G90
//      restore, so the machine does not stay in relative mode after jogging.
//   3. THROUGH THE REAL SEND PATH (MachineSession + recording
//      SimulatorTransport.writtenBytesSnapshot): a non-jog sendCommand writes
//      its command + '\n' and NOTHING else (no G90 injected), and the jog
//      formatter's output arrives byte-exact: "G91 G0 X5.000\nG90\n".
//
// Wiring under test (helper is the shared testable seam):
//   - MachineSession.sendCommand        → GCodeLine.sending (Core, verified below)
//   - ConnectionManager.sendCommand     → GCodeLine.sending (app target, same
//     helper — Sources/ShopPilot/MachineConnection.swift)
//   - MachineController.jog             → JogCommandFormatter.lines, each line
//     via ConnectionManager.sendCommand (Sources/ShopPilot/MachineController.swift)

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// Minimal async runner: keep the verify main synchronous on CLT.
private func awaitBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task {
        do { result = .success(try await op()) }
        catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result!.get()
}

func main() throws {
    // ── 1. Newline guarantee (pure helper). ────────────────────────────────
    try expect(GCodeLine.sending("G0 X0") == "G0 X0\n",
               "bare command gets a trailing newline")
    try expect(GCodeLine.sending("G0 X0\n") == "G0 X0\n",
               "command already ending in \\n is unchanged (no double newline)")
    try expect(GCodeLine.sending("G0 X0\r\n") == "G0 X0\r\n",
               "CRLF-terminated command is unchanged")
    try expect(GCodeLine.sending("G0 X0\r") == "G0 X0\r\n",
               "CR-only command gets the LF half of the terminator")
    try expect(GCodeLine.sending("") == "\n",
               "empty command still carries a terminator")

    // ── 2. Jog sequence: G91 block then G90 restore. ───────────────────────
    try expect(JogCommandFormatter.lines(axis: "X", distanceMm: 5.0) == ["G91 G0 X5.000", "G90"],
               "jog +X emits G91 move then G90 restore")
    try expect(JogCommandFormatter.lines(axis: "Y", distanceMm: -1.0) == ["G91 G0 Y-1.000", "G90"],
               "jog -Y emits signed G91 move then G90 restore")
    try expect(JogCommandFormatter.restoreLine == "G90",
               "restore line is exactly G90")

    // ── 3. Recording transport: session send path. ─────────────────────────
    try awaitBlocking {
        let sim = SimulatorTransport()
        let session = MachineSession()
        try await session.connect(transport: sim,
                                  config: SerialConfig(isSimulator: true, simulationDelayNanoseconds: 0))

        // Non-jog command: newline-terminated, and NO G90 injected.
        let before1 = await sim.writtenBytesSnapshot
        try await session.sendCommand("G28")
        let sent1 = String(decoding: (await sim.writtenBytesSnapshot).dropFirst(before1.count), as: UTF8.self)
        try expect(sent1 == "G28\n", "session sendCommand('G28') writes 'G28\\n' (got \(sent1.debugDescription))")
        try expect(!sent1.contains("G90"), "non-jog sendCommand does NOT inject G90")

        // Already-terminated command stays single-terminated through the session.
        let before2 = await sim.writtenBytesSnapshot
        try await session.sendCommand("G91 G0 X5.000\n")
        let sent2 = String(decoding: (await sim.writtenBytesSnapshot).dropFirst(before2.count), as: UTF8.self)
        try expect(sent2 == "G91 G0 X5.000\n",
                   "pre-terminated command is written unchanged (got \(sent2.debugDescription))")

        // End-to-end jog: the formatter's two lines arrive byte-exact.
        let jog = JogCommandFormatter.lines(axis: "X", distanceMm: 5.0)
        let before3 = await sim.writtenBytesSnapshot
        for line in jog {
            try await session.sendCommand(line)
        }
        let sent3 = String(decoding: (await sim.writtenBytesSnapshot).dropFirst(before3.count), as: UTF8.self)
        try expect(sent3 == "G91 G0 X5.000\nG90\n",
                   "jog sequence writes G91 block then G90 restore, newline-terminated (got \(sent3.debugDescription))")

        await session.disconnect()
    }

    print("1401c: PASS — jog newline + G90 restore")
}

do {
    try main()
} catch {
    print("1401c: FAIL — \(error)")
    exit(1)
}
