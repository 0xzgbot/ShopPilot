import Foundation
import ShopPilotCore

/// SPK-2000a verify — expanded shipped post catalog (cross-platform parity).
///
/// Covers:
///   1. Catalog size ≥ 54 templates (parity surface) with unique ids.
///   2. Every template emits through PostTemplateEngine for a sample program
///      (header + moves + footer, no crash, move count preserved).
///   3. Units variants are distinct (mm body carries G21, inch G20).
///   4. Grouping is total: every template lands in exactly one group.
///   5. Laser dialect carries $32=1 + M5; industrial carries G28/M30;
///      plasma carries THC enable/disable.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

let sampleProgram = [
    "G0 Z5.000",
    "G0 X10 Y10",
    "G1 Z-1.000 F300",
    "G1 X50 F1000",
    "G1 X50 Y50",
    "G0 Z5.000",
]

func verify() throws {
    // 1. Size + uniqueness.
    let all = PostTemplate.shipped
    try expect(all.count >= 54, "catalog has ≥54 templates (got \(all.count))")
    let ids = all.map(\.id)
    try expect(Set(ids).count == ids.count, "template ids are unique")

    // 2. Every template emits a full program.
    for template in all {
        let result = PostTemplateEngine.emit(gcodeLines: sampleProgram, template: template)
        try expect(result.lines.count > sampleProgram.count,
                   "\(template.id): emitted more than raw input (got \(result.lines.count))")
        try expect(result.moveCount == sampleProgram.count,
                   "\(template.id): moveCount preserved (\(result.moveCount) vs \(sampleProgram.count))")
        let joined = result.lines.joined(separator: "\n")
        try expect(joined.contains("X50"), "\(template.id): move coordinates survive the post")
        // No unresolved format specifiers may leak into output.
        try expect(!joined.contains("[N|A"), "\(template.id): no raw recipe specifiers in output")
    }

    // 3. Units variants distinct.
    for family in ["grbl", "haas", "fanuc", "fluidnc", "longmill"] {
        let mm = try PostTemplate.shipped(byID: "\(family)-mm") ?? {
            if family == "grbl" { return PostTemplate.grbl(units: .millimeter) }
            throw VerifyError.failed("missing \(family)-mm template")
        }()
        let inch = try PostTemplate.shipped(byID: "\(family)-in") ?? {
            if family == "grbl" { return PostTemplate.grbl(units: .inch) }
            throw VerifyError.failed("missing \(family)-in template")
        }()
        try expect(mm.text.contains("G21"), "\(family): mm post carries G21")
        try expect(inch.text.contains("G20"), "\(family): inch post carries G20")
        try expect(mm.text != inch.text, "\(family): mm/inch bodies differ")
    }

    // 4. Grouping is total and non-empty per group.
    let grouped = PostTemplate.groupedShipped
    let groupedCount = grouped.reduce(0) { $0 + $1.templates.count }
    try expect(groupedCount == all.count,
               "every template appears in exactly one group (\(groupedCount) vs \(all.count))")
    for section in grouped {
        try expect(!section.templates.isEmpty, "group '\(section.group)' non-empty")
    }
    let names = Set(grouped.map(\.group))
    for expected in ["Routers", "Industrial", "Firmware", "Laser & Plasma"] {
        try expect(names.contains(expected), "group '\(expected)' present")
    }

    // 5. Dialect markers.
    let laser = try PostTemplate.shipped(byID: "laser-grbl-m4-mm")
        ?? { throw VerifyError.failed("missing laser-grbl-m4-mm") }()
    let laserOut = PostTemplateEngine.emit(gcodeLines: sampleProgram, template: laser)
    let laserJoined = laserOut.lines.joined(separator: "\n")
    try expect(laserJoined.contains("$32=1"), "laser post enables $32=1 laser mode")
    try expect(laserJoined.contains("M5"), "laser post turns beam off with M5")

    let fanuc = try PostTemplate.shipped(byID: "fanuc-mm")
        ?? { throw VerifyError.failed("missing fanuc-mm") }()
    let fanucJoined = PostTemplateEngine.emit(gcodeLines: sampleProgram, template: fanuc)
        .lines.joined(separator: "\n")
    try expect(fanucJoined.contains("G28"), "industrial post retracts via G28")
    try expect(fanucJoined.contains("M30"), "industrial post ends with M30")

    let plasma = try PostTemplate.shipped(byID: "plasma-thc-mm")
        ?? { throw VerifyError.failed("missing plasma-thc-mm") }()
    let plasmaJoined = PostTemplateEngine.emit(gcodeLines: sampleProgram, template: plasma)
        .lines.joined(separator: "\n")
    try expect(plasmaJoined.contains("M64 P1") && plasmaJoined.contains("M65 P1"),
               "plasma post toggles THC enable/disable")
}

do {
    try verify()
    print("ShopPilotVerify2000a: PASS — \(PostTemplate.shipped.count) shipped templates, all emit clean, units distinct, groups total, dialect markers verified")
} catch {
    print("ShopPilotVerify2000a: FAIL — \(error)")
    exit(1)
}
