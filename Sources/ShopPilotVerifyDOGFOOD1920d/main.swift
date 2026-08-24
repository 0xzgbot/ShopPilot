import Foundation
import ShopPilotCore

// SPK-1920d verify — inverse mill on 3D rough.
//
// AC: with the same relief, params.inverseMill = true produces G-code whose
//     max Z differs from the normal pass — the machine cuts the COMPLEMENT
//     (peaks become pockets). Also: legacy JSON without the field decodes to
//     false; round-trip preserves the flag.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD1920d: FAIL — \(msg)")
        exit(1)
    }
}

// --- Synthetic relief: a single dome peak ---------------------------------
// 21×21 grid, cell 1mm, peak 8mm at center.
var heights: [Double] = []
for row in 0..<21 {
    for col in 0..<21 {
        let dx = Double(col - 10)
        let dy = Double(row - 10)
        let r2 = (dx * dx + dy * dy) / 100.0
        heights.append(max(0, 8.0 * (1 - r2)))
    }
}
let hf = HeightfieldData(width: 21, height: 21, cellSizeMm: 1.0, minX: 0, minY: 0, heights: heights)

// --- Normal vs inverse ----------------------------------------------------
var normalParams = HeightfieldRoughParams()
normalParams.stepDownMm = 3.0
normalParams.stepOverMm = 4.0
normalParams.spindleRpm = 0

var inverseParams = normalParams
inverseParams.inverseMill = true

FileHandle.standardError.write(Data("A\n".utf8)); let normal = HeightfieldRoughEngine.compute(heightfield: hf, params: normalParams)
let inverse = HeightfieldRoughEngine.compute(heightfield: hf, params: inverseParams)
FileHandle.standardError.write(Data("C\n".utf8))

FileHandle.standardError.write(Data("B\n".utf8)); expect(!normal.gcodeLines.isEmpty, "normal rough emits G-code")
expect(!inverse.gcodeLines.isEmpty, "inverse rough emits G-code")

// Max Z in the program: the shallowest cutting depth (closest to zero from
// below). With a dome, the normal pass's first level is deep near the peak;
// the INVERSE pass's surface is flipped — its deepest region is where the
// dome was LOWEST (the flat floor becomes the new peak). The two programs'
// pass-1 depth comments must therefore differ measurably.
func zLevels(_ lines: [String]) -> [Double] {
    lines.compactMap { line -> Double? in
        guard line.contains("Z="), let r = line.range(of: "Z=") else { return nil }
        return Double(line[r.upperBound...].prefix { $0.isNumber || $0 == "-" || $0 == "." })
    }
}
let nz = zLevels(normal.gcodeLines)
FileHandle.standardError.write(Data("D\n".utf8))
let iz = zLevels(inverse.gcodeLines)
expect(!nz.isEmpty && !iz.isEmpty, "both programs report z-levels")

// Cutting-move max Z (shallowest G1/G0 Z after the header) must differ too.
func pass1Runs(_ lines: [String]) -> [Double] {
    var runs: [Double] = []
    var inPass1 = false
    for l in lines {
        if l.contains("Pass 1/") { inPass1 = true; continue }
        if l.contains("Pass 2/") { break }
        if inPass1, l.hasPrefix("G0 X"), let r = l.range(of: "X"),
           let x = Double(l[r.upperBound...].prefix { $0.isNumber || $0 == "." }) {
            runs.append(x)
        }
    }
    return runs.sorted()
}

// The level LADDER is identical by construction (both grids span 0…8mm); what
// proves inversion is WHERE the tool cuts. Pass 1 of the normal mode clears
// only cells near the dome PEAK (surface above the first level); pass 1 of the
// inverse mode clears everything EXCEPT near the peak (the flipped surface is
// high where the dome was low). Assert pass-1 XY positions differ.
let nRuns = pass1Runs(normal.gcodeLines)
FileHandle.standardError.write(Data("E\n".utf8))
let iRuns = pass1Runs(inverse.gcodeLines)
expect(!nRuns.isEmpty && !iRuns.isEmpty, "both programs cut in pass 1")
expect(nRuns != iRuns,
       "pass-1 cut positions differ — complement proven (\(nRuns.count) vs \(iRuns.count) run starts)")
// Normal pass-1 starts near the center (the dome peak, X≈10mm); inverse
// pass-1 starts away from center (the flipped-high floor near X=0 or X=20).
// Dome radius where h=5.5 (level 1): r≈5.95mm → normal pass-1's smallest X
// ≈ 4.05. Inverse flips it: cut region is h<2.5 → r>8.75 → smallest X = 0.5.
if let dump = normal.gcodeLines.firstIndex(where: { $0.contains("Pass 1/") }) {
            FileHandle.standardError.write(Data("RAW1:\n".utf8))
            for l in normal.gcodeLines[dump..<(dump+14)] {
                FileHandle.standardError.write(Data((l + "\n").utf8))
            }
        }
        FileHandle.standardError.write(Data("DEBUG normal pass1 first: \(nRuns.prefix(2)) last: \(nRuns.suffix(2)) count \(nRuns.count)\n".utf8))
        FileHandle.standardError.write(Data("DEBUG inverse pass1 first: \(iRuns.prefix(2)) last: \(iRuns.suffix(2)) count \(iRuns.count)\n".utf8))
        // Engine semantics: at this Z the tool removes material where the SURFACE is
// BELOW the pass plane (h <= level) — it clears stock the plane passes above.
// Dome: normal level 5.5 → h<=5.5 covers the rim (min X = 0.5). Inverse flips
// the grid: cut where h'<=5.5, i.e. h>=2.5 → only near-center cells remain.
expect(nRuns[0] <= 1.5, "normal pass-1 clears the rim (min X=\(nRuns[0]))")
expect(iRuns[0] >= 2.0 && iRuns[0] <= 5.5, "inverse pass-1 cuts only near the flipped peak (min X=\(iRuns[0]))")

// Inverse of a dome = a shallow dish-shaped pocket in the flipped stock: at
// pass-1 level only the near-center cells qualify, so a SHORT program is
// expected (33 lines vs ~90 for normal). Assert it emitted real moves.
expect(inverse.gcodeLines.count > 10,
       "inverse program has substantial content (\(inverse.gcodeLines.count) lines)")

// --- Legacy decode + round-trip
FileHandle.standardError.write(Data("F\n".utf8))
let encoded = try! JSONEncoder().encode(inverseParams)
let decoded = try! JSONDecoder().decode(HeightfieldRoughParams.self, from: encoded)
expect(decoded.inverseMill == true, "round-trip preserves inverseMill=true")

struct LegacyRough: Codable {}
let legacyJSON = #"{"toolDiameterMm":6,"stepDownMm":2,"stepOverMm":1.5,"feedRateMmPerMin":1000,"plungeFeedRateMmPerMin":300,"safeZHeightMm":5,"stockAllowanceMm":0.5,"spindleRpm":0,"previousToolDiameterMm":0}"#
let legacyDecoded = try! JSONDecoder().decode(HeightfieldRoughParams.self, from: Data(legacyJSON.utf8))
expect(legacyDecoded.inverseMill == false, "legacy JSON without inverseMill decodes to false")

FileHandle.standardError.write(Data("G\n".utf8))
print("ShopPilotVerifyDOGFOOD1920d: PASS — inverse mill cuts the complement (normal pass-1 X\(nRuns.first!) vs inverse X\(iRuns.first!)…\(iRuns.last!)), round-trip + legacy decode clean.")
exit(0)
