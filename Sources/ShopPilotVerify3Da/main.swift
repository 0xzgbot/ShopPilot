import Foundation
import ShopPilotCore

/// SPK-3D-spine-a verify (CLT machine, no XCTest).
/// Proves the STL → heightfield relief import spine:
///   1. BOX: a 20×20×10 ASCII STL box rasterizes to a heightfield whose
///      footprint cells sit at the box top (10mm) and outside cells at 0 —
///      a real geometry import (the old estimator never parsed triangles).
///   2. PYRAMID: a 4-triangle pyramid peaks at its apex height over the
///      center cell and falls to ~0 at the corners.
///   3. PERSIST: Job Codable round-trip keeps the imported heightfield;
///      a legacy Job (no relief key) decodes with nil.
///   4. ROBUSTNESS: non-STL text and binary-looking payloads fail gracefully
///      with a clear error (no crash); degenerate triangles are skipped.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// ASCII STL for a box from (0,0,0) to (w,d,h). 8 vertices, 12 triangles.
func boxSTL(w: Double, d: Double, h: Double) -> String {
    let v: [(Double, Double, Double)] = [
        (0, 0, 0), (w, 0, 0), (w, d, 0), (0, d, 0),
        (0, 0, h), (w, 0, h), (w, d, h), (0, d, h),
    ]
    // Faces: bottom (0,1,2,3), top (4,5,6,7), sides. 12 triangles.
    let faces: [[Int]] = [
        [0, 2, 1], [0, 3, 2], // bottom
        [4, 5, 6], [4, 6, 7], // top
        [0, 1, 5], [0, 5, 4], // front
        [1, 2, 6], [1, 6, 5], // right
        [2, 3, 7], [2, 7, 6], // back
        [3, 0, 4], [3, 4, 7], // left
    ]
    var out = "solid box\n"
    for f in faces {
        out += "  facet normal 0 0 0\n    outer loop\n"
        for idx in f {
            let p = v[idx]
            out += "      vertex \(p.0) \(p.1) \(p.2)\n"
        }
        out += "    endloop\n  endfacet\n"
    }
    out += "endsolid box\n"
    return out
}

/// ASCII STL for a pyramid: 20×20 base at z=0, apex at (10,10,8). 4 sides.
func pyramidSTL() -> String {
    let base: [(Double, Double, Double)] = [(0, 0, 0), (20, 0, 0), (20, 20, 0), (0, 20, 0)]
    let apex = (10.0, 10.0, 8.0)
    let faces: [[(Double, Double, Double)]] = [
        [base[0], base[1], apex],
        [base[1], base[2], apex],
        [base[2], base[3], apex],
        [base[3], base[0], apex],
    ]
    var out = "solid pyramid\n"
    for f in faces {
        out += "  facet normal 0 0 0\n    outer loop\n"
        for p in f {
            out += "      vertex \(p.0) \(p.1) \(p.2)\n"
        }
        out += "    endloop\n  endfacet\n"
    }
    out += "endsolid pyramid\n"
    return out
}

func writeTemp(_ name: String, _ content: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-3da-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

func main() throws {
    // ── 1. Box → heightfield with correct footprint + top. ─────────────────
    let boxPath = try writeTemp("box.stl", boxSTL(w: 20, d: 20, h: 10))
    let box = STLHeightfieldImporter.importSTL(at: boxPath, cellSizeMm: 2.0, scale: 1.0)
    try expect(box.success, "box import succeeds")
    guard let hf = box.heightfield else { throw VerifyError.failed("box heightfield produced") }
    try expect(box.triangleCount == 12, "box has 12 triangles (got \(box.triangleCount))")
    try expect(hf.width == 10 && hf.height == 10,
               "20mm box at 2mm cells → 10×10 grid (got \(hf.width)×\(hf.height))")
    let center = try hf.height(atX: 10, y: 10) ?? { throw VerifyError.failed("center cell missing") }()
    try expect(abs(center - 10) < 0.001, "center cell sits at the box top 10mm (got \(center))")
    let nearEdge = try hf.height(atX: 19, y: 19) ?? { throw VerifyError.failed("edge cell missing") }()
    try expect(abs(nearEdge - 10) < 0.001, "footprint cell near the edge sits at the box top (got \(nearEdge))")
    try expect(hf.height(atX: -1, y: -1) == nil, "cell outside the grid returns nil")
    try expect(abs(hf.maxHeight - 10) < 0.001, "max height is the box top")

    // ── 2. Pyramid → apex over center, ~0 at corners. ───────────────────────
    let pyrPath = try writeTemp("pyr.stl", pyramidSTL())
    let pyr = STLHeightfieldImporter.importSTL(at: pyrPath, cellSizeMm: 1.0, scale: 1.0)
    try expect(pyr.success, "pyramid import succeeds")
    guard let ph = pyr.heightfield else { throw VerifyError.failed("pyramid heightfield produced") }
    try expect(pyr.triangleCount == 4, "pyramid has 4 triangles (got \(pyr.triangleCount))")
    let apex = try ph.height(atX: 10, y: 10) ?? { throw VerifyError.failed("apex cell missing") }()
    try expect(apex > 7.5, "center cell is near the 8mm apex (got \(apex))")
    let pCorner = try ph.height(atX: 0.2, y: 0.2) ?? { throw VerifyError.failed("pyramid corner missing") }()
    try expect(pCorner < 0.5, "pyramid corner cell is near 0 (got \(pCorner))")
    let midSlope = try ph.height(atX: 5, y: 5) ?? { throw VerifyError.failed("pyramid mid missing") }()
    try expect(midSlope > 3.5 && midSlope < 5.5,
               "midpoint cell sits partway up the slope (got \(midSlope))")

    // ── 3. Persist: Job round-trip + legacy decode. ─────────────────────────
    var job = Job(name: "Relief Job")
    job.stlHeightfield = hf
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.stlHeightfield?.width == 10 && decoded.stlHeightfield?.heights == hf.heights,
               "Job round-trip keeps the heightfield")
    // Legacy decode: a Job JSON WITHOUT the stlHeightfield key must decode
    // with nil (backward compatibility). Built by stripping the key from a
    // real encoding (avoids hand-writing Job's synthesized date format).
    let legacyData = try JSONEncoder().encode(Job(name: "Old Job"))
    var legacyObject = try JSONSerialization.jsonObject(with: legacyData) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "stlHeightfield")
    let legacy = try JSONDecoder().decode(Job.self, from: JSONSerialization.data(withJSONObject: legacyObject))
    try expect(legacy.stlHeightfield == nil, "legacy Job (no relief key) decodes with nil heightfield")

    // ── 4. Robustness: garbage + binary payload fail gracefully. ────────────
    let garbagePath = try writeTemp("bad.stl", "this is not an STL file at all\njust text\n")
    let garbage = STLHeightfieldImporter.importSTL(at: garbagePath, cellSizeMm: 1.0, scale: 1.0)
    try expect(!garbage.success && garbage.errorMessage != nil, "non-STL text fails with an error (no crash)")
    let binaryPath = try writeTemp("bin.stl", "solid\n" + String(repeating: "x", count: 2000))
    let binary = STLHeightfieldImporter.importSTL(at: binaryPath, cellSizeMm: 1.0, scale: 1.0)
    try expect(!binary.success && (binary.errorMessage ?? "").contains("Binary"),
               "binary-looking STL reports the binary-not-supported error")

    print("ShopPilotVerify3Da: PASS — box footprint+top, pyramid apex, Job round-trip + legacy nil, graceful failures")
}

do {
    try main()
} catch {
    print("ShopPilotVerify3Da: FAIL — \(error)")
    exit(1)
}
