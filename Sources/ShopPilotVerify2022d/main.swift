import Foundation
import ShopPilotCore

// SPK-2022d — device profile library verifier.
// AC: catalog decodes, all six profiles present, Generic fallback exists and
// never blocks, choosing a profile yields expected baud/post/travel, last-used
// id persists round-trip, soft-limit advisor warns only with known travel.

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── AC1 — bundled catalog decodes with all six profiles. ────────────────
    let bundled = DeviceProfileCatalog.bundled
    let ids = Set(bundled.map(\.id))
    let required: Set<String> = [
        "longmill-mk2-30x30", "shapeoko-3", "shapeoko-4",
        "onefinity-woodworker", "workbee-1000", "generic-grbl",
    ]
    try expect(ids.isSuperset(of: required),
               "bundled catalog must contain all six profiles, got \(ids.sorted())")
    try expect(bundled.count == 6,
               "expected exactly 6 bundled profiles, got \(bundled.count)")

    // The catalog really came off the bundled JSON resource (not the Swift
    // mirror alone): decode the resource directly too.
    guard let url = DeviceProfileCatalog.bundledResourceURL else {
        throw VerifyError.failed("DeviceProfiles.json missing from ShopPilotCore bundle")
    }
    let rawData = try Data(contentsOf: url)
    let decoded = try DeviceProfileCatalog.decode(rawData)
    try expect(decoded.count == 6, "raw JSON decode must yield 6 profiles")
    try expect(decoded.contains { $0.id == "generic-grbl" }, "raw JSON contains the Generic profile")

    // ── AC2 — Generic fallback exists and never blocks connect. ─────────────
    let generic = DeviceProfileCatalog.fallback
    try expect(generic.id == DeviceProfileCatalog.genericID,
               "fallback must be the Generic GRBL profile")
    try expect(generic.baud == 115200, "Generic baud must be GRBL-typical 115200")
    // Unknown / stale / empty ids all resolve to a real profile — resolution
    // never returns nil, so a bad stored id can never block connecting.
    for stale in ["", "does-not-exist", "machine-from-a-prior-install"] {
        let resolved = DeviceProfileCatalog.resolved(id: stale)
        try expect(resolved.id == DeviceProfileCatalog.genericID,
                   "unknown id '\(stale)' must resolve to Generic, got \(resolved.id)")
    }

    // ── AC3 — one choice yields expected baud + post + travel + origin. ─────
    let longmill = DeviceProfileCatalog.profile(id: "longmill-mk2-30x30")
    try expect(longmill?.baud == 115200, "LongMill baud 115200")
    try expect(longmill?.postID == "longmill-mm", "LongMill post id 'longmill-mm'")
    try expect(longmill?.travelXMm == 782 && longmill?.travelYMm == 782
               && longmill?.travelZMm == 110, "LongMill travel 782×782×110")
    try expect(longmill?.originConvention == .frontLeft, "LongMill origin front-left")

    let shapeoko3 = DeviceProfileCatalog.profile(id: "shapeoko-3")
    try expect(shapeoko3?.postID == "shapeoko-mm" && shapeoko3?.baud == 115200,
               "Shapeoko 3 post/baud")
    try expect(shapeoko3?.travelYMm == 418 && shapeoko3?.travelZMm == 89,
               "Shapeoko 3 travel Y/Z")

    let onefinity = DeviceProfileCatalog.profile(id: "onefinity-woodworker")
    try expect(onefinity?.postID == "onefinity-mm" && onefinity?.travelZMm == 133,
               "OneFinity post/travel")

    let workbee = DeviceProfileCatalog.profile(id: "workbee-1000")
    try expect(workbee?.postID == "workbee-mm" && workbee?.travelXMm == 970,
               "WorkBee post/travel")

    // Every profile's post id must point at a real shipped PostTemplate —
    // the picker's "sets the post in one choice" promise is only true if the
    // id actually resolves.
    for p in bundled {
        try expect(PostTemplate.shipped(byID: p.postID) != nil,
                   "\(p.name) references unknown post '\(p.postID)'")
    }

    // ── AC4 — legacy-safe decode: partial JSON gets defaults, not a throw. ──
    let partial = try JSONDecoder().decode(DeviceProfile.self,
                                           from: Data(#"{"id":"legacy-entry"}"#.utf8))
    try expect(partial.name == "legacy-entry", "missing name falls back to id")
    try expect(partial.baud == 115200, "missing baud defaults to 115200")
    try expect(partial.postID == "grbl-mm", "missing post defaults to grbl-mm")
    try expect(!partial.travelKnown, "missing travel decodes as unknown")
    try expect(partial.originConvention == .unspecified, "missing origin is unspecified")
    let roundTrip = try JSONDecoder().decode(
        DeviceProfile.self,
        from: JSONEncoder().encode(longmill!))
    try expect(roundTrip == longmill, "encode/decode round-trips every field")

    // ── AC5 — last-used profile id persists round-trip. ─────────────────────
    let previous = LastDeviceProfileStore.load()
    defer {
        if let previous { LastDeviceProfileStore.save(previous) } else { LastDeviceProfileStore.clear() }
    }
    LastDeviceProfileStore.save("longmill-mk2-30x30")
    try expect(LastDeviceProfileStore.load() == "longmill-mk2-30x30",
               "saved profile id must load back")
    // And resolving what was loaded gives the full profile back after a
    // "relaunch": id → catalog → baud/post/travel in one step.
    let restored = DeviceProfileCatalog.resolved(id: LastDeviceProfileStore.load() ?? "")
    try expect(restored.baud == 115200 && restored.postID == "longmill-mm"
               && restored.travelXMm == 782, "persisted id resolves to the full profile")

    // ── AC6 — §2.4 soft-limit jog awareness. ────────────────────────────────
    // Known travel + move that stays inside → no warnings.
    let quiet = SoftLimitAdvisor.warnings(
        currentX: 100, currentY: 100, currentZ: 10,
        stepMm: 10, profile: longmill)
    try expect(quiet.isEmpty, "in-envelope jog must not warn")

    // Known travel + X jog past the +X limit → warn naming the axis.
    let pastX = SoftLimitAdvisor.warnings(
        currentX: 775, currentY: 400, currentZ: 50,
        stepMm: 10, profile: longmill)
    try expect(pastX.count == 1 && pastX[0].hasPrefix("X:"),
               "past-+X-limit jog warns on X only, got \(pastX)")

    // Below-zero side warns too.
    let pastZero = SoftLimitAdvisor.warnings(
        currentX: 5, currentY: 400, currentZ: 50,
        stepMm: 10, profile: longmill)
    try expect(pastZero.count == 1 && pastZero[0].contains("0 limit"),
               "negative-side jog warns against the 0 limit, got \(pastZero)")

    // Unknown travel (nil or placeholder) → no false limits, but an honest
    // §2.4 notice instead.
    let none = SoftLimitAdvisor.warnings(
        currentX: 9_999, currentY: 0, currentZ: 0, stepMm: 100, profile: nil)
    try expect(none.isEmpty, "no profile → no numeric warnings (keeps today's behavior)")
    try expect(SoftLimitAdvisor.unknownTravelNotice(profile: nil) != nil,
               "unknown travel surfaces the §2.4 notice")
    try expect(SoftLimitAdvisor.unknownTravelNotice(profile: longmill) == nil,
               "known travel clears the notice")

    print("ShopPilotVerify2022d: PASS — 6-profile catalog decodes from bundle, Generic fallback never blocks (\(DeviceProfileCatalog.genericID)), one pick sets baud+post+travel+origin (all posts resolve to shipped templates), legacy-safe decode, last-used id persists round-trip, soft-limit advisor warns near limits and honestly when travel unknown")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2022d: FAIL — \(error)")
    exit(1)
}
