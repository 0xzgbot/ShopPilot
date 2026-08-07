import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-DWGImport verify (CLT machines, no XCTest).
/// Proves the scoped R12 (AC1009) DWG importer (`DWGImporter`) against the
/// REAL fixture files from the public `CAD::Format::DWG::AC1009` reference
/// (BSD-2-Clause), asserting the exact values its test suite asserts:
///   1. LINE1 (2D + handle): x1=1 y1=1 x2=2 y2=2, size 44, layer 0.
///   2. LINE2 (3D + handle): + z1=1 z2=2, size 60.
///   3. CIRCLE1: center (1,1) radius 3.
///   4. ARC1: center (5,5) radius 1, angle 3π/2 → 0.
///   5. POINT1: x=1 y=2.
///   6. Non-DWG bytes → graceful failure. Version detect: post-R12 header
///      ("AC1015" = 2000) → unsupported-version message.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func expectClose(_ a: Double, _ b: Double, _ msg: String, tolerance: Double = 1e-6) throws {
    if abs(a - b) > tolerance { throw VerifyError.failed("\(msg): expected \(b), got \(a)") }
}

/// Fixtures live next to the CLT (committed with it, provenance documented).
func fixturePath(_ name: String) -> String {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/ShopPilotVerifyDWGImport/Fixtures/\(name)").path
}

func main() throws {
    // ── 1. LINE1 (2D, handling id 4c) ─────────────────────────────────────
    let line1 = DWGImporter.importDWG(at: fixturePath("LINE1.DWG"))
    try expect(line1.success, "LINE1 imports")
    try expect(line1.version == "AC1009", "version AC1009")
    try expect(line1.entityCount == 1, "LINE1 → 1 entity (got \(line1.entityCount))")
    if case .line(let start, let end) = line1.shapes.first! {
        try expectClose(start.x, 1, "LINE1 x1")
        try expectClose(start.y, 1, "LINE1 y1")
        try expectClose(end.x, 2, "LINE1 x2")
        try expectClose(end.y, 2, "LINE1 y2")
    } else {
        throw VerifyError.failed("LINE1 first shape is not .line")
    }

    // ── 2. LINE2 (3D — z fields present) ──────────────────────────────────
    let line2 = DWGImporter.importDWG(at: fixturePath("LINE2.DWG"))
    try expect(line2.success, "LINE2 imports")
    try expect(line2.entityCount == 1, "LINE2 → 1 entity")
    if case .line(let start, let end) = line2.shapes.first! {
        try expectClose(start.x, 1, "LINE2 x1")
        try expectClose(start.y, 1, "LINE2 y1")
        try expectClose(end.x, 2, "LINE2 x2")
        try expectClose(end.y, 2, "LINE2 y2")
    } else {
        throw VerifyError.failed("LINE2 first shape is not .line")
    }

    // ── 3. CIRCLE1 ────────────────────────────────────────────────────────
    let circle = DWGImporter.importDWG(at: fixturePath("CIRCLE1.DWG"))
    try expect(circle.success, "CIRCLE1 imports")
    try expect(circle.entityCount == 1, "CIRCLE1 → 1 entity")
    if case .circle(let center, let radius) = circle.shapes.first! {
        try expectClose(center.x, 1, "CIRCLE1 center x")
        try expectClose(center.y, 1, "CIRCLE1 center y")
        try expectClose(radius, 3, "CIRCLE1 radius")
    } else {
        throw VerifyError.failed("CIRCLE1 first shape is not .circle")
    }

    // ── 4. ARC1 (3π/2 → 0 radians) ────────────────────────────────────────
    let arc = DWGImporter.importDWG(at: fixturePath("ARC1.DWG"))
    try expect(arc.success, "ARC1 imports")
    try expect(arc.entityCount == 1, "ARC1 → 1 entity")
    if case .arc(let center, let radius, let startAngle, let endAngle) = arc.shapes.first! {
        try expectClose(center.x, 5, "ARC1 center x")
        try expectClose(center.y, 5, "ARC1 center y")
        try expectClose(radius, 1, "ARC1 radius")
        try expectClose(startAngle, 4.71238898038469, "ARC1 angle_from (3π/2)")
        try expectClose(endAngle, 0, "ARC1 angle_to")
    } else {
        throw VerifyError.failed("ARC1 first shape is not .arc")
    }

    // ── 5. POINT1 ─────────────────────────────────────────────────────────
    let point = DWGImporter.importDWG(at: fixturePath("POINT1.DWG"))
    try expect(point.success, "POINT1 imports")
    try expect(point.entityCount == 1, "POINT1 → 1 entity")
    if case .circle(let center, _) = point.shapes.first! {
        try expectClose(center.x, 1, "POINT1 x")
        try expectClose(center.y, 2, "POINT1 y")
    } else {
        throw VerifyError.failed("POINT1 first shape is not .circle (point marker)")
    }

    // ── 6. Non-DWG → graceful failure ─────────────────────────────────────
    let tmp = NSTemporaryDirectory()
    let junkURL = URL(fileURLWithPath: tmp + "verify_dwg_junk.dwg")
    try Data("not a dwg at all".utf8).write(to: junkURL)
    let junk = DWGImporter.importDWG(at: junkURL.path)
    try expect(!junk.success, "non-DWG fails gracefully")
    try expect(junk.errorMessage != nil, "failure carries a message")

    // Post-R12 version header → unsupported-version message.
    let newerURL = URL(fileURLWithPath: tmp + "verify_dwg_2000.dwg")
    var newer = Data("AC1015".utf8)
    newer.append(Data(repeating: 0, count: 24))
    try newer.write(to: newerURL)
    let newerResult = DWGImporter.importDWG(at: newerURL.path)
    try expect(!newerResult.success, "AC1015 (2000) rejected")
    try expect(newerResult.errorMessage?.contains("export to DXF") == true,
               "unsupported version message points to DXF (got \(newerResult.errorMessage ?? "nil"))")

    print("ShopPilotVerifyDWGImport: PASS — real R12 fixtures (LINE1 2D, LINE2 3D, CIRCLE1, ARC1, POINT1) match the reference ground truth; non-DWG + AC1015 fail gracefully")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyDWGImport: FAIL — \(error)")
    exit(1)
}
