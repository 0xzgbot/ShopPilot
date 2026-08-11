import Foundation
import ShopPilotCore

/// SPK-1313 verify (CLT machine, no XCTest).
/// Proves the SampleProjectsStore contract:
///   1. Exactly 4 samples; ids distinct; categories all different.
///   2. Every sample builds a payload: non-empty job name, >= 1 sheet,
///      >= 1 layer named 'Layer 1' with >= 2 vectors.
///   3. Payloads are deterministic — two builds of the same sample id
///      yield equal job names (and equal sheet counts).
///   4. Codable round-trip: encode -> decode preserves job name + sheet count.
///   5. Unknown id -> nil; out-of-range index -> nil.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Exactly 4 samples, distinct ids + categories. ────────────────
    let samples = SampleProjectsStore.samples
    try expect(samples.count == 4, "samples.count == 4 (got \(samples.count))")
    let ids = Set(samples.map(\.id))
    try expect(ids.count == 4, "sample ids are distinct")
    let categories = Set(samples.map(\.category))
    try expect(categories.count == 4, "categories are distinct (got \(categories.sorted()))")
    try expect(categories == ["Sign", "Box", "Keychain", "Plaque"],
               "categories are Sign/Box/Keychain/Plaque (got \(categories.sorted()))")

    let expectedNames = [
        "Sign — V-Carve Greeting",
        "Box — Finger Joints",
        "Keychain — Dogbone",
        "Plaque — Text Relief",
    ]
    for (i, sample) in samples.enumerated() {
        try expect(sample.name == expectedNames[i], "sample[\(i)].name == \(expectedNames[i]) (got \(sample.name))")
        try expect(!sample.tagline.isEmpty, "sample[\(i)].tagline non-empty")
        try expect(!sample.category.isEmpty, "sample[\(i)].category non-empty")
    }

    // ── 2. Every sample builds a valid payload. ──────────────────────────
    for sample in samples {
        guard let payload = SampleProjectsStore.payload(for: sample.id) else {
            throw VerifyError.failed("payload(for: \(sample.id)) is nil for \(sample.name)")
        }
        try expect(!payload.job.name.isEmpty, "\(sample.name): job name non-empty")
        try expect(payload.job.sheets.count >= 1, "\(sample.name): >= 1 sheet (got \(payload.job.sheets.count))")
        guard let sheet = payload.job.sheets.first else {
            throw VerifyError.failed("\(sample.name): no first sheet")
        }
        try expect(sheet.layers.count >= 1, "\(sample.name): >= 1 layer (got \(sheet.layers.count))")
        guard let layer = sheet.layers.first else {
            throw VerifyError.failed("\(sample.name): no first layer")
        }
        try expect(layer.name == "Layer 1", "\(sample.name): first layer named 'Layer 1' (got \(layer.name))")
        try expect(layer.vectors.count >= 2, "\(sample.name): >= 2 vectors (got \(layer.vectors.count))")
        // Sensible stock: positive width/depth/height.
        try expect(sheet.width > 0 && sheet.depth > 0 && sheet.height > 0,
                   "\(sample.name): positive sheet dimensions")
        // Vectors live on the layer that owns them.
        try expect(layer.vectors.allSatisfy { $0.layerId == layer.id },
                   "\(sample.name): all vectors reference the owning layer")
    }

    // ── 3. Determinism: two builds of the same id agree. ─────────────────
    for sample in samples {
        guard let a = SampleProjectsStore.payload(for: sample.id),
              let b = SampleProjectsStore.payload(for: sample.id) else {
            throw VerifyError.failed("double build returned nil for \(sample.name)")
        }
        try expect(a.job.name == b.job.name, "\(sample.name): deterministic job name")
        try expect(a.job.sheets.count == b.job.sheets.count, "\(sample.name): deterministic sheet count")
        try expect(a.job.sheets.first?.layers.count == b.job.sheets.first?.layers.count,
                   "\(sample.name): deterministic layer count")
    }

    // ── 4. Codable round-trip per sample. ────────────────────────────────
    for sample in samples {
        guard let payload = SampleProjectsStore.payload(for: sample.id) else {
            throw VerifyError.failed("round-trip: no payload for \(sample.name)")
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw VerifyError.failed("\(sample.name): encode failed — \(error)")
        }
        let decoded: ShopPilotPackagePayload
        do {
            decoded = try JSONDecoder().decode(ShopPilotPackagePayload.self, from: data)
        } catch {
            throw VerifyError.failed("\(sample.name): decode failed — \(error)")
        }
        try expect(decoded.job.name == payload.job.name,
                   "\(sample.name): round-trip job name preserved")
        try expect(decoded.job.sheets.count == payload.job.sheets.count,
                   "\(sample.name): round-trip sheet count preserved (got \(decoded.job.sheets.count))")
        try expect(decoded.job.sheets.first?.layers.count == payload.job.sheets.first?.layers.count,
                   "\(sample.name): round-trip layer count preserved")
        try expect(decoded.job.sheets.first?.layers.first?.vectors.count == payload.job.sheets.first?.layers.first?.vectors.count,
                   "\(sample.name): round-trip vector count preserved")
    }

    // ── 5. Unknown id / out-of-range index -> nil. ───────────────────────
    try expect(SampleProjectsStore.payload(for: UUID()) == nil, "unknown id -> nil")
    try expect(SampleProjectsStore.payload(for: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) == nil,
               "zeroed uuid -> nil")
    try expect(SampleProjectsStore.payload(for: -1) == nil, "index -1 -> nil")
    try expect(SampleProjectsStore.payload(for: samples.count) == nil, "index == count -> nil")
    try expect(SampleProjectsStore.payload(for: 999) == nil, "index 999 -> nil")
    for i in 0..<samples.count {
        try expect(SampleProjectsStore.payload(for: i) != nil, "index \(i) -> payload")
    }

    print("ShopPilotVerify1313: PASS — 4 samples, distinct ids/categories, valid payloads (sheets/layers/vectors), deterministic builds, Codable round-trip, nil guards")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1313: FAIL — \(error)")
    exit(1)
}
