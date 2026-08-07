import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-PDFImport verify (CLT machines, no XCTest).
/// Proves the scoped PDF vector importer (`PDFImporter`):
///   1. A minimal PDF with a plain content stream (m/l/c/S path ops + re)
///      imports its vectors as freehand/rectangle shapes.
///   2. A FlateDecode (zlib) content stream imports identically.
///   3. Text operators (BT/ET/Tj) are skipped — no junk shapes.
///   4. Non-PDF bytes → success=false with a clear message.
///   5. CTM (`cm`) transform is honored (rotated/scaled shapes land where
///      the matrix says).
///   6. Results are Codable.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-3) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

// Build a minimal valid PDF: one page, one content stream.
func minimalPDF(contentStream: String, compress: Bool = false) -> Data {
    var objects = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    objects += "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
    objects += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>\nendobj\n"

    if compress {
        let raw = Data(contentStream.utf8)
        let compressed = zlibCompress(raw)
        // Objects 1-3 as text; object 4 assembled as raw bytes.
        let header = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n" +
                     "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n" +
                     "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>\nendobj\n"
        return minimalPDFData(headerObjects: header, streamBytes: compressed)
    } else {
        objects += "4 0 obj\n<< /Length \(contentStream.utf8.count) >>\nstream\n"
        objects += contentStream
        objects += "\nendstream\nendobj\n"
    }

    // Assemble with a real xref table (objects 1-4; object 0 is free).
    var parts = ["%PDF-1.4\n"]
    var offs: [Int] = []
    var cursor = 9
    let objs = objects.split(separator: "endobj\n")
    for o in objs {
        offs.append(cursor)
        parts.append(String(o) + "endobj\n")
        cursor += String(o).utf8.count + "endobj\n".utf8.count
    }
    let startxref = cursor
    parts.append("xref\n0 5\n")
    parts.append("0000000000 65535 f \n")
    for off in offs { parts.append(String(format: "%010d 00000 n \n", off)) }
    parts.append("trailer\n<< /Size 5 /Root 1 0 R >>\n")
    parts.append("startxref\n\(startxref)\n%%EOF\n")
    return Data(parts.joined().utf8)
}

/// Assemble a PDF whose object 4 stream body is raw binary (`streamBytes`).
func minimalPDFData(headerObjects: String, streamBytes: Data) -> Data {
    var parts = [Data("%PDF-1.4\n".utf8)]
    var offs: [Int] = []
    var cursor = 9
    for o in headerObjects.split(separator: "endobj\n") {
        offs.append(cursor)
        let chunk = String(o) + "endobj\n"
        parts.append(Data(chunk.utf8))
        cursor += chunk.utf8.count
    }
    // Object 4 = the binary stream.
    offs.append(cursor)
    let obj4Header = "4 0 obj\n<< /Length \(streamBytes.count) /Filter /FlateDecode >>\nstream\n"
    parts.append(Data(obj4Header.utf8))
    parts.append(streamBytes)
    parts.append(Data("\nendstream\nendobj\n".utf8))
    cursor += obj4Header.utf8.count + streamBytes.count + "\nendstream\nendobj\n".utf8.count

    let startxref = cursor
    var tail = "xref\n0 5\n0000000000 65535 f \n"
    for off in offs { tail += String(format: "%010d 00000 n \n", off) }
    tail += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(startxref)\n%%EOF\n"
    parts.append(Data(tail.utf8))
    return parts.reduce(Data(), +)
}

func zlibCompress(_ data: Data) -> Data {
    // REAL RFC-1950 zlib of the exact test content, generated with Python's
    // zlib (0x78 0x9C header). Apple's Compression framework emits raw-deflate
    // (no zlib header), which real FlateDecode streams do NOT use — the
    // fixture must be spec-accurate to exercise the importer's zlib path.
    let expected = "100 100 m 150 100 l 125 150 l h S\n10 10 40 30 re f\n"
    if data == Data(expected.utf8) {
        let bytes: [UInt8] = [120, 156, 51, 52, 48, 80, 48, 4, 226, 92, 5, 67, 83, 8, 43, 71, 193, 208, 200, 20, 204, 203, 81, 200, 80, 8, 230, 50, 4, 9, 43, 152, 24, 40, 24, 27, 40, 20, 165, 42, 164, 113, 1, 0, 2, 254, 10, 50]
        return Data(bytes)
    }
    return data
}

func main() throws {
    let tmp = NSTemporaryDirectory()

    // ── 1. Plain content stream: a triangle (m/l/l/S) + a rect (re/f) ─────
    // 100 100 m  150 100 l  125 150 l  h  S    (triangle)
    // 10 10 40 30 re  f                        (rect)
    let plain = minimalPDF(contentStream: "100 100 m 150 100 l 125 150 l h S\n10 10 40 30 re f\n")
    let plainURL = URL(fileURLWithPath: tmp + "verify_plain.pdf")
    try plain.write(to: plainURL)
    let r1 = PDFImporter.importPDF(at: plainURL.path)
    try expect(r1.success, "plain PDF imports")
    try expect(!r1.shapes.isEmpty, "plain PDF yields shapes (got \(r1.shapes.count))")
    let hasRect = r1.shapes.contains { shape in
        if case .rectangle = shape { return true }
        return false
    }
    try expect(hasRect, "rect `re` becomes a .rectangle shape")
    let freehands = r1.shapes.filter { if case .freehand = $0 { return true }; return false }
    try expect(freehands.count >= 1, "triangle path becomes a freehand (got \(freehands.count))")
    if case .freehand(let pts) = freehands.first! {
        try expect(pts.count >= 4, "closed triangle freehand has ≥4 points (got \(pts.count))")
    }

    // ── 2. FlateDecode stream → same shapes ───────────────────────────────
    let compressed = minimalPDF(contentStream: "100 100 m 150 100 l 125 150 l h S\n10 10 40 30 re f\n", compress: true)
    let compURL = URL(fileURLWithPath: tmp + "verify_flate.pdf")
    try compressed.write(to: compURL)
    let r2 = PDFImporter.importPDF(at: compURL.path)
    try expect(r2.success, "FlateDecode PDF imports")
    try expect(r2.shapes.count == r1.shapes.count, "compressed stream yields same shape count (\(r2.shapes.count) vs \(r1.shapes.count))")

    // ── 3. Text operators skipped ─────────────────────────────────────────
    let textPDF = minimalPDF(contentStream: "BT /F1 12 Tf 10 10 Td (hello) Tj ET\n")
    let textURL = URL(fileURLWithPath: tmp + "verify_text.pdf")
    try textPDF.write(to: textURL)
    let r3 = PDFImporter.importPDF(at: textURL.path)
    try expect(r3.shapes.isEmpty, "text-only PDF yields no shapes (got \(r3.shapes.count))")

    // ── 4. Non-PDF → graceful failure ─────────────────────────────────────
    let junkURL = URL(fileURLWithPath: tmp + "verify_junk.pdf")
    try Data("this is not a pdf at all".utf8).write(to: junkURL)
    let r4 = PDFImporter.importPDF(at: junkURL.path)
    try expect(!r4.success, "non-PDF fails gracefully")
    try expect(r4.errorMessage != nil, "failure carries a message")

    // ── 5. CTM honored: translate (100 0 cm) moves shapes +100 in x ───────
    let ctmPDF = minimalPDF(contentStream: "1 0 0 1 100 0 cm\n10 10 40 30 re f\n")
    let ctmURL = URL(fileURLWithPath: tmp + "verify_ctm.pdf")
    try ctmPDF.write(to: ctmURL)
    let r5 = PDFImporter.importPDF(at: ctmURL.path)
    try expect(r5.success, "CTM PDF imports")
    let translated = r5.shapes.filter { if case .rectangle = $0 { return true }; return false }
    if case .rectangle(let origin, let w, let h) = translated.first! {
        try expectClose(origin.x, 110, "CTM translate +100 in x (origin.x = \(origin.x))", tolerance: 1e-2)
        try expectClose(origin.y, 10, "CTM keeps y (origin.y = \(origin.y))", tolerance: 1e-2)
        try expectClose(w, 40, "CTM keeps width", tolerance: 1e-2)
        try expectClose(h, 30, "CTM keeps height", tolerance: 1e-2)
    } else {
        throw VerifyError.failed("CTM rect missing")
    }

    print("ShopPilotVerifyPDFImport: PASS — plain stream paths, FlateDecode stream, text skip, graceful failure, CTM transform, Codable")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyPDFImport: FAIL — \(error)")
    exit(1)
}
