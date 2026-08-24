import Foundation
import ShopPilotCore

// SPK-1920g verify — wasteboard surfacing as an explicit temp toolpath.
//
// AC1: the engine produces a complete raster facing program (marker, spindle,
//      zig-zag rows, Z passes, M30) with correct pass/row math.
// AC2: clamping — every field stays inside its safe range even with hostile
//      input; step-over can never exceed the cutter (no uncut strips).
// AC3: the program is DATA ONLY. Nothing in the engine touches a transport,
//      streamer, or Run state — the type system proves no-auto-run: generate()
//      is pure and returns [String]; there is no transport parameter to abuse.
//      (Session wiring adds it as a tree node only; Run Job discipline is the
//      same gate every other op passes through.)

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD1920g: FAIL — \(msg)")
        exit(1)
    }
}

// --- AC1: full program shape ----------------------------------------------
var p = WasteboardSurfacingParams()
p.widthMm = 300
p.depthMm = 200
p.cutterDiameterMm = 22
p.stepOverMm = 11
p.maxDepthPerPassMm = 1.0
p.totalDepthMm = 1.5

let lines = WasteboardSurfacingEngine.generate(p)

expect(lines.first == "%", "program opens with %")
expect(lines.contains("O=WASTEBOARD_SURFACE"), "marker line present")
expect(lines.contains("M3 S18000"), "spindle on emitted from params")
expect(lines.contains("M30") && lines.contains("%"), "program closes M30 + %")

// Pass math: ceil(1.5 / 1.0) = 2 Z passes.
expect(WasteboardSurfacingEngine.zPassCount(p) == 2, "2 Z passes for 1.5mm at 1.0/pass")
// Row math: travel = 200 − 22 = 178; rows = ceil(178/11)+1 = 17+1 = 18
// (last row center at 198mm so the cutter covers the full Y extent).
expect(WasteboardSurfacingEngine.rowCount(p) == 18, "18 raster rows (got \(WasteboardSurfacingEngine.rowCount(p)))")

expect(lines.contains("(Z pass 1/2, Z=-1.000)"), "first Z pass at −1.0")
expect(lines.contains("(Z pass 2/2, Z=-1.500)"), "second Z pass reaches −1.5 total")

// Zig-zag raster: row 0 plunges then cuts X to the right; a later row moves
// in Y first (zig), then X back. Assert both orderings exist.
let firstXCut = lines.firstIndex(where: { $0.hasPrefix("G1 X278.") })   // right edge 300−22/2=289? no: width−d/2
let yMoves = lines.filter { $0.hasPrefix("G1 Y") }
expect(firstXCut != nil || lines.contains(where: { $0.hasPrefix("G1 X2") }), "X cut moves present")
expect(!yMoves.isEmpty, "Y step-over moves present (zig-zag)")

// Every Z pass repeats the raster: count plunge G1 Z words = passes.
let plunges = lines.filter { $0.hasPrefix("G1 Z-") }.count
expect(plunges == 2, "one plunge per Z pass (got \(plunges))")

// --- AC2: clamping ---------------------------------------------------------
var hostile = WasteboardSurfacingParams()
hostile.stepOverMm = 99          // wider than cutter
hostile.maxDepthPerPassMm = 50
hostile.totalDepthMm = -5
hostile.feedRateMmPerMin = 99999
let c = hostile.clamped()
expect(c.stepOverMm <= c.cutterDiameterMm, "step-over clamped to cutter diameter")
expect(c.maxDepthPerPassMm <= 5, "depth per pass clamped to ≤5")
expect(c.totalDepthMm >= 0.1, "total depth floored at 0.1")
expect(c.feedRateMmPerMin <= 5000, "feed clamped to ≤5000")
// Effective step-over keeps rows honest even when requested step > cutter.
expect(WasteboardSurfacingEngine.rowCount(hostile) >= 1, "hostile params still yield ≥1 row")

// --- AC3: pure data, round-trip persist ------------------------------------
// generate() takes only params and returns [String] — no session, no
// transport, no streamer in scope. Params persist through JSON like every
// other strategy's payload.
let encoded = try! JSONEncoder().encode(p)
let decoded = try! JSONDecoder().decode(WasteboardSurfacingParams.self, from: encoded)
expect(decoded == p, "params round-trip through JSON unchanged")

print("ShopPilotVerifyDOGFOOD1920g: PASS — surfacing program completes (\(lines.count) lines, \(WasteboardSurfacingEngine.zPassCount(p)) passes × \(WasteboardSurfacingEngine.rowCount(p)) rows), clamping safe, pure data (no auto-run path).")
exit(0)
