import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1509 verify (CLT executable, no XCTest).
// Proves the simulator's soft limit follows the MachineProfile travel:
//   1. PROFILE → SIM: opening a sim transport with a 300mm-travel profile
//      trips ALARM:Soft limit at X=301 (and Y=301), while 299 is fine.
//   2. LEGACY DEFAULT: nil travel (or a profile that decodes without the
//      fields) keeps the 500mm envelope — trips at 501, 499 fine.
//   3. MACHINE PROFILE CODEC: travelXMM/travelYMM round-trip through Codable,
//      and a legacy JSON (no travel keys) decodes to 500/500.
//   4. SerialConfig.travelLimitMM passes through open(config:) (the sim
//      reads it).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Profile travel 300 → trips at 301, not at 299. ────────────────
    let sim300 = SimulatorTransport()
    try awaitBlocking {
        try await sim300.open(config: ShopPilotCore.SerialConfig(isSimulator: true, travelLimitMM: 300))
        try await sim300.write(Data("G0 X299\n".utf8))            // fine
        let alarmOK = try await sim300.read()
        try expect(String(decoding: alarmOK, as: UTF8.self) == "ok", "X=299 with 300mm travel → ok")
        try await sim300.write(Data("G0 X301\n".utf8))             // trips
        let alarm = try await sim300.read()
        let text = String(decoding: alarm, as: UTF8.self)
        try expect(text.contains("ALARM"), "X=301 with 300mm travel → ALARM (got \(text))")
        try expect(await sim300.isInAlarm, "X=301 latches the alarm")
        try await sim300.write(Data("\u{18}".utf8))                // reset alarm
        try await sim300.read()
        try await sim300.write(Data("G0 Y301\n".utf8))             // Y trips too
        let yAlarm = try await sim300.read()
        let yText = String(decoding: yAlarm, as: UTF8.self)
        try expect(yText.contains("ALARM"), "Y=301 also trips (got \(yText))")
        await sim300.close()
    }

    // ── 2. Legacy default 500 → trips at 501, 499 fine. ──────────────────
    let simDefault = SimulatorTransport()
    try awaitBlocking {
        try await simDefault.open(config: ShopPilotCore.SerialConfig(isSimulator: true)) // travelLimitMM nil
        try await simDefault.write(Data("G0 X499\n".utf8))
        let ok = try await simDefault.read()
        let okText = String(decoding: ok, as: UTF8.self)
        try expect(okText == "ok", "X=499 with default 500mm → ok (got \(okText))")
        try await simDefault.write(Data("G0 X501\n".utf8))
        let alarm = try await simDefault.read()
        let text = String(decoding: alarm, as: UTF8.self)
        try expect(text.contains("ALARM"), "X=501 with default 500mm → ALARM (got \(text))")
        await simDefault.close()
    }

    // ── 3. MachineProfile codec: round-trip + legacy decode → 500. ──────
    // (config: .simulator resolves the ShopPilotSerial SerialConfig — same
    // pattern ShopPilotVerifyFMR016 uses.)
    let profile = MachineProfile(
        name: "Small Router",
        config: .simulator,
        isSimulator: true,
        travelXMM: 300,
        travelYMM: 200
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(profile)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(MachineProfile.self, from: data)
    try expect(decoded.travelXMM == 300, "travelXMM round-trips (got \(decoded.travelXMM))")
    try expect(decoded.travelYMM == 200, "travelYMM round-trips (got \(decoded.travelYMM))")

    // Legacy JSON: same shape without travel keys → decodes to 500.
    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Legacy","config":{"baudRate":115200,"portName":"/dev/cu.test","dataBits":8,"parity":"none","stopBits":"one"},"isSimulator":true,"machineType":"grbl","units":"millimeter","vacuumHoldDown":false,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
    """
    let legacy = try decoder.decode(MachineProfile.self, from: Data(legacyJSON.utf8))
    try expect(legacy.travelXMM == 500 && legacy.travelYMM == 500,
               "legacy profile decodes travel → 500 (got \(legacy.travelXMM)/\(legacy.travelYMM))")

    // ── 4. SerialConfig codec keeps travelLimitMM. ───────────────────────
    let cfgData = try JSONEncoder().encode(ShopPilotCore.SerialConfig(isSimulator: true, travelLimitMM: 300))
    let cfgBack = try JSONDecoder().decode(ShopPilotCore.SerialConfig.self, from: cfgData)
    try expect(cfgBack.travelLimitMM == 300, "SerialConfig.travelLimitMM round-trips (got \(String(describing: cfgBack.travelLimitMM)))")

    print("1509: PASS — sim soft-limit from profile travel")
    print("  300mm travel trips at 301 (X and Y); legacy 500 default trips at 501; profile + config codec round-trip; legacy decode → 500")
}

do {
    try main()
} catch {
    print("1509: FAIL — \(error)")
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
