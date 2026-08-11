import Foundation
import ShopPilotCore

/// SPK-1312 verify (CLT machine, no XCTest).
/// Proves the AUTOSAVE RECOVERY contract — the surface the app uses to offer
/// "Recover unsaved work?" on launch:
///   1. EMPTY: scan on an empty temp dir → [].
///   2. SORT: two real .shoppilot files (a older, b newer) → scan returns 2,
///      newest first (b before a).
///   3. FILTER: a non-.shoppilot file (notes.txt) is ignored — scan still 2.
///   4. LATEST: latest() returns the newest snapshot.
///   5. CLEAR: clear() deletes both .shoppilot files (returns 2), scan() → []
///      afterwards, and the .txt file survives.
///   6. DEFAULT DIR: defaultDirectory() ends with 'ShopPilot/Autosave'.
/// All file work happens in a UUID temp dir — never the real Application Support.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory
        .appendingPathComponent("ShopPilotVerify1312-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    // ── 0. Missing directory → []. ────────────────────────────────────────
    let missing = dir.appendingPathComponent("nope", isDirectory: true)
    try expect(AutosaveRecovery.scan(directory: missing).isEmpty,
               "scan on non-existent directory = []")

    // ── 1. Empty dir → []. ────────────────────────────────────────────────
    try expect(AutosaveRecovery.scan(directory: dir).isEmpty,
               "scan on empty temp dir = [] (got \(AutosaveRecovery.scan(directory: dir).count))")

    // ── 2. Two real files, a older, b newer → newest first. ───────────────
    let a = dir.appendingPathComponent("a.shoppilot")
    let b = dir.appendingPathComponent("b.shoppilot")
    try Data("a".utf8).write(to: a)
    try Data("b".utf8).write(to: b)

    let past = Date(timeIntervalSinceNow: -3600)
    try expect(AutosaveRecovery.markTouched(a, at: past),
               "markTouched(a) with a past date succeeds")
    try expect(AutosaveRecovery.markTouched(b),
               "markTouched(b) with default (now) succeeds")
    try expect(!AutosaveRecovery.markTouched(dir.appendingPathComponent("missing.shoppilot")),
               "markTouched on a non-existent file = false")

    let snaps = AutosaveRecovery.scan(directory: dir)
    try expect(snaps.count == 2, "scan finds 2 .shoppilot files (got \(snaps.count))")
    try expect(snaps.first?.url.lastPathComponent == "b.shoppilot",
               "newest first: b before a (got \(snaps.first?.url.lastPathComponent ?? "nil"))")
    try expect(snaps.last?.url.lastPathComponent == "a.shoppilot",
               "oldest last: a after b")

    // ── 3. Non-.shoppilot files ignored. ──────────────────────────────────
    let notes = dir.appendingPathComponent("notes.txt")
    try Data("notes".utf8).write(to: notes)
    try expect(AutosaveRecovery.scan(directory: dir).count == 2,
               "notes.txt is ignored — scan still 2")

    // ── 4. latest() → newest snapshot. ────────────────────────────────────
    // NOTE: contentsOfDirectory returns symlink-resolved URLs (/private/var…)
    // while appendingPathComponent keeps the literal path (/var…); canonicalize
    // both sides so we compare the same file, not string spellings.
    let latestSnap = AutosaveRecovery.latest(in: snaps)
    try expect(latestSnap?.url.resolvingSymlinksInPath() == b.resolvingSymlinksInPath(),
               "latest() == b URL (got \(latestSnap?.url.absoluteString ?? "nil"), expected \(b.absoluteString))")
    try expect(AutosaveRecovery.latest(in: []) == nil,
               "latest() on empty array = nil")

    // ── 5. clear() deletes only .shoppilot files. ─────────────────────────
    let cleared = AutosaveRecovery.clear(directory: dir)
    try expect(cleared == 2, "clear() deletes both .shoppilot files (got \(cleared))")
    try expect(AutosaveRecovery.scan(directory: dir).isEmpty,
               "scan after clear = []")
    try expect(fm.fileExists(atPath: notes.path),
               "notes.txt survives clear()")
    try expect(AutosaveRecovery.clear(directory: missing) == 0,
               "clear() on missing directory = 0")

    // ── 6. Default directory. ─────────────────────────────────────────────
    try expect(AutosaveRecovery.defaultDirectory().path.hasSuffix("ShopPilot/Autosave"),
               "defaultDirectory() ends with ShopPilot/Autosave (got \(AutosaveRecovery.defaultDirectory().path))")

    print("ShopPilotVerify1312: PASS — scan (empty/missing → [], extension filter, newest-first), latest(), clear (count + .txt survives), markTouched (past/now/missing), defaultDirectory")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1312: FAIL — \(error)")
    exit(1)
}
