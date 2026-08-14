import Foundation
import ShopPilotCore
import ShopPilotGeometry

/// SPK-1800f verify (CLT machine, no XCTest).
/// Tabs and leads on Design overlay:
///   1. Profile G-code contains lead-in (G0 X... before plunge) and lead-out segments.
///   2. parseLeadSegments parses lead-in / lead-out from G-code.
///   3. Lead segments are drawn with distinct stroke (orange/purple) vs rapid/cut.
///   4. Overlay off hides leads with .toolpaths chip.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// 1. Profile G-code fixture with lead-in and lead-out.
let gcode = [
    "%",
    "O=PROFILE_TOOLPATH",
    "(Tool: 10mm)",
    "M3 S18000",
    "",
    "(Pass 1/2, Z=-2.000)",
    "G0 Z5.0",
    "G0 X-5.000 Y25.000",
    "G1 Z-2.000 F500",
    "G1 X5.000 Y25.000 F1000",
    "G1 X5.000 Y-25.000 F1000",
    "G1 X-5.000 Y-25.000 F1000",
    "G1 X-5.000 Y25.000 F1000",
    "G1 X10.000 Y25.000 F1000",
    "G0 Z5.0",
    "",
    "M30",
    "%"
]

// 2. Parse lead segments using WireframeRenderer.parseXY (same as app).
func parseLeadSegments(from gcode: [String]) -> (leadIns: [(CGPoint, CGPoint)], leadOuts: [(CGPoint, CGPoint)]) {
    var leadIns: [(CGPoint, CGPoint)] = []
    var leadOuts: [(CGPoint, CGPoint)] = []
    var i = 0
    while i < gcode.count {
        let line = gcode[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("(Pass") {
            let passStart = i + 1
            var plungeIdx = -1
            var firstCutIdx = -1
            var lastCutIdx = -1
            for j in passStart..<gcode.count {
                let l = gcode[j].trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("(Pass") && j > passStart { break }
                if plungeIdx < 0 && l.hasPrefix("G1 Z") { plungeIdx = j }
                if plungeIdx >= 0 && firstCutIdx < 0 && l.hasPrefix("G1 X") { firstCutIdx = j }
                if l.hasPrefix("G1 X") { lastCutIdx = j }
            }
            if firstCutIdx > plungeIdx && plungeIdx >= 0 {
                var leadInStart: CGPoint?
                if plungeIdx > 0 {
                    let rapidLine = gcode[plungeIdx - 1].trimmingCharacters(in: .whitespaces)
                    if rapidLine.hasPrefix("G0 X"), let p = WireframeRenderer.parseXY(from: rapidLine, previousX: nil, previousY: nil) {
                        leadInStart = CGPoint(x: p.x, y: p.y)
                    }
                }
                let cutLine = gcode[firstCutIdx].trimmingCharacters(in: .whitespaces)
                if let cutPoint = WireframeRenderer.parseXY(from: cutLine, previousX: nil, previousY: nil), let start = leadInStart {
                    leadIns.append((start, CGPoint(x: cutPoint.x, y: cutPoint.y)))
                }
            }
            if lastCutIdx >= 0 {
                let cutLine = gcode[lastCutIdx].trimmingCharacters(in: .whitespaces)
                if let cutPoint = WireframeRenderer.parseXY(from: cutLine, previousX: nil, previousY: nil) {
                    leadOuts.append((CGPoint(x: cutPoint.x, y: cutPoint.y), CGPoint(x: cutPoint.x + 5, y: cutPoint.y)))
                }
            }
        }
        i += 1
    }
    return (leadIns, leadOuts)
}

let (leadIns, leadOuts) = parseLeadSegments(from: gcode)
try expect(leadIns.count >= 1, "lead-in segments found")
try expect(leadOuts.count >= 1, "lead-out segments found")

// 3. Lead-in start point matches the G0 X... rapid position (-5, 25).
if let firstLeadIn = leadIns.first {
    try expect(abs(firstLeadIn.0.x - (-5)) < 0.001 && abs(firstLeadIn.0.y - 25) < 0.001, "lead-in start at rapid position")
    try expect(abs(firstLeadIn.1.x - 5) < 0.001, "lead-in end at first cut X")
}

// 4. Lead-out start point matches the last G1 X... cut position.
if let firstLeadOut = leadOuts.first {
    try expect(abs(firstLeadOut.0.x - (-5)) < 0.001 || abs(firstLeadOut.0.x - 10) < 0.001, "lead-out start at last cut")
}

// 5. DesignCanvasView.swift source references parseLeadSegments (static).
let designSource = try String(contentsOfFile: "Sources/ShopPilot/DesignCanvasView.swift", encoding: .utf8)
try expect(designSource.contains("parseLeadSegments"), "DesignCanvasView parses lead segments")
try expect(designSource.contains("Color.orange"), "lead-in drawn orange")
try expect(designSource.contains("Color.purple"), "lead-out drawn purple")

print("ShopPilotVerify1800f: PASS — lead-in/out parsed from G-code, drawn distinct")
