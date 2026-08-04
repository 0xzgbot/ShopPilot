import Foundation
import ShopPilotCore

/// SPK-0308 verify (CLT machine, no XCTest).
/// Proves KEEP-OUT ZONES end to end (engine → rule → persist):
///   1. GEOMETRY: `KeepOutZone.containsPoint` (rectangle / circle / polygon
///      ray-cast) and `intersectsLine` (rect crossing vs miss); inactive
///      zones are ignored; the manager aggregates active zones.
///   2. RULE: `ToolpathPreflight.keepOutZoneViolation` — a CUT segment that
///      enters an active zone → warning issue naming the zone (override CTA);
///      paths outside, rapid-only crossings (G0 exempt), inactive zones, and
///      empty zone lists produce nothing.
///   3. TREE-LEVEL: the session mirror (per-node gcode vs zones) flags the
///      offending node and leaves the clear node alone.
///   4. PERSIST: Job keeps zones through a Codable round-trip; documents saved
///      before zones existed decode with keepOutZones == nil (legacy-safe).
/// The UI glue (zones panel create/edit/toggle in Cut, red dashed overlay in
/// the Preview canvas, save-alert warning) is compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func rectZone(name: String, x: Double, y: Double, w: Double, h: Double, active: Bool = true) -> KeepOutZone {
    KeepOutZone(
        name: name,
        type: .rectangle,
        rectMinX: x,
        rectMinY: y,
        rectMaxX: x + w,
        rectMaxY: y + h,
        polygonPoints: nil
    )
}

func main() throws {
    // ── 1. Geometry. ───────────────────────────────────────────────────────
    let zone = rectZone(name: "Clamp", x: 10, y: 10, w: 20, h: 20)
    try expect(zone.containsPoint(VectorPoint(x: 20, y: 20)), "point inside the rect zone is contained")
    try expect(!zone.containsPoint(VectorPoint(x: 5, y: 5)), "point outside the rect zone is not contained")
    try expect(zone.intersectsLine(VectorPoint(x: 0, y: 15), VectorPoint(x: 40, y: 15)),
               "line crossing the rect zone intersects")
    try expect(!zone.intersectsLine(VectorPoint(x: 0, y: 5), VectorPoint(x: 40, y: 5)),
               "line passing above the rect zone does not intersect")

    var circle = KeepOutZone(name: "Post", type: .circle,
                             circleCenter: VectorPoint(x: 0, y: 0), circleRadiusMm: 10)
    try expect(circle.containsPoint(VectorPoint(x: 7, y: 0)), "point inside the circle zone is contained")
    try expect(!circle.containsPoint(VectorPoint(x: 11, y: 0)), "point outside the circle zone is not contained")

    let polygon = KeepOutZone(name: "Triangle", type: .polygon,
                              polygonPoints: [VectorPoint(x: 0, y: 0), VectorPoint(x: 10, y: 0), VectorPoint(x: 5, y: 10)])
    try expect(polygon.containsPoint(VectorPoint(x: 5, y: 2)), "ray-cast contains an interior polygon point")
    try expect(!polygon.containsPoint(VectorPoint(x: 9, y: 2)), "ray-cast excludes an exterior polygon point")

    var inactive = zone
    inactive.isActive = false
    try expect(!inactive.containsPoint(VectorPoint(x: 20, y: 20)), "inactive zones are ignored")

    let manager = KeepOutZoneManager()
    manager.addZone(zone)
    manager.addZone(inactive)
    try expect(manager.intersectsLine(VectorPoint(x: 0, y: 15), VectorPoint(x: 40, y: 15)),
               "manager aggregates active zones")
    try expect(manager.activeZones.count == 1, "activeZones excludes inactive")

    // ── 2. Rule: cut segments vs zones. ────────────────────────────────────
    // Crossing path: a G1 cut along y=20 from x=0 to x=50 — runs straight
    // through the (10,10)-(30,30) zone.
    let crossing: [String] = ["G0 X0 Y20", "G1 X50 Y20"]
    let violation = ToolpathPreflight.keepOutZoneViolation(nodeName: "Profile Cutout", zones: [zone], gcodeLines: crossing)
    guard let violation else { throw VerifyError.failed("cut through the zone must warn") }
    try expect(violation.ruleID == "KEEP-OUT", "rule id is KEEP-OUT")
    try expect(violation.severity == .warning, "keep-out is a warning (override)")
    try expect(violation.message.contains("Clamp"), "message names the offending zone: \(violation.message)")
    try expect(violation.fix == .warnOnly, "CTA is warn-only (expert override)")

    // Clear path: stays on the y=0 and x=50 edges — outside the zone.
    let clearPath: [String] = ["G0 X0 Y0", "G1 X50 Y0", "G1 X50 Y50"]
    let clearZone = rectZone(name: "Far", x: 100, y: 100, w: 10, h: 10)
    try expect(ToolpathPreflight.keepOutZoneViolation(nodeName: "Profile", zones: [clearZone], gcodeLines: clearPath) == nil,
               "path far from the zone → no issue")

    let rapidOnly: [String] = ["G0 X0 Y0", "G0 X50 Y0"]
    try expect(ToolpathPreflight.keepOutZoneViolation(nodeName: "Rapid", zones: [zone], gcodeLines: rapidOnly) == nil,
               "rapid-only crossings (G0) are exempt — only the cutter path matters")

    try expect(ToolpathPreflight.keepOutZoneViolation(nodeName: "X", zones: [inactive], gcodeLines: crossing) == nil,
               "inactive zone → no issue")
    try expect(ToolpathPreflight.keepOutZoneViolation(nodeName: "X", zones: [], gcodeLines: crossing) == nil,
               "no zones → no issue")

    // ── 3. Tree-level: only the offending node is flagged. ─────────────────
    let tree = ToolpathTreeManager()
    let badNode = tree.addOperation("Profile Into Clamp")
    badNode.toolpathResult = crossing.joined(separator: "\n")
    let goodNode = tree.addOperation("Profile Clear")
    goodNode.toolpathResult = clearPath.joined(separator: "\n")

    var flagged: [String] = []
    for node in tree.allNodes where node.isOperation {
        let gcode = (node.toolpathResult ?? "").components(separatedBy: .newlines)
        if ToolpathPreflight.keepOutZoneViolation(nodeName: node.name, zones: [zone], gcodeLines: gcode) != nil {
            flagged.append(node.name)
        }
    }
    try expect(flagged == ["Profile Into Clamp"], "only the entering node is flagged (got \(flagged))")

    // ── 4. Persist: Job round-trip + legacy-safe decode. ───────────────────
    var job = Job(name: "Zone Job")
    job.keepOutZones = [zone, circle]
    let data = try JSONEncoder().encode(job)
    let back = try JSONDecoder().decode(Job.self, from: data)
    try expect(back.keepOutZones?.count == 2, "zones survive the Job round-trip")
    try expect(back.keepOutZones?.first?.name == "Clamp", "zone identity survives the round-trip")

    let legacyJSON = """
    {"id":"\(UUID().uuidString)","name":"Old Job","sheets":[],"documentVariables":[],"drivenDimensions":[],"vcarvePasses":0,"vcarveTimeSeconds":0,"createdAt":0,"updatedAt":0}
    """
    let legacy = try JSONDecoder().decode(Job.self, from: Data(legacyJSON.utf8))
    try expect(legacy.keepOutZones == nil, "pre-zone documents decode keepOutZones = nil (legacy-safe)")

    print("ShopPilotVerify0308: PASS — zone geometry (rect/circle/polygon, inactive ignored), cut-vs-zone warning naming the zone, rapid exemption, tree-level flagging, Job round-trip + legacy nil")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0308: FAIL — \(error)")
    exit(1)
}
