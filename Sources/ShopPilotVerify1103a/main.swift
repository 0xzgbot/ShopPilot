import Foundation
import ShopPilotCore

/// SPK-1103a verify without XCTest (CLT-only): wireframe segments + draft height samples.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let gcode = [
        "G21",
        "G90",
        "G0 X0 Y0",
        "G0 Z5",
        "G1 Z-2 F300",
        "G1 X50 Y0 F800",
        "G1 X50 Y30",
        "G1 X0 Y30",
        "G1 X0 Y0",
        "G0 Z5",
        "G0X10Y10",
        "G1X20Y10",
    ]

    let segments = WireframeRenderer.generateSegments(from: gcode)
    try expect(segments.count >= 5, "expected several wireframe segments, got \(segments.count)")
    try expect(segments.contains(where: { !$0.isRapid }), "expected at least one cut segment")
    try expect(segments.contains(where: { $0.isRapid }), "expected at least one rapid segment")

    // Compact modal XY without spaces
    let compact = WireframeRenderer.parseXY(from: "G1X20Y10", previousX: 10, previousY: 10)
    try expect(compact?.x == 20 && compact?.y == 10, "compact parseXY")
    try expect(compact?.isRapid == false, "compact G1 not rapid")

    let samples = ToolpathSimulator.draftHeightSamples(from: gcode, cellSizeMm: 2.0, stockMm: 80)
    try expect(!samples.samples.isEmpty, "draft height samples non-empty")
    try expect(samples.seconds >= 0, "simulation time")

    print("ShopPilotVerify1103a PASS — segments=\(segments.count) samples=\(samples.samples.count)")
}

do {
    try main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
