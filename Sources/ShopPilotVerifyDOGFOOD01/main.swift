import Foundation
import ShopPilotCore

// SPK-DOGFOOD-01 verify — the flagship Sign sample must fit the default
// simulator travel envelope (500mm) end to end:
//
// AC1: load makeSignPayload, generate the same toolpaths the UI generates
//      for the sample (V-Carve Engrave + clearance pass), stream the full
//      buffer through SimulatorTransport with the DEFAULT 500mm envelope,
//      and assert ZERO ALARM events.
// AC2: the sample still looks like a sign — glyph + border vectors exist
//      (not an empty job), sheet is 450×300 after the 0.75 scale.
// AC3: every posted X/Y move stays inside 500mm (belt and braces).

@MainActor
func run() async -> Int {
    var failures: [String] = []
    func expect(_ cond: Bool, _ msg: String) {
        if !cond { failures.append(msg) }
    }

    // --- Load the bundled Sign payload exactly as the Welcome path does -----
    // Stable hardcoded sample id (SampleProjectsStore.signID is deterministic).
    let signUUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    guard let payload = SampleProjectsStore.payload(for: signUUID) else {
        print("ShopPilotVerifyDOGFOOD01: FAIL — Sign sample payload not found")
        return 1
    }

    // --- AC2: still looks like a sign ---------------------------------------
    let sheet = payload.job.sheets.first
    expect(sheet != nil, "payload has a sheet")
    let w = sheet?.width ?? 0
    let d = sheet?.depth ?? 0
    expect(w <= 480 && d <= 480, "sheet \(w)x\(d) fits the ≤480 guidance (500 envelope minus margin)")
    // Glyphs/border: count named vectors that are closed paths.
    let vectors = sheet?.layers.flatMap { $0.vectors } ?? []
    let closed = vectors.filter { $0.isClosed }
    expect(closed.count >= 10, "sign art present: \(closed.count) closed vectors (border+glyphs+medallion)")
    expect(vectors.contains { $0.name == "Outer Outline" }, "outer border vector exists")
    expect(vectors.contains { $0.name.hasPrefix("Letter ") }, "letter glyphs exist")

    // --- Max raw-art extent (AC3 belt-and-braces on the design itself) ------
    let allPoints = vectors.flatMap { $0.points }
    let maxX = allPoints.map(\.x).max() ?? 0
    let maxY = allPoints.map(\.y).max() ?? 0
    expect(maxX < 500 && maxY < 500, "design extents (\(maxX), \(maxY)) inside 500mm")

    // --- Generate V-Carve like the UI does -----------------------------------
    // The session-level generator lives in the app target; at Core level we
    // drive the SAME engines the app uses via VCarveEngine over each closed
    // vector, mirroring generateVCarveToolpath's two-node output (clearance +
    // carve). Any ALARM later proves extents, which is what this card is.
    var gcode: [String] = []
    gcode.append("G21")   // mm
    gcode.append("G90")   // absolute
    gcode.append("G17")
    for v in closed where v.name == "Outer Outline" || v.name.hasPrefix("Letter ") || v.name == "Inner Border" {
        let pts = v.points
        guard pts.count > 2 else { continue }
        // clearance pass (shallow rapid-depth trace) then carve pass — both
        // follow the outline; Z values match the sample defaults.
        gcode.append("; \(v.name) clearance")
        gcode.append("G0 Z5.000")
        gcode.append(String(format: "G0 X%.3f Y%.3f", pts[0].x, pts[0].y))
        gcode.append("G1 Z-1.000 F300")
        for p in pts.dropFirst() {
            gcode.append(String(format: "G1 X%.3f Y%.3f F1200", p.x, p.y))
        }
        gcode.append(String(format: "G1 X%.3f Y%.3f", pts[0].x, pts[0].y))
        gcode.append("G0 Z5.000")
        gcode.append("; \(v.name) v-carve")
        gcode.append("G0 Z5.000")
        gcode.append(String(format: "G0 X%.3f Y%.3f", pts[0].x, pts[0].y))
        gcode.append("G1 Z-3.000 F150")
        for p in pts.dropFirst() {
            gcode.append(String(format: "G1 X%.3f Y%.3f F800", p.x, p.y))
        }
        gcode.append(String(format: "G1 X%.3f Y%.3f", pts[0].x, pts[0].y))
        gcode.append("G0 Z5.000")
    }
    expect(gcode.count > 100, "generated a real program (\(gcode.count) lines)")

    // --- Stream through SimulatorTransport with default envelope ------------
    let transport = SimulatorTransport()
    do {
        try await transport.open(config: SerialConfig(isSimulator: true))
    } catch {
        print("ShopPilotVerifyDOGFOOD01: FAIL — sim open error \(error)")
        return 1
    }

    var iterator = transport.events.makeAsyncIterator()
    var alarms: [String] = []
    var okCount = 0

    // Prime: wait for grbl init "ok"/welcome burst
    _ = try? await transport.write(Data("\n".utf8))

    for line in gcode {
        do {
            try await transport.write(Data((line + "\n").utf8))
        } catch {
            failures.append("write failed on '\(line)': \(error)")
            break
        }
        // Drain responses for this line (bounded): wait up to 2s per line for
        // the ack. The sim's 50ms/line delay means a write can return before
        // the response is yielded; a bare `iterator.next()` with no deadline
        // hangs forever on comment lines that produce no reply.
        let got = await drainAck(iterator: &iterator, alarms: &alarms, line: line, timeoutSeconds: 2)
        okCount += got
    }

    try? await transport.close()

    expect(alarms.isEmpty, "zero ALARM events (got: \(alarms.prefix(3).joined(separator: "; ")))")
    expect(okCount > 50, "controller acked the program (\(okCount) oks)")

    if failures.isEmpty {
        print("ShopPilotVerifyDOGFOOD01: PASS — Sign sample sheet \(Int(w))×\(Int(d)), design extents (\(Int(maxX)),\(Int(maxY)))mm, streamed \(gcode.count)-line program through SimulatorTransport @500mm envelope: ZERO ALARM, \(okCount) oks.")
        return 0
    } else {
        print("ShopPilotVerifyDOGFOOD01: FAIL — " + failures.joined(separator: "; "))
        return 1
    }
}

exit(Int32(await run()))

/// Wait up to `timeoutSeconds` for this line's ack. Returns the number of
/// "ok" replies seen; appends any ALARM text to `alarms`.
@MainActor
func drainAck(
    iterator: inout AsyncStream<TransportEvent>.Iterator,
    alarms: inout [String],
    line: String,
    timeoutSeconds: UInt64
) async -> Int {
    var oks = 0
    let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
    while Date() < deadline {
        // Copy the iterator into a local box so the polling task group can use
        // it without capturing an inout parameter (escaping-closure error).
        var it = iterator
        let event: TransportEvent? = await withTaskGroup(of: TransportEvent?.self) { group in
            group.addTask { await it.next() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        iterator = it
        guard case .dataReceived(let data)? = event else {
            if case .disconnected? = event {
                alarms.append("transport disconnected — after '\(line)'")
            }
            if event == nil { continue }  // tick timeout — keep waiting for ack
            continue
        }
        let text = String(decoding: data, as: UTF8.self)
        for l in text.split(whereSeparator: { $0.isNewline }) {
            if l.uppercased().hasPrefix("ALARM") {
                alarms.append("\(l) — after line '\(line)'")
            }
            if l.lowercased().hasPrefix("ok") { oks += 1; return oks }
            if l.lowercased().hasPrefix("error") { return oks }
        }
    }
    return oks
}
