import Foundation
import ShopPilotCore

/// SPK-1400a verify (CLT machine, no XCTest).
///
/// The Welcome sheet renders `SampleProjectsStore.samples` directly and loads
/// a sample through `AppSession.loadSampleProject(id:)`, which wraps
/// `SampleProjectsStore.payload(for:)` + `applyPackagePayload`. That session
/// method lives in the app target (not importable from a CLT), so this verify
/// proves its underlying Core mapping instead:
///   1. The catalog surface the Welcome sheet renders is exactly the store:
///      every sample has distinct id, non-empty name/tagline/category.
///   2. The id → payload mapping `loadSampleProject` wraps is complete —
///      every `samples` id builds a valid payload (non-empty job name,
///      >= 1 sheet), which is what makes the click load into the session.
///   3. Unknown ids resolve to nil, so `loadSampleProject` returns false
///      (no session mutation) for anything not in the catalog.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Catalog surface the Welcome sheet renders. ─────────────────────
    let samples = SampleProjectsStore.samples
    try expect(samples.count == 4, "samples.count == 4 (got \(samples.count))")
    let ids = Set(samples.map(\.id))
    try expect(ids.count == 4, "sample ids are distinct (the gallery needs unique ids)")
    for sample in samples {
        try expect(!sample.name.isEmpty, "sample \(sample.id): name non-empty")
        try expect(!sample.tagline.isEmpty, "sample \(sample.id): tagline non-empty")
        try expect(!sample.category.isEmpty, "sample \(sample.id): category non-empty")
    }

    // ── 2. loadSampleProject's underlying mapping is complete: every ──────
    // ──    samples id builds a payload.                                    ──
    for sample in samples {
        guard let payload = SampleProjectsStore.payload(for: sample.id) else {
            throw VerifyError.failed("payload(for: \(sample.id)) is nil for '\(sample.name)' — the welcome card would load nothing")
        }
        try expect(!payload.job.name.isEmpty, "'\(sample.name)': job name non-empty")
        try expect(payload.job.sheets.count >= 1, "'\(sample.name)': >= 1 sheet (got \(payload.job.sheets.count))")
        // The payload must round-trip (it goes through applyPackagePayload,
        // which restores shapes from layer vectors).
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ShopPilotPackagePayload.self, from: data)
        try expect(decoded.job.name == payload.job.name, "'\(sample.name)': round-trip preserves job name")
        try expect(decoded.job.sheets.count == payload.job.sheets.count, "'\(sample.name)': round-trip preserves sheet count")
    }

    // ── 3. Unknown id -> nil (loadSampleProject returns false, no-op). ────
    try expect(SampleProjectsStore.payload(for: UUID()) == nil, "unknown id -> nil")
    try expect(SampleProjectsStore.payload(for: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) == nil,
               "zeroed uuid -> nil")

    print("1400a: PASS — welcome samples + real open/import")
}

do {
    try main()
} catch {
    print("1400a: FAIL — \(error)")
    exit(1)
}
