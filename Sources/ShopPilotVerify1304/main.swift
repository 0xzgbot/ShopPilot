import Foundation
import ShopPilotCore

/// SPK-1304 verify (CLT, no XCTest).
/// Proves the WORK OFFSET REGISTRY (G54–G59) contract:
///   1. init() seeds exactly 6 offsets, gcodes G54…G59 in order, names
///      "Fixture 1"…"Fixture 6".
///   2. activeIndex defaults to 0 → activeGcode "G54".
///   3. setActive(2) → true + activeGcode "G56"; out-of-range (9, −1)
///      → false and activeIndex unchanged.
///   4. update mutates only the target offset's given fields; out-of-range
///      → false no-op.
///   5. Codable round-trip preserves offsets AND activeIndex.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Seeding: 6 offsets, G54…G59 in order. ─────────────────────────
    let registry = WorkOffsetRegistry()
    try expect(registry.offsets.count == 6, "init seeds exactly 6 offsets (got \(registry.offsets.count))")
    let expectedGcodes = ["G54", "G55", "G56", "G57", "G58", "G59"]
    for (i, gcode) in expectedGcodes.enumerated() {
        try expect(registry.offsets[i].gcode == gcode,
                   "offset[\(i)].gcode == \(gcode) (got \(registry.offsets[i].gcode))")
        try expect(registry.offsets[i].name == "Fixture \(i + 1)",
                   "offset[\(i)].name == Fixture \(i + 1) (got \(registry.offsets[i].name))")
    }

    // ── 2. Active defaults to G54. ───────────────────────────────────────
    try expect(registry.activeIndex == 0, "activeIndex defaults to 0 (got \(registry.activeIndex))")
    try expect(registry.activeGcode == "G54", "activeGcode defaults to G54 (got \(registry.activeGcode))")
    try expect(registry.active.name == "Fixture 1", "active offset is Fixture 1")

    // ── 3. setActive: valid switch + out-of-range rejection. ─────────────
    try expect(registry.setActive(2) == true, "setActive(2) returns true")
    try expect(registry.activeIndex == 2, "activeIndex == 2 after setActive(2) (got \(registry.activeIndex))")
    try expect(registry.activeGcode == "G56", "activeGcode == G56 (got \(registry.activeGcode))")
    try expect(registry.setActive(9) == false, "setActive(9) returns false")
    try expect(registry.activeIndex == 2, "activeIndex still 2 after invalid setActive(9) (got \(registry.activeIndex))")
    try expect(registry.setActive(-1) == false, "setActive(-1) returns false")
    try expect(registry.activeIndex == 2, "activeIndex still 2 after invalid setActive(-1)")

    // ── 4. update: mutate target only; out-of-range no-op. ───────────────
    try expect(registry.update(x: 12.5, at: 1) == true, "update(x: 12.5, at: 1) returns true")
    try expect(registry.offsets[1].x == 12.5, "offsets[1].x == 12.5 (got \(registry.offsets[1].x))")
    try expect(registry.offsets[1].y == 0 && registry.offsets[1].z == 0, "untouched y/z of offset[1] stay 0")
    try expect(registry.offsets[0].x == 0, "offset[0] untouched by update at index 1")
    try expect(registry.update(at: 99) == false, "update(at: 99) returns false")

    // ── 5. Codable round-trip preserves offsets + activeIndex. ───────────
    try expect(registry.setActive(3) == true, "setActive(3) before persistence check")
    _ = registry.update(name: "A", x: 1, y: 2, z: 3, at: 4)
    try expect(registry.offsets[4].name == "A", "offsets[4].name == A (got \(registry.offsets[4].name))")
    let data = try JSONEncoder().encode(registry)
    let decoded = try JSONDecoder().decode(WorkOffsetRegistry.self, from: data)
    try expect(decoded.activeIndex == 3, "decoded activeIndex == 3 (got \(decoded.activeIndex))")
    try expect(decoded.offsets.count == 6, "decoded offsets.count == 6 (got \(decoded.offsets.count))")
    try expect(decoded.offsets[4].name == "A", "decoded offsets[4].name == A (got \(decoded.offsets[4].name))")
    try expect(decoded.offsets[4].x == 1 && decoded.offsets[4].y == 2 && decoded.offsets[4].z == 3,
               "decoded offsets[4] x/y/z == 1/2/3 (got \(decoded.offsets[4].x)/\(decoded.offsets[4].y)/\(decoded.offsets[4].z))")
    try expect(decoded.offsets[4].gcode == "G58", "decoded offsets[4].gcode == G58 (got \(decoded.offsets[4].gcode))")

    print("ShopPilotVerify1304: PASS — work offsets G54–G59: seed order, active default G54, setActive validation, update mutation, Codable round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1304: FAIL — \(error)")
    exit(1)
}
