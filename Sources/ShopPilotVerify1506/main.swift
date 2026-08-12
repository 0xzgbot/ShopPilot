import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1506 verify (CLT executable, no XCTest).
// Proves ONE transport factory exists after the duplicate was deleted:
//   1. SOURCE CONTRACT: only ShopPilotCore/TransportFactory.swift declares
//      `final class TransportFactory` — the app-target duplicate in
//      MachineConnection.swift is gone (and its `TransportFactoryResult`
//      struct too).
//   2. CONNECTION MANAGER routes through the Core factory: connect(to:)
//      calls ShopPilotCore.TransportFactory.createTransport(for:
//      type.coreType, ...) — the UI enum maps to Core TransportType.
//   3. BEHAVIOR: Core factory with the App-registered serial builder returns
//      a real serial transport for .serial; sim returns SimulatorTransport.
//   4. MachineTransportType.coreType maps both cases 1:1.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    // ── 1. One TransportFactory declaration in the whole Sources tree. ───
    let coreFactory = try String(
        contentsOf: root.appendingPathComponent("ShopPilotCore/TransportFactory.swift"),
        encoding: .utf8
    )
    try expect(coreFactory.contains("public final class TransportFactory"),
               "Core TransportFactory exists")

    let appConnection = try String(
        contentsOf: root.appendingPathComponent("ShopPilot/MachineConnection.swift"),
        encoding: .utf8
    )
    try expect(!appConnection.contains("public final class TransportFactory"),
               "MachineConnection.swift no longer declares a duplicate TransportFactory")
    try expect(!appConnection.contains("public struct TransportFactoryResult"),
               "MachineConnection.swift no longer declares a duplicate TransportFactoryResult")

    // ── 2. ConnectionManager routes through the Core factory. ────────────
    try expect(appConnection.contains("ShopPilotCore.TransportFactory.createTransport"),
               "ConnectionManager uses ShopPilotCore.TransportFactory")
    try expect(appConnection.contains("type.coreType"),
               "ConnectionManager passes the UI enum mapped to Core TransportType")

    // ── 3. Behavior: serial via registered builder, sim via Simulator. ───
    TransportFactory.serialTransportBuilder = { _ in RealSerialTransport() }
    let serialResult = TransportFactory.createTransport(for: .serial)
    try expect(serialResult.success, "serial transport created via builder")
    try expect(serialResult.transport is RealSerialTransport,
               "serial builder yields RealSerialTransport")

    let simResult = TransportFactory.createTransport(for: .simulator)
    try expect(simResult.success, "simulator transport created")
    try expect(simResult.transport is SimulatorTransport,
               "sim yields SimulatorTransport")

    // ── 4. coreType mapping exists on the UI enum (source contract — the
    // enum itself is app-target, unimportable from the CLT).
    try expect(appConnection.contains("public var coreType: TransportType"),
               "MachineTransportType declares coreType → Core TransportType")
    try expect(appConnection.contains("case .simulator: return .simulator")
               && appConnection.contains("case .serial: return .serial"),
               "coreType maps both cases 1:1")

    print("1506: PASS — one TransportFactory (Core), duplicate deleted")
    print("  serial → RealSerialTransport via builder; sim → SimulatorTransport; coreType maps 1:1")
}

do {
    try main()
} catch {
    print("1506: FAIL — \(error)")
    exit(1)
}
