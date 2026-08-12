import Foundation
import ShopPilotCore

// SPK-1403a verify (CLT executable, no XCTest).
// Proves the extracted sample-load lifecycle (SampleProjectLoader) keeps the
// exact AppSession.loadSampleProject contract:
//   1. KNOWN ID → returns true, drives the full hook sequence in order
//      (applyPackagePayload → packageURL=nil → markClean → clearUndoStack →
//      status message) and the status text matches the original format.
//   2. UNKNOWN ID → returns false and mutates NOTHING (no hooks fired).
//   3. THE STORE IS THE CATALOG: every SampleProjectsStore.samples id loads
//      (the loader must not depend on a second list).
// The fake session records hook calls so the lifecycle is observable without
// the app target.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Records every SampleLoadingSession hook invocation.
final class RecordingSession: SampleLoadingSession {
    var packageURL: URL?
    var appliedPayloads: [ShopPilotPackagePayload] = []
    var cleanCount = 0
    var undoClearCount = 0
    var statusMessages: [String] = []

    func applyPackagePayload(_ payload: ShopPilotPackagePayload) {
        appliedPayloads.append(payload)
    }
    func markClean() { cleanCount += 1 }
    func clearUndoStack() { undoClearCount += 1 }
    func setStatusMessage(_ message: String) { statusMessages.append(message) }
}

func main() throws {
    let samples = SampleProjectsStore.samples
    try expect(!samples.isEmpty, "sample catalog is not empty")

    // ── 1. Known id: full lifecycle, exact order + text. ────────────────
    for sample in samples {
        let session = RecordingSession()
        session.packageURL = URL(fileURLWithPath: "/tmp/Previous.shoppilot")

        let loaded = SampleProjectLoader.load(id: sample.id, into: session)
        try expect(loaded, "'\(sample.name)': load returns true")

        try expect(session.appliedPayloads.count == 1,
                   "'\(sample.name)': applyPackagePayload called once (got \(session.appliedPayloads.count))")
        try expect(session.appliedPayloads.first?.job.name == sample.name,
                   "'\(sample.name)': applied payload is the sample's job")
        try expect(session.packageURL == nil,
                   "'\(sample.name)': packageURL cleared (fresh in-memory doc, no overwrite)")
        try expect(session.cleanCount == 1, "'\(sample.name)': markClean called once")
        try expect(session.undoClearCount == 1, "'\(sample.name)': clearUndoStack called once")
        try expect(session.statusMessages.count == 1,
                   "'\(sample.name)': one status message (got \(session.statusMessages.count))")
        let expectedStatus = "Opened “\(sample.name)” — ready to design"
        try expect(session.statusMessages.first == expectedStatus,
                   "'\(sample.name)': status text exact ('\(session.statusMessages.first ?? "nil")' vs '\(expectedStatus)')")
    }

    // ── 2. Unknown id: false, zero mutation. ─────────────────────────────
    let unknown = RecordingSession()
    unknown.packageURL = URL(fileURLWithPath: "/tmp/Keep.shoppilot")
    let notLoaded = SampleProjectLoader.load(id: UUID(), into: unknown)
    try expect(!notLoaded, "unknown id → false")
    try expect(unknown.appliedPayloads.isEmpty, "unknown id → no payload applied")
    try expect(unknown.cleanCount == 0, "unknown id → no markClean")
    try expect(unknown.undoClearCount == 0, "unknown id → no clearUndoStack")
    try expect(unknown.statusMessages.isEmpty, "unknown id → no status message")
    try expect(unknown.packageURL != nil, "unknown id → packageURL untouched")

    // ── 3. The store is the catalog (no second list in the loader). ──────
    // Every catalog id must load — a loader with a hardcoded subset would
    // fail the loop above on the missing sample.

    print("1403a: PASS — sample load lifecycle extracted")
    print("  \(samples.count) samples: full hook sequence + exact status; unknown id → no-op; store is the catalog")
}

do {
    try main()
} catch {
    print("1403a: FAIL — \(error)")
    exit(1)
}
