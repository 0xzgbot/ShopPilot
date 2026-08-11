import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1322 verify (CLT machine, no XCTest).
/// Proves the DESIGN PDF EXPORT contract:
///   1. export(...) writes a real PDF to a temp file: returns true, file
///      exists, > 100 bytes, first 4 bytes are "%PDF".
///   2. renderShapes returns non-nil Data for a mixed shape list (every
///      VectorShape case), starting with "%PDF".
///   3. Empty shape list still exports a valid PDF ("%PDF" header) — an
///      empty design exports.
///   4. export to an invalid path (missing directory) → false, no crash.
///   5. A 400×300 mm design on the default A4 page still exports (clipped,
///      no crash).
/// Uses a UUID-suffixed temp directory, cleaned up at the end.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pdfHeader(_ data: Data) -> String {
    String(data: data.prefix(4), encoding: .utf8) ?? ""
}

func main() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("spk1322-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // ── 1. export 3 shapes (rectangle 100×50, circle r=20, line) to a real file.
    let shapes: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 10, y: 10), width: 100, height: 50),
        .circle(center: VectorPoint(x: 80, y: 60), radius: 20),
        .line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 50, y: 50)),
    ]
    let pdfURL = tempDir.appendingPathComponent("design.pdf")
    let exported = DesignPDFExporter.export(shapes, to: pdfURL)
    try expect(exported, "export(to:) returned true")
    try expect(FileManager.default.fileExists(atPath: pdfURL.path), "PDF file exists on disk")
    let fileData = try Data(contentsOf: pdfURL)
    try expect(fileData.count > 100, "PDF size > 100 bytes (got \(fileData.count))")
    try expect(pdfHeader(fileData) == "%PDF", "file starts with %PDF (got '\(pdfHeader(fileData))')")

    // ── 2. renderShapes: mixed list with every shape case → non-nil %PDF Data.
    let mixed: [VectorShape] = [
        .line(start: VectorPoint(x: 0, y: 0), end: VectorPoint(x: 40, y: 40)),
        .circle(center: VectorPoint(x: 30, y: 30), radius: 15),
        .rectangle(origin: VectorPoint(x: 5, y: 5), width: 60, height: 30),
        .arc(center: VectorPoint(x: 50, y: 50), radius: 25, startAngle: 0, endAngle: .pi),
        .ellipse(center: VectorPoint(x: 70, y: 20), radiusX: 12, radiusY: 6, rotation: 0.3),
        .polygon(center: VectorPoint(x: 90, y: 50), radius: 18, sides: 6, rotation: 0.1),
        .star(center: VectorPoint(x: 20, y: 70), outerRadius: 16, innerRadius: 7, points: 5, rotation: 0),
        .freehand(points: [
            VectorPoint(x: 60, y: 70), VectorPoint(x: 75, y: 60),
            VectorPoint(x: 90, y: 70), VectorPoint(x: 75, y: 85),
            VectorPoint(x: 60, y: 70),
        ]),
    ]
    guard let mixedData = DesignPDFExporter.renderShapes(mixed) else {
        throw VerifyError.failed("renderShapes returned nil for a mixed shape list")
    }
    try expect(pdfHeader(mixedData) == "%PDF", "renderShapes Data starts with %PDF")

    // ── 3. Empty shape list → still a valid PDF.
    guard let emptyData = DesignPDFExporter.renderShapes([]) else {
        throw VerifyError.failed("renderShapes returned nil for an empty design")
    }
    try expect(pdfHeader(emptyData) == "%PDF", "empty design exports a valid PDF")
    try expect(emptyData.count > 100, "empty design PDF is a real document (got \(emptyData.count) bytes)")

    // ── 4. Invalid path (nonexistent directory) → false, no crash.
    let missingDirURL = tempDir.appendingPathComponent("nope/subdir/design.pdf")
    let invalid = DesignPDFExporter.export(shapes, to: missingDirURL)
    try expect(!invalid, "export to a missing directory returns false")

    // ── 5. 400×300 mm design on the default A4 page → still exports (clipped).
    let big: [VectorShape] = [
        .rectangle(origin: VectorPoint(x: 0, y: 0), width: 400, height: 300),
    ]
    guard let clippedData = DesignPDFExporter.renderShapes(big) else {
        throw VerifyError.failed("renderShapes returned nil for a 400×300 mm design on A4")
    }
    try expect(pdfHeader(clippedData) == "%PDF", "clipped design still exports a valid PDF")

    print("ShopPilotVerify1322: PASS — design PDF export: real %PDF file (>100 bytes), mixed/empty/oversized designs, invalid-path safety")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1322: FAIL — \(error)")
    exit(1)
}
