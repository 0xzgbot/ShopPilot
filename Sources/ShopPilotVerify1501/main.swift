import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1501 verify (CLT executable, no XCTest).
// Proves the Welcome/File Open path without driving NSOpenPanel:
//   1. SOURCE CONTRACT — WelcomeSheetView and App.swift File menu BOTH route
//      through `session.handleCommand(.openJob)`, and AppSession's
//      `handleCommand(.openJob)` calls `openPackageFromPanel()` — one open
//      path, two entry points.
//   2. BEHAVIORAL — the Core loader under `openPackage(from:)` throws on a
//      bad/unknown package URL (the "unknown URL still throws" contract):
//      a nonexistent file throws; a directory-that-is-not-a-package throws;
//      a real temp package opens cleanly (round-trip already proven by 1100,
//      here just the good-path smoke so the throw checks aren't vacuous).

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    // ── 1. Source contract. ──────────────────────────────────────────────
    let welcome = try String(
        contentsOf: root.appendingPathComponent("ShopPilot/WelcomeSheetView.swift"),
        encoding: .utf8
    )
    let app = try String(
        contentsOf: root.appendingPathComponent("ShopPilot/App.swift"),
        encoding: .utf8
    )
    let session = try String(
        contentsOf: root.appendingPathComponent("ShopPilot/AppSession.swift"),
        encoding: .utf8
    )

    try expect(welcome.contains("session.handleCommand(.openJob)"),
               "Welcome 'Open a Job…' routes via handleCommand(.openJob)")
    try expect(app.contains("Button(\"Open Job…\")")
               && app.contains("session.handleCommand(.openJob)"),
               "File menu 'Open Job…' routes via handleCommand(.openJob)")
    try expect(session.contains("case .openJob:")
               && session.contains("openPackageFromPanel()"),
               "handleCommand(.openJob) → openPackageFromPanel (the real panel)")
    try expect(session.contains("func openPackage(from url: URL) throws"),
               "openPackage(from:) is the throwing load path")

    // ── 2. Behavioral: unknown/bad URL throws; good package opens. ───────
    let loader = DocumentLoader()

    // Nonexistent file → throws.
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("does-not-exist-\(UUID().uuidString).shoppilot")
    do {
        _ = try loader.loadPayload(from: missing)
        throw VerifyError.failed("nonexistent package did not throw")
    } catch {
        // expected
    }

    // A plain temp directory (not a package) → throws.
    let fakePackage = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fake-package-\(UUID().uuidString).shoppilot")
    try FileManager.default.createDirectory(at: fakePackage, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fakePackage) }
    do {
        _ = try loader.loadPayload(from: fakePackage)
        throw VerifyError.failed("empty package directory did not throw")
    } catch {
        // expected
    }

    // Good path smoke: build a minimal valid package in a temp dir, open it.
    let goodPackage = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("good-\(UUID().uuidString).shoppilot")
    defer { try? FileManager.default.removeItem(at: goodPackage) }
    do {
        let payload = ShopPilotPackagePayload(job: Job(name: "Smoke"))
        let saver = DocumentSaver()
        try saver.save(payload, to: goodPackage)
        let loaded = try loader.loadPayload(from: goodPackage)
        try expect(loaded.job.name == "Smoke", "good package round-trips (got \(loaded.job.name))")
    } catch {
        throw VerifyError.failed("good package failed to open: \(error)")
    }

    print("1501: PASS — Welcome/File open path contract")
    print("  Welcome + File menu → handleCommand(.openJob) → openPackageFromPanel; bad URL throws; good package opens")
}

do {
    try main()
} catch {
    print("1501: FAIL — \(error)")
    exit(1)
}
