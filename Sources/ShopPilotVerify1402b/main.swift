import Foundation
import ShopPilotCore

/// SPK-1402b verify (CLT machine, no XCTest).
/// Proves DocumentLoader never silently skips corrupt sheet JSON:
///   1. STRICT OPEN FAILS: a package with one good sheet + one corrupt sheet
///      file throws `DocumentError.corruptSheets` naming the corrupt file
///      (both `loadPayload` and the `load` convenience).
///   2. TOLERANT OPEN WARNS: `loadPayloadCollectingWarnings` loads the good
///      sheet and returns a warning naming the corrupt file — the document
///      opens while the corruption stays user-visible.
///   3. NO FALSE POSITIVES: a fully-good package opens cleanly through both
///      paths with zero warnings.
/// All file work happens in a UUID temp dir — never the real Application
/// Support, never the repo's fixtures.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Write a minimal valid manifest.json for a hand-rolled package.
func writeManifest(to packageURL: URL, jobID: UUID, name: String) throws {
    let manifest: [String: Any] = [
        "id": jobID.uuidString,
        "name": name,
        "createdAt": "2026-08-12T00:00:00Z",
        "updatedAt": "2026-08-12T00:00:00Z",
        "version": "0.2",
        "sheetCount": 2,
        "documentVariables": [],
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    try data.write(to: packageURL.appendingPathComponent("manifest.json"), options: .atomic)
}

func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("ShopPilotVerify1402b-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // ── Fixture: one good sheet + one corrupt sheet file. ────────────────
    let packageURL = root.appendingPathComponent("Mixed.shoppilot", isDirectory: true)
    try fm.createDirectory(at: packageURL.appendingPathComponent("sheets", isDirectory: true),
                           withIntermediateDirectories: true)
    try writeManifest(to: packageURL, jobID: UUID(), name: "Mixed Fixture")

    let goodSheet = Sheet(id: UUID(), name: "Good Sheet", width: 600, depth: 400, height: 25)
    let goodData = try JSONEncoder().encode(goodSheet)
    try goodData.write(
        to: packageURL.appendingPathComponent("sheets/\(goodSheet.id.uuidString).json"),
        options: .atomic
    )

    let corruptSheetFile = "broken-sheet.json"
    try Data("this is not valid JSON ~~".utf8).write(
        to: packageURL.appendingPathComponent("sheets/\(corruptSheetFile)"),
        options: .atomic
    )

    let loader = DocumentLoader()

    // ── 1. Strict open fails with the corrupt sheet NAMED. ───────────────
    do {
        _ = try loader.loadPayload(from: packageURL)
        throw VerifyError.failed("loadPayload did NOT fail on corrupt sheet — silent skip!")
    } catch DocumentError.corruptSheets(let names) {
        try expect(names.contains(corruptSheetFile),
                   "corruptSheets error names the corrupt file — got \(names)")
    } catch {
        throw VerifyError.failed("wrong error type on corrupt sheet: \(error)")
    }

    do {
        _ = try loader.load(from: packageURL)
        throw VerifyError.failed("load(_:) did NOT fail on corrupt sheet — silent skip!")
    } catch DocumentError.corruptSheets(let names) {
        try expect(names.contains(corruptSheetFile),
                   "load(_:) corruptSheets error names the corrupt file — got \(names)")
    } catch {
        throw VerifyError.failed("wrong error type from load(_:): \(error)")
    }

    // ── 2. Tolerant open: good sheet loads, warning names the corrupt one. ─
    let tolerant = try loader.loadPayloadCollectingWarnings(from: packageURL)
    try expect(tolerant.payload.job.sheets.count == 1,
               "tolerant open loads the good sheet (got \(tolerant.payload.job.sheets.count))")
    try expect(tolerant.payload.job.sheets.first?.name == "Good Sheet",
               "good sheet identity preserved (got \(String(describing: tolerant.payload.job.sheets.first?.name)))")
    try expect(tolerant.warnings.count == 1,
               "exactly one warning for the corrupt sheet (got \(tolerant.warnings.count))")
    try expect(tolerant.warnings.first?.fileName == corruptSheetFile,
               "warning names the corrupt file — got \(String(describing: tolerant.warnings.first?.fileName))")
    try expect(!(tolerant.warnings.first?.message.isEmpty ?? true),
               "warning carries a human-readable message")

    // ── 3. Fully-good package opens cleanly — no false positives. ────────
    var job = Job(id: UUID(), name: "Good Fixture")
    job.sheets = [
        goodSheet,
        Sheet(id: UUID(), name: "Second Sheet", width: 300, depth: 200, height: 12),
    ]
    let goodURL = root.appendingPathComponent("Good.shoppilot", isDirectory: true)
    try DocumentSaver().save(job, to: goodURL)

    let strict = try loader.loadPayload(from: goodURL)
    try expect(strict.job.sheets.count == 2,
               "strict open loads all 2 good sheets (got \(strict.job.sheets.count))")

    let clean = try loader.loadPayloadCollectingWarnings(from: goodURL)
    try expect(clean.payload.job.sheets.count == 2,
               "tolerant open loads all 2 good sheets (got \(clean.payload.job.sheets.count))")
    try expect(clean.warnings.isEmpty,
               "fully-good package → zero warnings (got \(clean.warnings.count))")

    print("1402b: PASS — corrupt sheets surface")
}

do {
    try main()
} catch {
    print("1402b: FAIL — \(error)")
    exit(1)
}
