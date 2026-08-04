import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1101g verify (CLT machines, no XCTest).
/// Proves the DXF import spine the Import hub's DXF path and
/// `AppSession.importDXF(from:)` rely on:
///   1. A fixture ASCII DXF (LINE + closed LWPOLYLINE + CIRCLE + ARC +
///      unsupported TEXT) parses to exactly the supported shapes with the
///      right geometry; TEXT is skipped tolerantly, not fatal.
///   2. Arc angles convert from DXF degrees to radians (VectorShape.arc
///      semantics) — a 0°→90° arc becomes 0→π/2.
///   3. Closed LWPOLYLINE closes (first point re-appended).
///   4. Malformed entities collect errors without killing the import.
///   5. Imported shapes survive a .shoppilot-style Job round-trip
///      (layer-faithful, same as SVG imports).
/// The hub/UI glue (picker enablement, status copy) is covered by the build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func near(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    abs(a - b) < tolerance
}

let fixtureDXF = """
0
SECTION
2
HEADER
9
$ACADVER
1
AC1009
0
ENDSEC
0
SECTION
2
ENTITIES
0
LINE
8
0
10
0.0
20
0.0
11
100.0
21
50.0
0
LWPOLYLINE
8
0
90
4
70
1
10
0.0
20
0.0
10
40.0
20
0.0
10
40.0
20
40.0
10
0.0
20
40.0
0
CIRCLE
8
0
10
200.0
20
100.0
40
25.0
0
ARC
8
0
10
0.0
20
0.0
40
50.0
50
0.0
51
90.0
0
TEXT
8
0
10
5.0
20
5.0
40
2.5
1
Hello
0
ENDSEC
0
EOF
"""

func main() throws {
    // ── 1. Supported entities parse with correct geometry; TEXT skipped. ─────
    let result = DXFParser.parse(fixtureDXF)
    try expect(result.shapes.count == 4, "4 supported entities parse (TEXT skipped)")
    try expect(result.success, "no fatal errors")

    guard case .line(let start, let end) = result.shapes[0] else {
        throw VerifyError.failed("shape 0 should be a LINE")
    }
    try expect(near(start.x, 0) && near(start.y, 0) && near(end.x, 100) && near(end.y, 50),
               "LINE geometry from 10/20/11/21")

    guard case .freehand(let points) = result.shapes[1] else {
        throw VerifyError.failed("shape 1 should be a freehand LWPOLYLINE")
    }
    try expect(points.count == 5, "closed LWPOLYLINE re-appends the first point")
    try expect(points.first == points.last, "LWPOLYLINE is closed (70 flag)")

    guard case .circle(let center, let radius) = result.shapes[2] else {
        throw VerifyError.failed("shape 2 should be a CIRCLE")
    }
    try expect(near(center.x, 200) && near(center.y, 100) && near(radius, 25),
               "CIRCLE center/radius from 10/20/40")

    // ── 2. ARC angles convert degrees → radians. ─────────────────────────────
    guard case .arc(let arcCenter, let arcRadius, let startAngle, let endAngle) = result.shapes[3] else {
        throw VerifyError.failed("shape 3 should be an ARC")
    }
    try expect(near(arcCenter.x, 0) && near(arcCenter.y, 0), "arc center from 10/20")
    try expect(near(startAngle, 0.0), "arc start 0° → 0 rad")
    try expect(near(endAngle, .pi / 2), "arc end 90° → π/2 rad")
    try expect(near(arcRadius, 50), "arc radius from 40")

    // ── 4. Malformed entities collect errors without killing the import. ────
    let malformed = DXFParser.parse("""
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    8
    0
    10
    1.0
    0
    CIRCLE
    8
    0
    10
    1.0
    20
    2.0
    40
    5.0
    0
    ENDSEC
    0
    EOF
    """)
    try expect(!malformed.errors.isEmpty, "malformed LINE (no 11/21) records an error")
    try expect(malformed.shapes.count == 1, "the well-formed CIRCLE still imports")

    // ── 5. Imported shapes survive a Job round-trip (layer-faithful). ────────
    let layer = Layer(name: "DXF Import")
    let paths = GeometryBridge.toCorePaths(
        result.shapes,
        layerIDs: Array(repeating: layer.id, count: result.shapes.count)
    )
    try expect(paths.count == 4, "shapes → layer vectors")
    var layers = [layer]
    LayerVisibility.distribute(paths, into: &layers)
    try expect(layers[0].vectors.count == 4, "all imported vectors land on the layer")
    var job = Job(name: "DXF round-trip")
    _ = job.ensureSingleSheet()
    job.sheets[0].layers = layers
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    let restored = decoded.sheets[0].layers.flatMap { $0.vectors }
    try expect(restored.count == 4, "Job round-trip keeps all 4 imported vectors")

    print("ShopPilotVerify1101g: PASS — LINE/LWPOLYLINE/CIRCLE/ARC parse + degrees→radians + closed polyline + tolerant errors + round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1101g: FAIL — \(error)")
    exit(1)
}
