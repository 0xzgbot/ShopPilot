import Foundation
import ShopPilotCore
import ShopPilotGeometry

// SPK-2023c — 2D rest machining verify (PocketToolpath.swift).
// Asserts: prev=0 byte-identical, leftover-band containment (1/4" cleared,
// 1/16" rest pass), depth-level floor-once, legacy decode + round-trip.

func expect(_ cond: Bool, _ msg: String) {
    guard cond else { print("ShopPilotVerify2023c: FAIL — \(msg)"); exit(1) }
}

// Closed rectangle pocket: 60 x 40 mm.
let points: [VectorPoint] = [
    VectorPoint(x: 0, y: 0),
    VectorPoint(x: 60, y: 0),
    VectorPoint(x: 60, y: 40),
    VectorPoint(x: 0, y: 40),
    VectorPoint(x: 0, y: 0)
]
let rect = VectorPath(name: "Rect", points: points, isClosed: true)

var params = PocketToolpathParams(
    clearanceMode: .zigzag,
    stepOverMm: 3.0,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 6.35,
    safetyHeightMm: 5.0,
    spindleRpm: 18000
)
let stockHeight = 4.0

// --- 1) prev=0 must be byte-identical to the full clear ---
let base = PocketToolpathEngine.compute(vectors: [rect], params: params, stockHeightMm: stockHeight)
params.previousToolDiameterMm = 0
let zero = PocketToolpathEngine.compute(vectors: [rect], params: params, stockHeightMm: stockHeight)
expect(base.gcodeLines == zero.gcodeLines, "prev=0 output changed vs baseline")
print("ok 1/4 prev=0 byte-identical (\(zero.gcodeLines.count) lines)")

// Legacy JSON without the new key still decodes.
let legacyJSON = #"{"clearanceMode":"zigzag","stepOverMm":3,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"maxDepthOfCutMm":2,"toolDiameterMm":6.35,"safetyHeightMm":5,"spindleRpm":18000,"startDepthMm":0,"passCount":0,"exactStepDepth":false,"cutDirection":"climb","rasterAngleDegrees":0,"profilePass":"last","allowanceMm":0,"rampPlungeMoves":false,"useVectorSelectionOrder":false}"#
let legacyParams = try! JSONDecoder().decode(PocketToolpathParams.self, from: Data(legacyJSON.utf8))
expect(legacyParams.previousToolDiameterMm == 0, "legacy decode should default previousToolDiameterMm to 0")
print("ok  legacy decode defaults to 0")

// Round-trip with a nonzero value.
params.previousToolDiameterMm = 6.35
let rtData = try! JSONEncoder().encode(params)
let rtParams = try! JSONDecoder().decode(PocketToolpathParams.self, from: rtData)
expect(rtParams.previousToolDiameterMm == 6.35, "previousToolDiameterMm round-trip")
print("ok  round-trip preserves 6.35")

// --- 2) Rest pass machines ONLY the leftover band ---
// 1/4" (6.35 mm) cleared first; 1/16" (1.5875 mm) cleans up the corners.
// prevInset = 3.175 ; curInset = 0.79375.
let restParams = PocketToolpathParams(
    clearanceMode: .zigzag,
    stepOverMm: 3.0,
    feedRateMmPerMin: 1000,
    plungeFeedRateMmPerMin: 300,
    maxDepthOfCutMm: 2.0,
    toolDiameterMm: 1.5875,
    safetyHeightMm: 5.0,
    spindleRpm: 18000,
    startDepthMm: 0, passCount: 0, exactStepDepth: false,
    cutDirection: .climb, rasterAngleDegrees: 0, profilePass: .last,
    allowanceMm: 0, rampPlungeMoves: false, useVectorSelectionOrder: false,
    previousToolDiameterMm: 6.35
)
let rest = PocketToolpathEngine.compute(vectors: [rect], params: restParams, stockHeightMm: stockHeight)

let cutLines = rest.gcodeLines.filter { $0.hasPrefix("G1 X") }
expect(!cutLines.isEmpty, "rest pass emitted no cut moves")

// Current tool's reachable region (inset by its radius).
let minX = 0 + 1.5875 / 2            // 0.79375
let maxX = 60 - 1.5875 / 2           // 59.20625
let minY = 0 + 1.5875 / 2
let maxY = 40 - 1.5875 / 2
// Region already cleared by the 1/4" tool (inset by ITS radius).
let cminX = 0 + 6.35 / 2             // 3.175
let cmaxX = 60 - 6.35 / 2            // 56.825
let cminY = 0 + 6.35 / 2
let cmaxY = 40 - 6.35 / 2

for line in cutLines {
    // Parse "G1 X<x> Y<y> F..." — every cut endpoint must lie inside the
    // reachable region and NOT inside the previously-cleared rectangle.
    let toks = line.split(separator: " ")
    let xs = toks.first { $0.hasPrefix("X") }.flatMap { Double($0.dropFirst()) }
    let ys = toks.first { $0.hasPrefix("Y") }.flatMap { Double($0.dropFirst()) }
    guard let x = xs, let y = ys else {
        print("ShopPilotVerify2023c: FAIL — unparseable cut line: \(line)"); exit(1)
    }

    expect(x >= minX - 0.001 && x <= maxX + 0.001, "cut x=\(x) outside current tool reach [\(minX),\(maxX)]")
    expect(y >= minY - 0.001 && y <= maxY + 0.001, "cut y=\(y) outside current tool reach")

    let insideClearedX = x > cminX && x < cmaxX
    let insideClearedY = y > cminY && y < cmaxY
    expect(!(insideClearedX && insideClearedY),
           "cut (\(x),\(y)) lies INSIDE the previously-cleared region [x:\(cminX)-\(cmaxX) y:\(cminY)-\(cmaxY)]")
}
print("ok 2/4 all \(cutLines.count) cut endpoints inside leftover band only")

// Corner spot-check: the extreme corner point of the leftover band must be cut.
expect(cutLines.contains { $0.contains(String(format: "X%.3f", minX)) } ||
       cutLines.contains { $0.contains(String(format: "X%.3f", maxX)) },
       "rest pass never reaches the wall-side edge of the band")

// --- 3) Floor covered once: one depth level per maxDepthOfCut across passes ---
let zDepths = Set(rest.gcodeLines.compactMap { line -> Double? in
    guard line.hasPrefix("G1 Z") else { return nil }
    return Double(line.split(separator: " ")[1].dropFirst())
})
expect(zDepths.count == Int(ceil(stockHeight / 2.0)), "expected \(Int(ceil(stockHeight / 2.0))) depth levels, got \(zDepths.count)")
print("ok 3/4 depth levels match single-pass-per-level semantics (\(zDepths.count) levels)")

// --- 4) Rest pass cuts STRICTLY LESS total distance than a full re-clear ---
// Track consecutive endpoints: each "G1 X.. Y.." line is a cut move whose
// start is the previous position. Sum Euclidean lengths of all G1 XY moves.
func totalCutDistance(_ lines: [String]) -> Double {
    var cx = 0.0, cy = 0.0, total = 0.0
    for line in lines {
        let toks = line.split(separator: " ")
        guard let xt = toks.first(where: { $0.hasPrefix("X") }),
              let yt = toks.first(where: { $0.hasPrefix("Y") }),
              let nx = Double(xt.dropFirst()), let ny = Double(yt.dropFirst())
        else { continue }
        if line.hasPrefix("G1") {
            total += ((nx - cx) * (nx - cx) + (ny - cy) * (ny - cy)).squareRoot()
        }
        cx = nx; cy = ny
    }
    return total
}
var fullParams = restParams
fullParams.previousToolDiameterMm = 0
let fullClear = PocketToolpathEngine.compute(vectors: [rect], params: fullParams, stockHeightMm: stockHeight)
let restDist = totalCutDistance(rest.gcodeLines)
let fullDist = totalCutDistance(fullClear.gcodeLines)
expect(restDist > 0 && restDist < fullDist,
       "rest distance \(restDist) not strictly within (0, full-clear \(fullDist))")
print(String(format: "ok 4/4 rest cut distance %.1f mm < full re-clear %.1f mm", restDist, fullDist))

print("ShopPilotVerify2023c: PASS — rest machining engine verified")
