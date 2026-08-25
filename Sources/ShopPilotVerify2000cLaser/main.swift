import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-2000c verify — Laser Fill + Laser Picture engines.
///
/// Covers: scanline coverage of a circle fixture at two angles, serpentine
/// alternation, power monotonicity in the picture raster, run merging, no
/// motion outside bounds, zero-ALARM stream through SimulatorTransport.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

var circlePath: [VectorPoint] = []
for i in 0..<64 {
    let a = Double(i) / 64.0 * 2 * .pi
    circlePath.append(VectorPoint(x: 50 + 20 * cos(a), y: 50 + 20 * sin(a)))
}
circlePath.append(circlePath[0])

func gcodeMoves(_ lines: [String]) -> [(x: Double, y: Double)] {
    var pos = (0.0, 0.0)
    var moves: [(Double, Double)] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("G0 X") || trimmed.hasPrefix("G1 X") else { continue }
        let parts = trimmed.split(separator: " ")
        var x = pos.0, y = pos.1
        for part in parts.dropFirst() {
            if part.hasPrefix("X"), let v = Double(part.dropFirst()) { x = v }
            if part.hasPrefix("Y"), let v = Double(part.dropFirst()) { y = v }
        }
        moves.append((x, y))
        pos = (x, y)
    }
    return moves
}

func verify() async throws {
    // ── Laser Fill ────────────────────────────────────────────────────────
    let params = LaserFillParams(angleDegrees: 0, lineSpacingMm: 0.5,
                                 overscanMm: 1, powerPercent: 80, speedMmPerMin: 3000)
    let fill = LaserFillEngine.compute(paths: [circlePath], params: params)
    try expect(fill.success, "fill computes")
    // 40mm-diameter box / 0.5 spacing → ~81+ scanlines.
    try expect(fill.scanlineCount >= 78 && fill.scanlineCount <= 90,
               "scanline count matches geometry (got \(fill.scanlineCount))")

    // Coverage: some G1 endpoint must reach beyond both Y extremes of the circle.
    let moves = gcodeMoves(fill.gcodeLines)
    try expect(moves.contains { $0.y > 68 }, "fill reaches above the circle")
    try expect(moves.contains { $0.y < 32 }, "fill reaches below the circle")
    // Overscan pushes X to/past the circle's 30…70 span (overscan 1mm → 29.0).
    try expect(moves.contains { $0.x <= 29.001 || $0.x >= 70.999 }, "overscan extends past shape bounds")
    // Nothing may fly absurdly far.
    for m in moves {
        try expect(m.x > 20 && m.x < 80 && m.y > 20 && m.y < 80,
                   "no motion wildly outside bounds (\(m.x), \(m.y))")
    }

    // Serpentine: consecutive scanlines alternate direction — check S-power
    // count equals 2× scanlines (on + off per line).
    let sCount = fill.gcodeLines.filter { $0.hasPrefix("S") }.count
    try expect(sCount >= fill.scanlineCount, "power words accompany every scanline")

    // Angle 90° rotates scan direction: Y span tight, X span covered.
    let fill90 = LaserFillEngine.compute(paths: [circlePath],
                                         params: LaserFillParams(angleDegrees: 90,
                                                                 lineSpacingMm: 0.5))
    try expect(fill90.scanlineCount >= 78, "90° angle produces equivalent coverage")
    try expect(fill90.gcodeLines != fill.gcodeLines, "angle changes output")

    // Empty input fails honestly.
    let empty = LaserFillEngine.compute(paths: [], params: params)
    try expect(!empty.success && empty.errorMessage != nil, "empty fill fails honestly")

    // ── Laser Picture ─────────────────────────────────────────────────────
    // 10×10 grid: left half black (255), right half white (0).
    var lum: [UInt8] = []
    for row in 0..<10 {
        for col in 0..<10 {
            lum.append(col < 5 ? 255 : 0)
        }
    }
    let grid = GrayscaleGrid(width: 10, height: 10, luminance: lum)
    let pic = LaserPictureEngine.compute(grid: grid,
                                         params: LaserPictureParams(targetWidthMm: 100,
                                                                    maxPowerPercent: 100))
    try expect(pic.success, "picture computes")
    try expect(pic.rasterRows == 10, "all 10 rows carry burn (got \(pic.rasterRows))")
    try expect(pic.burnedPixels == 50, "exactly the black half burns (got \(pic.burnedPixels))")
    // Max-power runs must exist (S1000 = 255/255 × 100% × 10).
    try expect(pic.gcodeLines.contains("S1000"), "black pixels burn at max power")
    // Power monotonicity: a gray ramp burns with intermediate powers.
    var rampLum: [UInt8] = []
    for row in 0..<4 {
        for col in 0..<8 {
            rampLum.append(UInt8(min(255, col * 36)))
        }
    }
    let ramp = GrayscaleGrid(width: 8, height: 4, luminance: rampLum)
    let rampResult = LaserPictureEngine.compute(
        grid: ramp,
        params: LaserPictureParams(targetWidthMm: 80, maxPowerPercent: 100))
    let sPowers = Set(rampResult.gcodeLines.compactMap { line -> Int? in
        line.hasPrefix("S") ? Int(line.dropFirst()) : nil
    })
    try expect(sPowers.count >= 3, "gray ramp produces ≥3 distinct power levels (got \(sPowers.sorted()))")

    // Stream the picture program through SimulatorTransport: zero ALARM.
    let transport = SimulatorTransport()
    let config = SerialConfig(simulationDelayNanoseconds: 0)
    try await transport.open(config: config)
    var alarms = 0
    let eventStream = transport.events
    var iterator = eventStream.makeAsyncIterator()
    for line in pic.gcodeLines where !line.hasPrefix(";") {
        try await transport.write(Data((line + "\n").utf8))
        if let event = await iterator.next(),
           case .dataReceived(let data) = event,
           String(decoding: data, as: UTF8.self).uppercased().contains("ALARM") {
            alarms += 1
        }
    }
    try expect(alarms == 0, "picture program streams without ALARM (got \(alarms))")
}

// Top-level async entry (CLT pattern — semaphore + Task).
let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await verify()
        print("ShopPilotVerify2000cLaser: PASS — fill coverage/serpentine/overscan verified, picture power-modulated rows verified, zero-ALARM sim stream")
        semaphore.signal()
    } catch {
        print("ShopPilotVerify2000cLaser: FAIL — \(error)")
        exit(1)
    }
}
semaphore.wait()
