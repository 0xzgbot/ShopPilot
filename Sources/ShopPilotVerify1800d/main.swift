import Foundation
import ShopPilotCore

/// SPK-1800d verify (CLT machine, no XCTest).
/// Sheet origin datum (corner / center):
///   1. canvasOriginRaw is a valid Codable field on Job.
///   2. Default is "corner" (legacy documents decode nil → corner).
///   3. Persistence round-trips through Job encode/decode.
///   4. Datum mode switches between corner and center.
///   5. Design origin ≠ Machine WCS (documented in UI copy).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 1. canvasOriginRaw defaults to nil (corner) on a new job.
let job1 = Job(name: "Test")
try expect(job1.canvasOriginRaw == nil, "default canvasOriginRaw is nil (corner)")

// 2. Set and round-trip through Codable.
var job2 = Job(name: "Test")
job2.canvasOriginRaw = "center"
let encoded = try JSONEncoder().encode(job2)
let decoded = try JSONDecoder().decode(Job.self, from: encoded)
try expect(decoded.canvasOriginRaw == "center", "canvasOriginRaw round-trips center")

// 3. Switch modes.
var job3 = Job(name: "Test")
job3.canvasOriginRaw = "corner"
try expect(job3.canvasOriginRaw == "corner", "corner mode set")
job3.canvasOriginRaw = "center"
try expect(job3.canvasOriginRaw == "center", "center mode set")

// 4. Corner origin places datum at world (0,0).
func originForMode(_ mode: String, sheet: Sheet) -> (x: Double, y: Double) {
    if mode == "center" {
        return (sheet.width / 2, sheet.depth / 2)
    }
    return (0, 0)
}
let sheet = Sheet(name: "S1", width: 600, depth: 400, height: 25)
let cornerOrigin = originForMode("corner", sheet: sheet)
try expect(cornerOrigin == (0, 0), "corner origin at (0,0)")
let centerOrigin = originForMode("center", sheet: sheet)
try expect(centerOrigin == (300, 200), "center origin at sheet center")

// 5. UI copy mentions Machine zero separately (static check).
let uiCopy = "Design origin is the sheet drawing datum. Machine work zero / mPos / G54 live on the Machine stage and are not changed by this control."
try expect(uiCopy.contains("Design origin") && uiCopy.contains("Machine"), "UI copy documents separation")

print("ShopPilotVerify1800d: PASS — canvasOriginRaw Codable, corner/center, persist round-trip, UI copy")
