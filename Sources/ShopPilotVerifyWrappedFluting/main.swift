import Foundation
import ShopPilotCore

/// Parity rows H04/H05 — Wrapped Fluting (rotary gadget). Verifies the real
/// wrap math: flat Y maps to A degrees about the X axis via the cylinder
/// circumference (Y = 50mm on Ø50 → A = 360/π ≈ 114.59°), X stays axial,
/// the marker is line 0, M3 S<rpm> fires when rpm > 0, step-down passes
/// plunge in order, CCW mirrors the sweep, params round-trip, and no Y word
/// leaks into the emitted G-code.
enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func pt(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

/// Extract the numeric A word from a G-code line, e.g.
/// "G1 X50.000 A114.592 F1500" → 114.592.
func aValue(from line: String) -> Double? {
    guard let range = line.range(of: "A"),
          let token = line[range.upperBound...].split(separator: " ").first
    else { return nil }
    return Double(token)
}

func main() throws {
    // 1. Single flute (0,0) → (50,50) on Ø50. X stays axial (X50 unchanged);
    //    flat Y = 50 wraps to A = 50/(π·50)·360 = 360/π ≈ 114.59°.
    let params = WrappedFlutingParams(
        startDepthMm: 0,
        cutDepthMm: 4.0,
        passDepthMm: 2.0,
        safeZHeightMm: 5.0,
        feedRateMmPerMin: 1500,
        plungeRateMmPerMin: 300,
        toolDiameterMm: 6.0,
        spindleRpm: 12000,
        wrapDiameterMm: 50.0,
        direction: .clockwise
    )
    let result = WrappedFlutingToolpathEngine.compute(
        points: [pt(0, 0), pt(50, 50)],
        params: params
    )

    // 2. Marker is line 0.
    try expect(result.gcode.first == "O=WRAPPED_FLUTING",
               "marker is line 0 (got \(result.gcode.first ?? "nil"))")
    try expect(result.marker == "O=WRAPPED_FLUTING", "result marker constant")

    // 3. Spindle on when rpm > 0.
    try expect(result.gcode.contains("M3 S12000"), "M3 S12000 present")

    // 1 (cont). A mapping: end A = 360/π ≈ 114.59, start A = 0.
    let rapidStart = result.gcode.first { $0.hasPrefix("G0 X0.000 A0.000") }
    try expect(rapidStart != nil, "start rapids to X0 A0 (got \(result.gcode.filter { $0.hasPrefix("G0 X") }))")
    let feed = result.gcode.first { $0.hasPrefix("G1 X50.000 A") }
    try expect(feed != nil, "feed along flute to X50 (got \(result.gcode.filter { $0.hasPrefix("G1 X") }))")
    let aEnd = aValue(from: feed ?? "") ?? -1
    try expect(abs(aEnd - 360.0 / .pi) < 1e-2,
               "A end = 360/π ≈ 114.59 (got \(aEnd))")

    // 4. passDepth 5 with cutDepth 10 → two plunge passes, Z -5.000 then -10.000.
    let step = WrappedFlutingParams(cutDepthMm: 10.0, passDepthMm: 5.0, spindleRpm: 12000)
    let stepResult = WrappedFlutingToolpathEngine.compute(points: [pt(0, 0), pt(50, 50)], params: step)
    let plunges = stepResult.gcode.filter { $0.hasPrefix("G1 Z") }
    try expect(plunges.count == 2, "two plunge passes (got \(plunges))")
    try expect(plunges[0].contains("Z-5.000") && plunges[1].contains("Z-10.000"),
               "plunges in order -5 then -10 (got \(plunges))")
    try expect(stepResult.moveCount == 4,
               "moveCount = 4 G1 moves (2 passes × plunge + feed) (got \(stepResult.moveCount))")

    // 5. counterClockwise mirrors the A value: 360 − 360/π ≈ 245.41.
    let ccw = WrappedFlutingParams(wrapDiameterMm: 50.0, direction: .counterClockwise)
    let ccwResult = WrappedFlutingToolpathEngine.compute(points: [pt(0, 0), pt(50, 50)], params: ccw)
    let ccwFeed = ccwResult.gcode.first { $0.hasPrefix("G1 X50.000 A") }
    try expect(ccwFeed != nil, "CCW feed line present")
    let aCcw = aValue(from: ccwFeed ?? "") ?? -1
    try expect(abs(aCcw - (360.0 - 360.0 / .pi)) < 1e-2,
               "CCW mirrors A to 360−360/π ≈ 245.41 (got \(aCcw))")

    // 6. Codable round-trip of params.
    let data = try JSONEncoder().encode(params)
    let back = try JSONDecoder().decode(WrappedFlutingParams.self, from: data)
    try expect(abs(back.wrapDiameterMm - 50.0) < 1e-9, "wrap diameter round-trips")
    try expect(back.direction == .clockwise, "direction round-trips")
    try expect(abs(back.cutDepthMm - 4.0) < 1e-9, "cut depth round-trips")
    try expect(abs(back.spindleRpm - 12000) < 1e-9, "spindle rpm round-trips")

    // 7. No 'Y' word appears in any emitted G-code line.
    for line in result.gcode {
        try expect(!line.contains("Y"), "no Y word in '\(line)'")
    }

    print("ShopPilotVerifyWrappedFluting: PASS — Y→A wrap (50mm→114.59°), X axial, marker line 0, M3 S12000, step-down plunges -5/-10, CCW mirror (245.41°), Codable round-trip, no Y words")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyWrappedFluting: FAIL — \(error)")
    exit(1)
}
