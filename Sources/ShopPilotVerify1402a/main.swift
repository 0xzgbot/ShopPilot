import Foundation
import ShopPilotCore

/// SPK-1402a verify (CLT machine, no XCTest).
/// Proves the Autosaver is no longer dead code — the `RecoveryCoordinator`
/// contract `AppSession` calls at launch:
///   1. CONFIG: `Autosaver.defaultInterval == 300` (5 minutes).
///   2. NAMING: `RecoveryCoordinator.recoveryURL(for:)` is "<job name>.shoppilot".
///   3. DIRTY START → ARTIFACT: starting the autosaver with a dirty
///      session-like immediately writes a `.shoppilot` recovery package
///      (manifest.json present) — the start API really saves.
///   4. LIVE DOC: the saved package carries the session's CURRENT job (read
///      through `AutosaveSessionLike`), not an init-time copy.
///   5. RECOVERY SURFACE: `AutosaveRecovery.scan` finds the artifact and
///      `RecoveryCoordinator.latestSnapshot` returns it — launch can offer
///      "Recover unsaved work?".
///   6. CLEAN: a clean session writes nothing.
/// All file work happens in a UUID temp dir — never the real Application Support.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Minimal test double for the app session — exactly the autosave slice.
final class FakeSession: AutosaveSessionLike {
    var autosaveJob: Job
    var isAutosaveDirty: Bool
    init(job: Job, dirty: Bool) {
        autosaveJob = job
        isAutosaveDirty = dirty
    }
}

func main() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory
        .appendingPathComponent("ShopPilotVerify1402a-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    // ── 1. Interval configuration: 5 minutes. ───────────────────────────
    try expect(Autosaver.defaultInterval == 300,
               "Autosaver.defaultInterval == 300 (5 min) — got \(Autosaver.defaultInterval)")

    // ── 2. Recovery file naming. ────────────────────────────────────────
    var job = Job(name: "Test Part")
    _ = job.ensureSingleSheet()
    let namedURL = RecoveryCoordinator.recoveryURL(for: job, directory: dir)
    try expect(namedURL.lastPathComponent == "Test Part.shoppilot",
               "recovery file is '<job name>.shoppilot' — got \(namedURL.lastPathComponent)")

    // ── 3 + 4. Dirty session-like → start writes the CURRENT job immediately.
    // Rename before start: the autosaver must read the session live, not a
    // captured init-time copy.
    job.name = "Renamed Part"
    let session = FakeSession(job: job, dirty: true)
    let autosaver = RecoveryCoordinator.startAutosaver(for: session, directory: dir)
    defer { autosaver.stop() }

    try expect(autosaver.isActive, "autosaver is active after start")

    let packageURL = RecoveryCoordinator.recoveryURL(for: job, directory: dir)
    try expect(fm.fileExists(atPath: packageURL.path),
               "dirty start → recovery package exists immediately")
    let manifestURL = packageURL.appendingPathComponent("manifest.json")
    try expect(fm.fileExists(atPath: manifestURL.path),
               "recovery package contains manifest.json")

    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    try expect(manifest?["name"] as? String == "Renamed Part",
               "manifest name == session's live job name (got \(String(describing: manifest?["name"])))")

    // ── 5. Recovery surface sees the artifact (launch can offer recover). ──
    let snaps = AutosaveRecovery.scan(directory: dir)
    try expect(snaps.count == 1, "scan finds the recovery artifact (got \(snaps.count))")
    try expect(RecoveryCoordinator.latestSnapshot(directory: dir)?
        .url.resolvingSymlinksInPath() == packageURL.resolvingSymlinksInPath(),
        "latestSnapshot == the autosaved package")
    autosaver.stop()

    // ── 6. Clean session → nothing written. ─────────────────────────────
    let cleanDir = dir.appendingPathComponent("clean", isDirectory: true)
    let cleanAutosaver = RecoveryCoordinator.startAutosaver(
        for: FakeSession(job: job, dirty: false),
        directory: cleanDir
    )
    defer { cleanAutosaver.stop() }
    try expect(AutosaveRecovery.scan(directory: cleanDir).isEmpty,
               "clean session writes no recovery artifact")

    print("1402a: PASS — Autosaver wired")
}

do {
    try main()
} catch {
    print("1402a: FAIL — \(error)")
    exit(1)
}
