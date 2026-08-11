import Foundation
import ShopPilotCore

/// SPK-1209 verify (CLT machine, no XCTest).
/// Proves the WEBP IMPORT + RECENT FILES contract:
///   1. WEBP DECODE: the bitmap importer (CGImageSource-backed) decodes a
///      real .webp fixture into a heightfield — ImageIO supports WebP on
///      macOS 11+, and the importer already routes every raster through it,
///      so the format gate is: fixture decodes, non-zero grid.
///   2. RECENT STORE: record dedupes by path (re-importing the same file
///      bumps it to front, no duplicates), caps at the configured capacity,
///      persists across store instances (UserDefaults), remove + clear work.
/// The Import hub rail (Recent list UI + onRecordRecent wiring) is
/// compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let cwd = FileManager.default.currentDirectoryPath
    let root = cwd.hasSuffix("ShopPilot") ? cwd : cwd + "/../.."

    // ── 1. WebP decodes through the real importer. ────────────────────────
    let webpURL = URL(fileURLWithPath: root).appendingPathComponent("fixtures/import/tiny.webp")
    try expect(FileManager.default.fileExists(atPath: webpURL.path), "webp fixture present")
    let config = BitmapHeightfieldConfig(maxCells: 64)
    let result = BitmapHeightfieldImporter.decodeImage(at: webpURL, config: config)
    try expect(result.success, "webp decode succeeds (got \(result.errorMessage ?? "ok"))")
    try expect(result.heightfield != nil, "webp yields a heightfield")
    if let hf = result.heightfield {
        try expect(hf.width > 0 && hf.height > 0, "webp grid non-zero (\(hf.width)×\(hf.height))")
    }

    // ── 2. Recent store: dedupe, cap, persist, remove, clear. ─────────────
    let defaults = UserDefaults(suiteName: "verify1209-\(UUID().uuidString)")!
    let store = RecentFilesStore(defaults: defaults, capacity: 3)

    let a = URL(fileURLWithPath: "/tmp/art-a.svg")
    let b = URL(fileURLWithPath: "/tmp/art-b.dxf")
    let c = URL(fileURLWithPath: "/tmp/art-c.eps")
    let d = URL(fileURLWithPath: "/tmp/art-d.pdf")

    store.record(a)
    store.record(b)
    store.record(c)
    try expect(store.recent.count == 3, "three files recorded")
    try expect(store.recent.first?.url == c, "most recent first")

    // Dedupe: re-record b → bumps to front, still 3 entries.
    store.record(b)
    try expect(store.recent.count == 3, "re-record dedupes (no duplicate)")
    try expect(store.recent.first?.url == b, "re-recorded file bumps to front")

    // Cap: adding a 4th drops the oldest (a).
    store.record(d)
    try expect(store.recent.count == 3, "cap enforced (got \(store.recent.count))")
    try expect(!store.recent.contains { $0.url == a }, "oldest dropped at cap")

    // Persistence across a fresh instance.
    let store2 = RecentFilesStore(defaults: defaults, capacity: 3)
    try expect(store2.recent.count == 3, "recents persist across instances")
    try expect(store2.recent.first?.url == d, "persisted order kept")

    // Remove + clear.
    store2.remove(url: b)
    try expect(store2.recent.count == 2, "remove drops the entry")
    store2.clear()
    try expect(store2.recent.isEmpty, "clear empties the rail")

    print("ShopPilotVerify1209: PASS — webp decodes to a heightfield via ImageIO, recent store dedupe/cap/persist/remove/clear")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1209: FAIL — \(error)")
    exit(1)
}
