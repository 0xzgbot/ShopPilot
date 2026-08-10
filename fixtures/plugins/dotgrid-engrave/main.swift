#!/usr/bin/env swift
// Dot Grid Engrave — sample ShopPilot plugin (SPK-1006 loadable ABI).
// Contract: reads a PluginJobDocument JSON from stdin, writes a PluginOutput
// JSON to stdout ({ gcodeLines, estimatedTimeSeconds, params }).
// Emits a peck-dot grid across the stock: G0 rapids, G1 plunge to depth,
// G0 retract — a deterministic, machine-checkable engrave strategy.

import Foundation

struct PluginVectorPoint: Codable { var x: Double; var y: Double }
struct PluginVectorPath: Codable { var points: [PluginVectorPoint]; var isClosed: Bool }
struct PluginJobDocument: Codable {
    var jobName: String
    var stockWidthMm: Double
    var stockDepthMm: Double
    var stockHeightMm: Double
    var vectors: [PluginVectorPath]
    var params: [String: String]
}
struct PluginOutput: Codable {
    var gcodeLines: [String]
    var estimatedTimeSeconds: Double
    var params: [String: String]
}

let docData = FileHandle.standardInput.readDataToEndOfFile()

guard let doc = try? JSONDecoder().decode(PluginJobDocument.self, from: docData) else {
    FileHandle.standardError.write(Data("dotgrid: bad input document\n".utf8))
    exit(2)
}

let spacing = Double(doc.params["spacingMm"] ?? "10") ?? 10
let depth = Double(doc.params["depthMm"] ?? "0.5") ?? 0.5
let feed = Double(doc.params["feedRate"] ?? "1200") ?? 1200
let safeZ = 2.0

var gcode: [String] = []
gcode.append("%")
gcode.append("(Dot Grid Engrave — \(doc.jobName))")
gcode.append("G21")
gcode.append("G90")
gcode.append("G0 Z\(safeZ)")

var x = spacing / 2
var y = spacing / 2
while y <= doc.stockDepthMm {
    while x <= doc.stockWidthMm {
        gcode.append("G0 X\(String(format: "%.3f", x)) Y\(String(format: "%.3f", y))")
        gcode.append("G1 Z-\(String(format: "%.3f", depth)) F\(Int(feed))")
        gcode.append("G0 Z\(safeZ)")
        x += spacing
    }
    x = spacing / 2
    y += spacing
}

gcode.append("M2")

let output = PluginOutput(
    gcodeLines: gcode,
    estimatedTimeSeconds: Double(gcode.count) * 0.35,
    params: ["spacingMm": String(spacing), "depthMm": String(depth)]
)

let outData = try JSONEncoder().encode(output)
FileHandle.standardOutput.write(outData)
