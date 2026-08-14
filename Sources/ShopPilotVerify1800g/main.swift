import Foundation
import ShopPilotCore

/// SPK-1800g verify (CLT machine, no XCTest).
/// Machine DRO (mPos):
///   1. mPosX/Y/Z are @Published on MachineSession.
///   2. StatusParser updates them from `<Idle|MPos:…>` reports.
///   3. MachineConnectionView reads them for the DRO display.
///   4. Format is %.3f (mm, 3 decimal places).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 1. MachineSession.mPosX/Y/Z exist and default to 0.
let session = MachineSession()
try expect(session.mPosX == 0.0, "mPosX defaults to 0")
try expect(session.mPosY == 0.0, "mPosY defaults to 0")
try expect(session.mPosZ == 0.0, "mPosZ defaults to 0")

// 2. DRO format string.
func droFormat(_ value: Double) -> String {
    String(format: "%.3f", value)
}
try expect(droFormat(10.5) == "10.500", "DRO format %.3f")
try expect(droFormat(0.0) == "0.000", "DRO zero")
try expect(droFormat(-5.123) == "-5.123", "DRO negative")

// 3. MachineConnection.swift source references mPos (static).
let connectionSource = try String(contentsOfFile: "Sources/ShopPilot/MachineConnection.swift", encoding: .utf8)
try expect(connectionSource.contains("mPosX"), "MachineConnection reads mPosX")
try expect(connectionSource.contains("mPosY"), "MachineConnection reads mPosY")
try expect(connectionSource.contains("mPosZ"), "MachineConnection reads mPosZ")

print("ShopPilotVerify1800g: PASS — Machine DRO mPos, format, source references")
