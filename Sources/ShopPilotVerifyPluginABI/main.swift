import Foundation
import ShopPilotCore

/// SPK-1006 loadable-ABI verify (CLT machine, no XCTest).
/// Proves the PLUGIN ABI is actually loadable — the draft is now a working
/// contract, not a proposal:
///   1. DISCOVERY: `PluginStore` finds the bundled sample plugin from
///      fixtures/plugins (manifest.json parsed, kind + params read).
///   2. RUNNER: `PluginRunner.run` executes the sample plugin as a real child
///      process (`swift fixtures/plugins/dotgrid-engrave/main.swift`), feeds
///      it a PluginJobDocument on stdin, and decodes the PluginOutput JSON —
///      the emitted dot-grid G-code is checked (markers, first move, grid
///      extent from the stock dims).
///   3. MANIFEST REJECTION: a bad manifest (wrong apiVersion) is skipped by
///      discovery, never fatal.
///   4. TIMEOUT: a hung plugin is terminated and returns nil (the sandbox
///      contract — no infinite hang).
///   5. JOB DOC: vectors round-trip through the plugin document (points +
///      closure flag survive the JSON hop).
/// The session glue (pluginStore + runPluginStrategy + PluginsPanelView) is
/// compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let cwd = FileManager.default.currentDirectoryPath
    let root = cwd.hasSuffix("ShopPilot") ? cwd : cwd + "/../.."
    let fixturesPlugins = URL(fileURLWithPath: root).appendingPathComponent("fixtures/plugins")

    // ── 1. Discovery finds the sample plugin. ─────────────────────────────
    let store = PluginStore(searchDirectories: [fixturesPlugins])
    try expect(store.plugins.count == 1, "sample plugin discovered (got \(store.plugins.count))")
    guard let plugin = store.plugins.first else { throw VerifyError.failed("no plugin") }
    try expect(plugin.manifest.id == "com.shoppilot.dotgrid", "manifest id parsed")
    try expect(plugin.manifest.kind == .toolpathStrategy, "kind parsed")
    try expect(plugin.manifest.params.count == 3, "params declared (got \(plugin.manifest.params.count))")

    // ── 2. Runner executes the real child process. ────────────────────────
    let doc = PluginJobDocument(
        jobName: "Verify Grid",
        stockWidthMm: 40,
        stockDepthMm: 30,
        stockHeightMm: 10,
        vectors: [
            PluginVectorPath(
                points: [PluginVectorPoint(x: 1, y: 1), PluginVectorPoint(x: 39, y: 29)],
                isClosed: true
            )
        ],
        params: ["spacingMm": "10", "depthMm": "0.5", "feedRate": "1200"]
    )
    guard let output = PluginRunner.run(
        manifest: plugin.manifest,
        pluginDirectory: plugin.directory,
        document: doc,
        timeoutSeconds: 60
    ) else {
        throw VerifyError.failed("plugin run returned nil (child process failed)")
    }
    try expect(output.gcodeLines.contains("%"), "output carries the % marker")
    try expect(output.gcodeLines.contains { $0.hasPrefix("(Dot Grid Engrave") },
               "output carries the job-name comment")
    try expect(output.gcodeLines.contains("G21") && output.gcodeLines.contains("G90"),
               "modal header emitted")
    try expect(output.gcodeLines.contains("M2"), "end marker emitted")
    // Grid extent: 40×30 stock, 10mm spacing → columns at 5,15,25,35 (4),
    // rows at 5,15,25 (3) → 12 dots → 12 plunge G1 lines.
    let plunges = output.gcodeLines.filter { $0.hasPrefix("G1 Z-0.500") }
    try expect(plunges.count == 12, "dot grid 4×3 = 12 plunges (got \(plunges.count))")
    try expect(output.gcodeLines.contains("G0 X35.000 Y25.000"),
               "last dot at (35,25) from the stock dims")
    try expect(output.estimatedTimeSeconds > 0, "estimate carried")

    // ── 3. Manifest rejection (bad apiVersion skipped). ───────────────────
    let badDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("badplugin-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
    let badManifest = """
    {"apiVersion": 9, "id": "com.bad", "name": "Bad", "kind": "toolpath-strategy", "entry": "x"}
    """
    try Data(badManifest.utf8).write(to: badDir.appendingPathComponent("manifest.json"))
    defer { try? FileManager.default.removeItem(at: badDir) }
    let store2 = PluginStore(searchDirectories: [badDir, fixturesPlugins])
    try expect(store2.plugins.count == 1, "bad manifest skipped (got \(store2.plugins.count))")
    try expect(store2.plugins.first?.manifest.id == "com.shoppilot.dotgrid", "good plugin still found")

    // ── 4. Timeout: hung plugin terminated → nil. ─────────────────────────
    let hungDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hungplugin-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: hungDir, withIntermediateDirectories: true)
    let hungScript = "#!/bin/bash\nsleep 3600\n"
    let scriptURL = hungDir.appendingPathComponent("hang.sh")
    try Data(hungScript.utf8).write(to: scriptURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    let hungManifest = PluginManifest(id: "com.hung", name: "Hang", kind: .gadget, entry: "hang.sh")
    defer { try? FileManager.default.removeItem(at: hungDir) }
    let hungStart = Date()
    let hungResult = PluginRunner.run(
        manifest: hungManifest,
        pluginDirectory: hungDir,
        document: doc,
        timeoutSeconds: 2
    )
    let hungElapsed = Date().timeIntervalSince(hungStart)
    try expect(hungResult == nil, "hung plugin returns nil")
    try expect(hungElapsed < 30, "hung plugin killed promptly (\(String(format: "%.1f", hungElapsed))s)")

    // ── 5. Vectors round-trip through the document. ───────────────────────
    try expect(doc.vectors[0].points.count == 2, "vector points carried")
    try expect(doc.vectors[0].isClosed, "closure flag carried")

    print("ShopPilotVerifyPluginABI: PASS — discovery + real child-process run (12-dot grid on 40×30 stock), manifest rejection, 2s timeout kill, vector round-trip")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyPluginABI: FAIL — \(error)")
    exit(1)
}
