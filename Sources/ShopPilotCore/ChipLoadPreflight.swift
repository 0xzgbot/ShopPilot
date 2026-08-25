import Foundation

// MARK: - Chip-load preflight (SPK-2023a, warning tier only)

/// One material's target chip-load window, decoded from
/// `Resources/bit_feeds_seed.json` (seeded from
/// `docs/planning/research/BIT_FEEDS_LIBRARY.md` §4).
public struct BitFeedsMaterial: Codable, Sendable, Equatable {
    public var name: String
    public var displayName: String
    public var aliases: [String]
    public var chipLoadMinMmPerTooth: Double
    public var chipLoadMaxMmPerTooth: Double

    /// Case/whitespace-insensitive match on the canonical name or any alias
    /// ("Pine" → softwood, "Baltic Birch" → plywood).
    public func matches(_ materialName: String) -> Bool {
        let key = materialName.trimmingCharacters(in: .whitespaces).lowercased()
        if name.lowercased() == key { return true }
        return aliases.contains { $0.lowercased() == key }
    }
}

/// One bit-diameter band of hobby-router feed data for a material
/// (seeded from BIT_FEEDS_LIBRARY.md §3 tables; feed/plunge ranges derived —
/// see the seed's `metadata.derivedNote`).
public struct BitFeedsBand: Codable, Sendable, Equatable {
    public var material: String
    public var bitDiameterMinMm: Double
    public var bitDiameterMaxMm: Double
    /// The doc's tabulated point feed this band was anchored on (provenance only).
    public var feedRateAnchorMmPerMin: Double
    public var feedRateMinMmPerMin: Double
    public var feedRateMaxMmPerMin: Double
    public var plungeRateMinMmPerMin: Double
    public var plungeRateMaxMmPerMin: Double
    public var spindleRpmMin: Int
    public var spindleRpmMax: Int
}

public struct BitFeedsSeedMetadata: Codable, Sendable {
    public var source: String
    public var generated: String
    public var machineClass: String
    public var status: String
    public var derivedNote: String?
    public var derivedFields: [String]?
}

/// Root shape of `bit_feeds_seed.json`.
public struct BitFeedsSeed: Codable, Sendable {
    public var metadata: BitFeedsSeedMetadata
    public var materials: [BitFeedsMaterial]
    public var bands: [BitFeedsBand]
}

/// Loader + pure evaluator for the chip-load preflight warning.
///
/// Chip load (mm/tooth) = feed rate (mm/min) / (RPM × flutes). Outside the
/// seeded per-material window → WARNING tier only — never blocks export or
/// recalc (BIT_FEEDS_LIBRARY.md: all values are conservative starting points;
/// the user test-cuts and tunes).
public enum BitFeedsLibrary {

    /// Decode the bundled seed. Nil when the resource is missing/corrupt
    /// (callers then skip the check — absence of data must not warn).
    public static func loadSeed(bundle: Bundle? = nil) -> BitFeedsSeed? {
        // Bundle.module is internal — resolve the default inside.
        let target = bundle ?? Bundle.module
        guard let url = target.url(forResource: "bit_feeds_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(BitFeedsSeed.self, from: data)
    }

    /// Process-wide seed snapshot (loaded once; tests may pass their own).
    public static let shared: BitFeedsSeed? = loadSeed()
}

public enum ChipLoadVerdict: Equatable, Sendable {
    /// Computed chip load is inside (or on the edge of) the material window.
    case ok
    /// Out of window — carries the computed value and the recommended range
    /// text ("0.040–0.060 mm/tooth") for surfacing.
    case warning(computedMmPerTooth: Double, recommendedText: String)
    /// No usable seed data for these inputs — stay silent.
    case noData(reason: String)
}

public enum ChipLoadPreflight {

    /// Edge tolerance so a computed value exactly ON a range edge is .ok
    /// (no false positives from binary-float representation).
    static let edgeToleranceMm: Double = 1e-9

    /// The formula from BIT_FEEDS_LIBRARY.md §1. Nil when inputs are
    /// unusable (non-positive rpm/flutes/feed) rather than division-by-zero.
    public static func chipLoad(feedRateMmPerMin: Double, rpm: Double, flutes: Int) -> Double? {
        guard flutes > 0, rpm > 0, feedRateMmPerMin > 0 else { return nil }
        return feedRateMmPerMin / (rpm * Double(flutes))
    }

    static func recommendedText(_ material: BitFeedsMaterial) -> String {
        String(format: "%.3f–%.3f mm/tooth",
               material.chipLoadMinMmPerTooth, material.chipLoadMaxMmPerTooth)
    }

    /// Pure evaluator: given (material, bit Ø, feed, rpm, flutes), compute
    /// chip load and compare against the seeded per-material window.
    public static func evaluate(
        material materialName: String?,
        bitDiameterMm: Double,
        feedRateMmPerMin: Double,
        rpm: Double,
        flutes: Int,
        seed: BitFeedsSeed? = BitFeedsLibrary.shared
    ) -> ChipLoadVerdict {
        guard let seed else {
            return .noData(reason: "bit-feeds seed unavailable")
        }
        guard let computed = chipLoad(feedRateMmPerMin: feedRateMmPerMin, rpm: rpm, flutes: flutes) else {
            return .noData(reason: "feed/rpm/flutes not resolvable")
        }
        guard let materialName, !materialName.isEmpty,
              let material = seed.materials.first(where: { $0.matches(materialName) }) else {
            return .noData(reason: "no cutting data for material")
        }
        // Diameter bands carry feed/plunge/RPM context; the chip-load window
        // itself is per-material (§4). A diameter outside 1–6 mm is beyond the
        // seeded hobby class — still evaluate the material window (the chip
        // load math does not depend on diameter), but note nothing special.
        _ = seed.bands.first {
            $0.material == material.name
                && bitDiameterMm >= $0.bitDiameterMinMm
                && bitDiameterMm <= $0.bitDiameterMaxMm
        }
        let text = recommendedText(material)
        if computed < material.chipLoadMinMmPerTooth - edgeToleranceMm
            || computed > material.chipLoadMaxMmPerTooth + edgeToleranceMm {
            return .warning(computedMmPerTooth: computed, recommendedText: text)
        }
        return .ok
    }
}
