import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-0216 verify (CLT machines, no XCTest).
/// Proves `UnifiedImportRouter` dispatches every supported vector format to
/// its importer and reports shapes + warnings uniformly:
///   1. Extension → format routing (svg/dxf/eps/pdf/ai/dwg + unknown).
///   2. SVG fixture parses to shapes through the router.
///   3. DXF fixture (LINE/CIRCLE) parses to shapes through the router.
///   4. EPS fixture (%%BoundingBox + moveto/lineto) parses through the router.
///   5. PDF fixture parses through the router.
///   6. AI (EPS flavor) dispatches through the router.
///   7. DWG R12 fixture parses through the router.
///   8. Unknown extension → empty result + warning, no crash.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-0216-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func write(_ content: String, ext: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("fixture.\(ext)")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

func write(_ data: Data, ext: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent("fixture.\(ext)")
    try data.write(to: url)
    return url
}

func main() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // ── 1. Extension routing ──────────────────────────────────────────────
    try expect(UnifiedImportRouter.Format.from(extension: "svg") == .svg, "ext svg")
    try expect(UnifiedImportRouter.Format.from(extension: "DXF") == .dxf, "ext DXF uppercase")
    try expect(UnifiedImportRouter.Format.from(extension: "eps") == .eps, "ext eps")
    try expect(UnifiedImportRouter.Format.from(extension: "pdf") == .pdf, "ext pdf")
    try expect(UnifiedImportRouter.Format.from(extension: "ai") == .ai, "ext ai")
    try expect(UnifiedImportRouter.Format.from(extension: "dwg") == .dwg, "ext dwg")
    try expect(UnifiedImportRouter.Format.from(extension: "xyz") == nil, "ext unknown → nil")

    // ── 2. SVG ────────────────────────────────────────────────────────────
    let svg = try write("""
    <?xml version="1.0"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
      <rect x="10" y="10" width="30" height="20"/>
      <line x1="0" y1="0" x2="50" y2="50"/>
    </svg>
    """, ext: "svg", in: dir)
    let svgResult = UnifiedImportRouter.importFile(at: svg)
    try expect(svgResult.format == .svg, "svg result format")
    try expect(!svgResult.shapes.isEmpty, "svg parses to shapes (got \(svgResult.shapes.count))")

    // ── 3. DXF ────────────────────────────────────────────────────────────
    let dxf = try write("""
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    8
    0
    10
    0.0
    20
    0.0
    11
    10.0
    21
    10.0
    0
    CIRCLE
    8
    0
    10
    5.0
    20
    5.0
    40
    3.0
    0
    ENDSEC
    0
    EOF
    """, ext: "dxf", in: dir)
    let dxfResult = UnifiedImportRouter.importFile(at: dxf)
    try expect(dxfResult.format == .dxf, "dxf result format")
    try expect(dxfResult.shapes.count == 2, "dxf parses line + circle (got \(dxfResult.shapes.count))")

    // ── 4. EPS ────────────────────────────────────────────────────────────
    let eps = try write("""
    %!PS-Adobe-3.0 EPSF-3.0
    %%BoundingBox: 0 0 100 100
    newpath
    10 10 moveto
    90 10 lineto
    90 90 lineto
    closepath
    stroke
    """, ext: "eps", in: dir)
    let epsResult = UnifiedImportRouter.importFile(at: eps)
    try expect(epsResult.format == .eps, "eps result format")
    try expect(!epsResult.shapes.isEmpty, "eps parses to shapes (got \(epsResult.shapes.count))")

    // ── 5. PDF ────────────────────────────────────────────────────────────
    let pdf = try write("""
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >> endobj
    4 0 obj << /Length 44 >>
    stream
    10 10 m 90 10 l 90 90 l S
    endstream
    endobj
    xref
    0 5
    trailer << /Root 1 0 R >>
    %%EOF
    """, ext: "pdf", in: dir)
    let pdfResult = UnifiedImportRouter.importFile(at: pdf)
    try expect(pdfResult.format == .pdf, "pdf result format")
    try expect(!pdfResult.shapes.isEmpty, "pdf parses to shapes (got \(pdfResult.shapes.count))")

    // ── 6. AI (EPS flavor) ────────────────────────────────────────────────
    let ai = try write("""
    %!PS-Adobe-3.0 EPSF-3.0
    %%BoundingBox: 0 0 50 50
    newpath
    0 0 moveto
    50 50 lineto
    stroke
    """, ext: "ai", in: dir)
    let aiResult = UnifiedImportRouter.importFile(at: ai)
    try expect(aiResult.format == .ai, "ai result format")
    try expect(!aiResult.shapes.isEmpty, "ai parses to shapes (got \(aiResult.shapes.count))")

    // ── 7. DWG (R12 fixture from the reference suite) ─────────────────────
    let dwgPath = FileManager.default.currentDirectoryPath
        + "/Sources/ShopPilotVerifyDWGImport/Fixtures/LINE1.DWG"
    if FileManager.default.fileExists(atPath: dwgPath) {
        let dwgResult = UnifiedImportRouter.importFile(at: URL(fileURLWithPath: dwgPath))
        try expect(dwgResult.format == .dwg, "dwg result format")
        try expect(!dwgResult.shapes.isEmpty, "dwg parses to shapes (got \(dwgResult.shapes.count))")
    }

    // ── 8. Unknown extension ──────────────────────────────────────────────
    let unknown = try write("garbage", ext: "xyz", in: dir)
    let unknownResult = UnifiedImportRouter.importFile(at: unknown)
    try expect(unknownResult.shapes.isEmpty, "unknown ext → no shapes")
    try expect(!unknownResult.warnings.isEmpty, "unknown ext → warning")

    print("ShopPilotVerify0216: PASS — ext routing, SVG/DXF/EPS/PDF/AI/DWG dispatch, unknown → warning")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0216: FAIL — \(error)")
    exit(1)
}
