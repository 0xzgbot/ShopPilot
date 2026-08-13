import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1608 verify (CLT executable, no XCTest).
// Proves Home sends the GRBL homing cycle ($H), not a soft G28:
//   1. SOURCE CONTRACT: MachineController.softHomeAll() writes "$H" and the
//      status message names $H; no "G28" remains in the home path.
//   2. BEHAVIORAL: the simulator transport ACCEPTS "$H" (a controller that
//      rejected the homing command would be a real regression) and still
//      answers status queries afterward.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Source contract. ──────────────────────────────────────────────
    let controllerURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ShopPilot/MachineController.swift")
    let source = try String(contentsOf: controllerURL, encoding: .utf8)

    let homePath = source.range(of: "public func softHomeAll()")!
    let homeBody = source[homePath.upperBound...].prefix(400)
    try expect(homeBody.contains("\"$H\""),
               "softHomeAll sends the $H homing cycle")
    try expect(!homeBody.contains("G28"),
               "home path no longer sends G28")
    try expect(homeBody.contains("Homing sent"),
               "status message names the homing cycle")

    // ── 2. Behavioral: sim accepts $H and stays responsive. ─────────────
    let sim = SimulatorTransport()
    try awaitBlocking {
        try await sim.open(config: ShopPilotCore.SerialConfig(isSimulator: true, simulationDelayNanoseconds: 0))
        try await sim.write(Data("$H\n".utf8))
        let reply = try await sim.read()
        let text = String(decoding: reply, as: UTF8.self)
        try expect(!text.lowercased().contains("error"),
                   "sim accepts $H without error (got \(text))")
        // Still responsive to a status query after homing.
        try await sim.write(Data("?\n".utf8))
        let status = try await sim.read()
        let statusText = String(decoding: status, as: UTF8.self)
        try expect(statusText.contains("<") && statusText.contains(">"),
                   "machine still answers status after $H (got \(statusText))")
        await sim.close()
    }

    print("1608: PASS — Home sends $H (GRBL homing), not G28")
    print("  source contract ($H + no G28) and sim accepts $H + stays responsive")
}

do {
    try main()
} catch {
    print("1608: FAIL — \(error)")
    exit(1)
}

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
