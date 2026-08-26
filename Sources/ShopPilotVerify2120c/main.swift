import Foundation
import ShopPilotCore

// SPK-2120c — Crisp-letters medial cell preset (no MedialAxis rewrite).
// AC: Valley form preset sets medialAxisCellMm = 0.2 with a time warning;
//     a letter fixture at 0.2 mm differs vs 1.0 mm cell.

var failures = 0
func expect(_ cond: Bool, _ label: String) {
    print((cond ? "  ok  " : " FAIL ") + label)
    if !cond { failures += 1 }
}

func ridgeCount(_ r: MedialAxis.Result) -> Int {
    r.paths.reduce(0) { $0 + $1.count }
}

/// Closed outline of a serif-less capital T (24×30 mm, 6 mm stroke).
func letterT() -> [VectorPoint] {
    [
        VectorPoint(x: 0, y: 24), VectorPoint(x: 9, y: 24),
        VectorPoint(x: 9, y: 0), VectorPoint(x: 15, y: 0),
        VectorPoint(x: 15, y: 24), VectorPoint(x: 24, y: 24),
        VectorPoint(x: 24, y: 30), VectorPoint(x: 0, y: 30),
    ]
}

func fileText(_ rel: String) -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(rel)
    guard let s = try? String(contentsOf: url, encoding: .utf8) else {
        print(" FAIL  cannot read \(rel) from repo root")
        failures += 1
        return ""
    }
    return s
}

func main() throws {
    // ── 1. Param contract: default 1.0; preset value 0.2 round-trips. ─────
    let p = VCarveParams()
    expect(p.medialAxisCellMm == 1.0, "init default medialAxisCellMm = 1.0")
    var crisp = VCarveParams()
    crisp.medialAxisCellMm = 0.2
    expect(crisp.medialAxisCellMm == 0.2, "crisp-letters preset sets 0.2 mm")
    let roundtrip = try JSONDecoder().decode(VCarveParams.self, from: try JSONEncoder().encode(crisp))
    expect(roundtrip.medialAxisCellMm == 0.2, "crisp cell size round-trips")

    // ── 2. Warning lives on the params type (Valley form binds to this). ──
    expect(crisp.showsMedialCellTimeWarning, "0.2 mm cell → warning shown")
    var almost = VCarveParams(); almost.medialAxisCellMm = 0.49
    expect(almost.showsMedialCellTimeWarning, "0.49 mm cell → warning shown")
    var boundary = VCarveParams(); boundary.medialAxisCellMm = 0.5
    expect(!boundary.showsMedialCellTimeWarning, "0.5 mm cell → no warning (boundary)")
    expect(!p.showsMedialCellTimeWarning, "1.0 mm cell → no warning")

    // ── 3. Letter fixture: 0.2 mm cell differs vs 1.0 mm (more samples). ──
    let t = letterT()
    let coarse = MedialAxis.compute(outline: t, cellMm: 1.0)
    let fine = MedialAxis.compute(outline: t, cellMm: 0.2)
    expect(!coarse.isEmpty, "T at 1.0 mm cell → non-empty skeleton")
    expect(!fine.isEmpty, "T at 0.2 mm cell → non-empty skeleton")
    let coarseN = ridgeCount(coarse), fineN = ridgeCount(fine)
    expect(fineN > coarseN,
           "T skeleton denser at 0.2 mm than 1.0 mm (\(fineN) > \(coarseN))")

    var coarseP = VCarveParams(); coarseP.medialAxisCellMm = 1.0; coarseP.maxDepthOfCutMm = 6
    var fineP = VCarveParams(); fineP.medialAxisCellMm = 0.2; fineP.maxDepthOfCutMm = 6
    let letterPath = VectorPath(points: t, isClosed: true)
    let coarseG = VCarveEngine.compute(vectors: [letterPath], params: coarseP).gcodeLines
    let fineG = VCarveEngine.compute(vectors: [letterPath], params: fineP).gcodeLines
    let coarseCuts = coarseG.filter { $0.hasPrefix("G1") && ($0.contains("X") || $0.contains("Y")) }.count
    let fineCuts = fineG.filter { $0.hasPrefix("G1") && ($0.contains("X") || $0.contains("Y")) }.count
    expect(fineCuts > coarseCuts,
           "T toolpath has more G1s at 0.2 mm cell than 1.0 mm (\(fineCuts) > \(coarseCuts))")
    expect(coarseG != fineG, "T G-code at 0.2 mm is not byte-identical to 1.0 mm")

    // ── 4. Valley form: Crisp Letters button + warning bound to helper. ───
    let ui = fileText("Sources/ShopPilot/ContentView.swift")
    expect(ui.contains("Crisp Letters (0.2 mm cell)"),
           "Valley form has Crisp Letters preset button")
    expect(ui.contains("params.medialAxisCellMm = 0.2"),
           "preset assigns medialAxisCellMm = 0.2")
    expect(ui.contains("showsMedialCellTimeWarning"),
           "Valley form warning uses VCarveParams.showsMedialCellTimeWarning")
    expect(!ui.contains("MedialAxis.swift"),
           "ContentView does not rewrite MedialAxis")

    print(failures == 0
          ? "ShopPilotVerify2120c: PASS"
          : "ShopPilotVerify2120c: FAIL (\(failures))")
    if failures > 0 { exit(1) }
}

try main()
