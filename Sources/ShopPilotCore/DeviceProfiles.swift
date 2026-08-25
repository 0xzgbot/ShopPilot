import Foundation

// MARK: - Device profile library (SPK-2022d)
//
// One pick in the connection picker sets everything machine-specific at once:
// serial baud, post flavor, travel envelope and origin convention. The bundled
// JSON catalog seeds the common hobby routers; an unknown machine falls back
// to the Generic GRBL profile which NEVER blocks connecting (Safety Req #9 —
// nothing here auto-connects or auto-runs).

/// Where the operator's work origin conventionally sits for this machine class.
public enum OriginConvention: String, Codable, Sendable, CaseIterable {
    case frontLeft = "front-left"
    case backRight = "back-right"
    case backLeft = "back-left"
    case unspecified

    public var displayName: String {
        switch self {
        case .frontLeft: return "Front-left"
        case .backRight: return "Back-right"
        case .backLeft: return "Back-left"
        case .unspecified: return "User-set"
        }
    }
}

/// A machine's one-choice setup: post flavor + baud + travel + origin.
/// Codable/Sendable, legacy-safe decode (every field but `id` defaults, so
/// older/partial catalog entries still decode — same style as
/// `RotaryWrapToolpathParams`).
public struct DeviceProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    /// Serial baud rate to apply on connect (GRBL-class: 115200).
    public var baud: Int
    /// PostTemplate id (see `PostTemplate.shipped(byID:)`) applied when posting jobs.
    public var postID: String
    /// Travel envelope in millimetres. `0` means unknown (no soft-limit warn).
    public var travelXMm: Double
    public var travelYMm: Double
    public var travelZMm: Double
    public var originConvention: OriginConvention
    public var notes: String

    public init(
        id: String,
        name: String,
        baud: Int = 115200,
        postID: String = "grbl-mm",
        travelXMm: Double = 0,
        travelYMm: Double = 0,
        travelZMm: Double = 0,
        originConvention: OriginConvention = .unspecified,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.baud = baud
        self.postID = postID
        self.travelXMm = travelXMm
        self.travelYMm = travelYMm
        self.travelZMm = travelZMm
        self.originConvention = originConvention
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baud, postID
        case travelXMm, travelYMm, travelZMm
        case originConvention, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        baud = try c.decodeIfPresent(Int.self, forKey: .baud) ?? 115200
        postID = try c.decodeIfPresent(String.self, forKey: .postID) ?? "grbl-mm"
        travelXMm = try c.decodeIfPresent(Double.self, forKey: .travelXMm) ?? 0
        travelYMm = try c.decodeIfPresent(Double.self, forKey: .travelYMm) ?? 0
        travelZMm = try c.decodeIfPresent(Double.self, forKey: .travelZMm) ?? 0
        originConvention = try c.decodeIfPresent(OriginConvention.self, forKey: .originConvention) ?? .unspecified
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(baud, forKey: .baud)
        try c.encode(postID, forKey: .postID)
        try c.encode(travelXMm, forKey: .travelXMm)
        try c.encode(travelYMm, forKey: .travelYMm)
        try c.encode(travelZMm, forKey: .travelZMm)
        try c.encode(originConvention, forKey: .originConvention)
        try c.encode(notes, forKey: .notes)
    }

    /// True when every axis has a usable travel figure (soft limits can warn).
    public var travelKnown: Bool { travelXMm > 0 && travelYMm > 0 && travelZMm > 0 }

    /// Smallest XY travel — the simulator's single-axis soft-limit envelope.
    public var simTravelLimitMM: Double? {
        guard travelXMm > 0, travelYMm > 0 else { return nil }
        return min(travelXMm, travelYMm)
    }
}

// MARK: - Catalog

public enum DeviceProfileCatalog {

    /// The never-blocks-connect fallback for unknown machines (§SPK-2022d AC).
    public static let genericID = "generic-grbl"

    /// Built-in mirror of the bundled JSON — used verbatim if the resource is
    /// missing/unreadable so the picker always has something valid to offer.
    public static let builtin: [DeviceProfile] = [
        DeviceProfile(
            id: "longmill-mk2-30x30", name: "LongMill MK2 30×30",
            baud: 115200, postID: "longmill-mm",
            travelXMm: 782, travelYMm: 782, travelZMm: 110,
            originConvention: .frontLeft,
            notes: "approx — Sienci published work area; verify $130–$132"),
        DeviceProfile(
            id: "shapeoko-3", name: "Shapeoko 3",
            baud: 115200, postID: "shapeoko-mm",
            travelXMm: 425, travelYMm: 418, travelZMm: 89,
            originConvention: .frontLeft,
            notes: "approx — Carbide 3D standard-size work area; verify $130–$132"),
        DeviceProfile(
            id: "shapeoko-4", name: "Shapeoko 4 (XL)",
            baud: 115200, postID: "shapeoko-mm",
            travelXMm: 838, travelYMm: 440, travelZMm: 89,
            originConvention: .frontLeft,
            notes: "approx — Carbide 3D XL work area; verify $130–$132"),
        DeviceProfile(
            id: "onefinity-woodworker", name: "OneFinity Woodworker",
            baud: 115200, postID: "onefinity-mm",
            travelXMm: 812, travelYMm: 812, travelZMm: 133,
            originConvention: .frontLeft,
            notes: "approx — Buildbotics controller, 32″×32″ class; verify machine settings"),
        DeviceProfile(
            id: "workbee-1000", name: "WorkBee (1000×1000)",
            baud: 115200, postID: "workbee-mm",
            travelXMm: 970, travelYMm: 970, travelZMm: 115,
            originConvention: .frontLeft,
            notes: "approx — Ooznest Z1+ 1m-class kit; verify $130–$132"),
        DeviceProfile(
            id: "generic-grbl", name: "Generic GRBL",
            baud: 115200, postID: "grbl-mm",
            travelXMm: 500, travelYMm: 500, travelZMm: 100,
            originConvention: .unspecified,
            notes: "Fallback for unknown machines — placeholder travel, treat as unknown until measured"),
    ]

    /// Decode a catalog document. Public so CLT verifiers exercise the exact
    /// production decoder.
    public static func decode(_ data: Data) throws -> [DeviceProfile] {
        try JSONDecoder().decode([DeviceProfile].self, from: data)
    }

    /// URL of the bundled catalog JSON (public because `Bundle.module` is
    /// internal to ShopPilotCore; CLT verifiers prove the resource shipped).
    public static var bundledResourceURL: URL? {
        Bundle.module.url(forResource: "DeviceProfiles", withExtension: "json")
    }

    /// The bundled catalog (ShopPilotCore/Resources/DeviceProfiles.json),
    /// falling back to the built-in mirror if the resource can't be read.
    public static var bundled: [DeviceProfile] {
        guard let url = Bundle.module.url(forResource: "DeviceProfiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let profiles = try? decode(data), !profiles.isEmpty else {
            return builtin
        }
        return profiles
    }

    /// Look up a profile by id in the bundled catalog.
    public static func profile(id: String) -> DeviceProfile? {
        bundled.first { $0.id == id }
    }

    /// Resolve any selection (including unknown/stale ids) to a real profile.
    /// Unknown machines land on Generic — resolution NEVER returns nil, so a
    /// bad stored id can never block connect.
    public static func resolved(id: String) -> DeviceProfile {
        profile(id: id) ?? fallback
    }

    /// The Generic GRBL fallback profile.
    public static var fallback: DeviceProfile {
        profile(id: genericID) ?? builtin.last!
    }
}

// MARK: - Last-used persistence

/// Persists the last-used device profile id (UserDefaults — same pattern as
/// CanvasOverlayOptions). Round-trip verified by ShopPilotVerify2022d.
public enum LastDeviceProfileStore {
    public static let defaultsKey = "shop_pilot_last_device_profile_id"

    public static func load() -> String? {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        return (raw?.isEmpty == true) ? nil : raw
    }

    public static func save(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultsKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Soft-limit awareness (§2.4 non-negotiable)

/// Jog-time soft-limit advisor. When the active profile knows the machine's
/// travel, warn BEFORE the move would leave the envelope; when travel is
/// unknown, surface that fact instead of pretending it is safe.
public enum SoftLimitAdvisor {

    /// Warnings for a proposed jog of `stepMm` (signed by caller per direction
    /// — pass the raw step size; both directions are checked here) from the
    /// current machine position, against GRBL's convention that the work
    /// envelope runs 0…travel on each axis. Empty when every proposed move is
    /// inside the envelope.
    public static func warnings(
        currentX: Double, currentY: Double, currentZ: Double,
        stepMm: Double,
        profile: DeviceProfile?
    ) -> [String] {
        guard let profile, profile.travelKnown else { return [] }
        var out: [String] = []
        let eps = 1e-6

        func check(_ axis: String, current: Double, travel: Double) {
            let up = current + abs(stepMm)
            let down = current - abs(stepMm)
            if up > travel + eps && down < -eps {
                out.append("\(axis): ±\(trim(stepMm))mm leaves travel in BOTH directions (0…\(trim(travel))mm)")
            } else if up > travel + eps {
                out.append("\(axis): +\(trim(stepMm))mm passes \(trim(travel))mm travel limit")
            } else if down < -eps {
                out.append("\(axis): −\(trim(stepMm))mm passes 0 limit")
            }
        }

        check("X", current: currentX, travel: profile.travelXMm)
        check("Y", current: currentY, travel: profile.travelYMm)
        check("Z", current: currentZ, travel: profile.travelZMm)
        return out
    }

    /// The §2.4 "warn if unknown" line shown when no known-travel profile is
    /// active. Nil once travel is known.
    public static func unknownTravelNotice(profile: DeviceProfile?) -> String? {
        guard !(profile?.travelKnown ?? false) else { return nil }
        return "Machine travel unknown — pick a device profile to enable soft-limit warnings."
    }

    private static func trim(_ v: Double) -> String {
        v >= 10 ? String(format: "%.0f", v) : String(format: "%g", v)
    }
}
