import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-AIImport verify (CLT machines, no XCTest).
/// Proves the AI flavor dispatcher (`AIImporter`):
///   1. EPS-flavored AI (`%!PS-Adobe-3.0 EPSF-3.0` + paths) → shapes via EPS.
///   2. PDF-flavored AI (`%PDF` + content stream) → shapes via PDF.
///   3. Non-AI bytes → success=false with a clear message.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let tmp = NSTemporaryDirectory()

    // ── 1. EPS-flavored AI ────────────────────────────────────────────────
    let epsAI = """
    %!PS-Adobe-3.0 EPSF-3.0
    %%BoundingBox: 0 0 100 100
    %%Creator: Adobe Illustrator(TM) 28.0
    %%EndComments
    newpath
    10 10 moveto
    90 10 lineto
    90 90 lineto
    10 90 lineto
    closepath
    stroke
    %%EOF
    """
    let epsURL = URL(fileURLWithPath: tmp + "verify_ai_eps.ai")
    try epsAI.write(to: epsURL, atomically: true, encoding: .utf8)
    let r1 = AIImporter.importAI(at: epsURL.path)
    try expect(r1.success, "EPS-flavored AI imports")
    try expect(r1.flavor == "EPS", "flavor tagged EPS (got \(r1.flavor))")
    try expect(!r1.shapes.isEmpty, "EPS-flavored AI yields shapes (got \(r1.shapes.count))")

    // ── 2. PDF-flavored AI ────────────────────────────────────────────────
    // Reuse the minimal PDF builder (same shape as the PDF verify CLT).
    var objects = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    objects += "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
    objects += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>\nendobj\n"
    let content = "100 100 m 150 100 l 125 150 l h S\n10 10 40 30 re f\n"
    objects += "4 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream\nendobj\n"

    var parts = ["%PDF-1.4\n"]
    var offs: [Int] = []
    var cursor = 9
    for o in objects.split(separator: "endobj\n") {
        offs.append(cursor)
        parts.append(String(o) + "endobj\n")
        cursor += String(o).utf8.count + "endobj\n".utf8.count
    }
    let startxref = cursor
    parts.append("xref\n0 5\n0000000000 65535 f \n")
    for off in offs { parts.append(String(format: "%010d 00000 n \n", off)) }
    parts.append("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(startxref)\n%%EOF\n")
    let pdfURL = URL(fileURLWithPath: tmp + "verify_ai_pdf.ai")
    try Data(parts.joined().utf8).write(to: pdfURL)

    let r2 = AIImporter.importAI(at: pdfURL.path)
    try expect(r2.success, "PDF-flavored AI imports")
    try expect(r2.flavor == "PDF", "flavor tagged PDF (got \(r2.flavor))")
    try expect(!r2.shapes.isEmpty, "PDF-flavored AI yields shapes (got \(r2.shapes.count))")

    // ── 3. Non-AI → graceful failure ──────────────────────────────────────
    let junkURL = URL(fileURLWithPath: tmp + "verify_ai_junk.ai")
    try Data("definitely not illustrator data".utf8).write(to: junkURL)
    let r3 = AIImporter.importAI(at: junkURL.path)
    try expect(!r3.success, "non-AI fails gracefully")
    try expect(r3.errorMessage != nil, "failure carries a message")

    print("ShopPilotVerifyAIImport: PASS — EPS-flavor dispatch, PDF-flavor dispatch, graceful failure")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyAIImport: FAIL — \(error)")
    exit(1)
}
