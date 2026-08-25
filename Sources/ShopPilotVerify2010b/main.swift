import Foundation
import ShopPilotCore

// SPK-2010b — width-derived Z + medial pass wired into VCarveEngine.
// Ports the sibling's VCarveMedialAxisTests engine asserts (semantics only).

enum VerifyError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let m): return m }
    }
}

func expect(_ cond: Bool, _ msg: String) throws {
    guard cond else { throw VerifyError.failed(msg) }
}

// MARK: - Dumbbell fixture (family reference, verbatim)

func dumbbell() -> [VectorPoint] {
    var pts: [VectorPoint] = []
    let r = 30.0, neckHalf = 6.0
    let leftC = 40.0, rightC = 160.0, cy = 100.0

    for i in 0...24 {
        let a = Double.pi + Double(i) / 24.0 * (Double.pi / 2 + Double.pi / 6)
        pts.append(VectorPoint(x: leftC + cos(a) * r, y: cy + sin(a) * r))
    }
    pts.append(VectorPoint(x: leftC + 20, y: cy - neckHalf))
    pts.append(VectorPoint(x: rightC - 20, y: cy - neckHalf))
    for i in 0...24 {
        let a = -Double.pi / 3 + Double(i) / 24.0 * (Double.pi / 3 + Double.pi / 2 + Double.pi / 3)
        pts.append(VectorPoint(x: rightC + cos(a) * r, y: cy + sin(a) * r))
    }
    pts.append(VectorPoint(x: rightC - 20, y: cy + neckHalf))
    pts.append(VectorPoint(x: leftC + 20, y: cy + neckHalf))
    for i in 0...24 {
        let a = 2 * Double.pi / 3 + Double(i) / 24.0 * (Double.pi / 3)
        pts.append(VectorPoint(x: leftC + cos(a) * r, y: cy + sin(a) * r))
    }
    return pts
}

struct Cut { let x: Double; let y: Double; let z: Double }

/// Parse G1 cut moves (with XY) from G-code lines, tracking modal X/Y/Z.
func cuts(_ gcode: [String]) -> [Cut] {
    var out: [Cut] = []
    var x = 0.0, y = 0.0, z = 0.0
    for raw in gcode {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("G1 ") || line == "G1" else { continue }
        var sawXY = false
        for tok in line.split(separator: " ").dropFirst() {
            guard tok.count >= 2, let v = Double(tok.dropFirst()) else { continue }
            switch tok.first.map(String.init) {
            case "X": x = v; sawXY = true
            case "Y": y = v; sawXY = true
            case "Z": z = v
            default: break
            }
        }
        if sawXY { out.append(Cut(x: x, y: y, z: z)) }
    }
    return out
}

func carveParams(medialAxis: Bool) -> VCarveParams {
    VCarveParams(
        vBitAngleDegrees: 90,
        feedRateMmPerMin: 1000,
        maxDepthOfCutMm: 20,
        stepOverMm: 2,
        spindleRpm: 12000,
        medialAxisPass: medialAxis,
        medialAxisCellMm: 1.5
    )
}
let carveVectors = [VectorPath(name: "dumbbell", points: dumbbell(), isClosed: true)]

func main() throws {
    // ── AC2 — bulbs cut deeper than the neck; interior visited. ────────────
    let with = VCarveEngine.compute(vectors: carveVectors, params: carveParams(medialAxis: true))
    let allCuts = cuts(with.gcodeLines).filter { $0.z < -0.01 }
    try expect(!allCuts.isEmpty, "medial-on carve produced no cut moves below Z-0.01")

    let bulb = allCuts.filter { $0.x < 55 || $0.x > 145 }
    let neck = allCuts.filter { $0.x > 75 && $0.x < 125 }
    try expect(!bulb.isEmpty, "no cuts inside the bulbs")
    try expect(!neck.isEmpty, "no cuts along the neck")

    let deepestBulb = bulb.map(\.z).min()!
    let deepestNeck = neck.map(\.z).min()!
    try expect(deepestBulb < deepestNeck,
               "bulb deepest \(deepestBulb) is not deeper than neck deepest \(deepestNeck)")

    // Neck interior: cuts near the neck centre line (y=100 ±3), where the
    // outline itself is ±6 mm away — only the skeleton reaches it.
    let neckInterior = allCuts.filter { $0.x > 75 && $0.x < 125 && abs($0.y - 100) < 3 }
    try expect(!neckInterior.isEmpty, "the toolpath never visits the neck interior")

    // Bulb interior: within 12 mm of the left bulb centre (40,100).
    let bulbInterior = allCuts.filter {
        hypot($0.x - 40, $0.y - 100) < 12
    }
    try expect(!bulbInterior.isEmpty, "the toolpath never visits the bulb interior")
    let deepestBulbInteriorZ = bulbInterior.map(\.z).min()!

    // ── AC3 — without the medial pass the interior is never reached. ───────
    let without = VCarveEngine.compute(vectors: carveVectors, params: carveParams(medialAxis: false))
    let outlineOnly = cuts(without.gcodeLines)
        .filter { $0.z < -0.01 }
        .filter { hypot($0.x - 40, $0.y - 100) < 12 }
    try expect(outlineOnly.isEmpty,
               "outline-only carving reached the bulb interior (\(outlineOnly.count) cuts) — Y-shading regression?")

    // Medial on adds cutting moves over off.
    try expect(allCuts.count > cuts(without.gcodeLines).count,
               "medial pass added nothing (\(allCuts.count) vs \(cuts(without.gcodeLines).count))")

    // Medial marker present iff on.
    try expect(with.gcodeLines.contains { $0.contains("(Medial axis:") },
               "medial-on output missing its comment marker")
    try expect(!without.gcodeLines.contains { $0.contains("(Medial axis:") },
               "medial-off output must not carry the medial comment")

    // Deepest interior cut is meaningfully deep (bulbs are 30 mm wide).
    try expect(deepestBulbInteriorZ < -5,
               "bulb interior barely cut (deepest \(deepestBulbInteriorZ))")

    // ── AC1 — width-Z, not page-Y: slot vs circle at the same sheet Y. ─────
    // A 12mm-wide slot and a 40mm-radius circle centred at the SAME Y must
    // not share one Z — the wide shape carves deeper at its widest point.
    func rectPath(w: Double, h: Double, cx: Double, cy: Double) -> VectorPath {
        VectorPath(
            name: "rect",
            points: [
                VectorPoint(x: cx - w / 2, y: cy - h / 2),
                VectorPoint(x: cx + w / 2, y: cy - h / 2),
                VectorPoint(x: cx + w / 2, y: cy + h / 2),
                VectorPoint(x: cx - w / 2, y: cy + h / 2),
                VectorPoint(x: cx - w / 2, y: cy - h / 2),
            ],
            isClosed: true
        )
    }
    // Width-Z needs the skeleton for smooth curves (outline vertices alone
    // sit ON the wall); run both shapes with the default medial-on params.
    let slotRes = VCarveEngine.compute(
        vectors: [rectPath(w: 12, h: 60, cx: 50, cy: 100)],
        params: carveParams(medialAxis: true))
    var circle: [VectorPoint] = []
    for i in 0..<72 {
        let a = Double(i) / 72.0 * 2 * .pi
        circle.append(VectorPoint(x: 200 + cos(a) * 40, y: 100 + sin(a) * 40))
    }
    let circleRes = VCarveEngine.compute(
        vectors: [VectorPath(name: "circle", points: circle, isClosed: true)],
        params: carveParams(medialAxis: true))
    let slotDeepest = cuts(slotRes.gcodeLines).map(\.z).min() ?? 0
    let circleDeepest = cuts(circleRes.gcodeLines).map(\.z).min() ?? 0
    try expect(circleDeepest < slotDeepest - 1.0,
               "circle (r=40) deepest \(circleDeepest) should be clearly deeper than slot (w=12) deepest \(slotDeepest)")
    // The slot's medial spine rides the centreline at half-width ~6 → Z≈−6,
    // even though its sharp outline corners legitimately measure the long
    // dimension and cut deeper.
    let slotSpine = cuts(slotRes.gcodeLines).filter { abs($0.x - 50) <= 2.25 && abs($0.z + 6.0) < 0.75 }
    try expect(!slotSpine.isEmpty,
               "slot spine should cut near Z−6 at the centreline, found none")

    // ── AC4 — open polyline: marker emitted, no medial pass. ───────────────
    let open = VectorPath(
        name: "open",
        points: [
            VectorPoint(x: 0, y: 0), VectorPoint(x: 30, y: 0),
            VectorPoint(x: 30, y: 30), VectorPoint(x: 60, y: 30),
        ],
        isClosed: false
    )
    let openRes = VCarveEngine.compute(
        vectors: [open], params: carveParams(medialAxis: true))
    try expect(openRes.gcodeLines.contains("O=V_CARVE_TOOLPATH"),
               "open polyline still emits O=V_CARVE_TOOLPATH")
    try expect(!openRes.gcodeLines.contains { $0.contains("(Medial axis:") },
               "open polyline must NOT get a medial pass")
    try expect(cuts(openRes.gcodeLines).count > 0, "open polyline emits cut moves")

    // ── AC5 — hygiene: no M6/G28, M3 only when rpm>0, deterministic. ───────
    for res in [with, without, slotRes, circleRes, openRes] {
        try expect(!res.gcodeLines.contains { $0.contains("M6") || $0.contains("G28") },
                   "M6/G28 must never appear")
        try expect(res.gcodeLines.contains("%"), "program must keep % wrapper")
        try expect(res.gcodeLines.last == "%", "trailing % closes the program")
    }
    var noRpm = carveParams(medialAxis: true)
    noRpm.spindleRpm = 0
    let noRpmRes = VCarveEngine.compute(vectors: carveVectors, params: noRpm)
    try expect(!noRpmRes.gcodeLines.contains { $0.hasPrefix("M3 S") },
               "rpm=0 must not emit M3")
    try expect(with.gcodeLines.contains { $0.hasPrefix("M3 S") },
               "rpm>0 must emit M3")

    let withAgain = VCarveEngine.compute(vectors: carveVectors, params: carveParams(medialAxis: true))
    try expect(withAgain.gcodeLines == with.gcodeLines, "compute must be deterministic")

    print("ShopPilotVerify2010b: PASS — V-carve valley spine (\(allCuts.count) medial-on cuts, bulb \(deepestBulb) < neck \(deepestNeck), interior visited iff medial on)")
}

do {
    try main()
} catch {
    print("ShopPilotVerify2010b: FAIL — \(error)")
    exit(1)
}
