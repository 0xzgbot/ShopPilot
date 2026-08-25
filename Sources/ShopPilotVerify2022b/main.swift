import Foundation
import ShopPilotCore

// SPK-2022b verify — Tool-length offset: Z-only re-probe after a tool change
// (M6), committing G10 L20 P1 Z[t], on SimulatorTransport.
//
// AC1: the emitted TLS plan contains the M6 change, exactly one Z probe
//      (G38.2 Z-… F…), exactly one commit (G10 L20 P1 Z<t>), and ZERO lines
//      carrying an X or Y word — XY is provably untouched in the emission.
// AC2: the full sequence completes through SimulatorTransport — every line
//      acked "ok".
// AC3: XY work position is identical before/after the cycle as read back from
//      transport state (? status WPos), even from a non-origin start; the
//      written-bytes log confirms no X/Y coordinate was ever sent by the plan.
// AC4: disconnected invocation emits nothing and changes no state (1920f
//      precedent); controller-level no-op guard is compile-checked by the app
//      build.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2022b: FAIL — \(msg)")
        exit(1)
    }
}

func containsLine(_ data: Data, _ needle: String) -> Bool {
    String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(needle) }
}

/// Pull the WPos triple out of a GRBL status report string.
func wpos(_ status: String) -> (x: Double, y: Double, z: Double)? {
    guard let range = status.range(of: "WPos:") else { return nil }
    let rest = status[range.upperBound...]
    guard let end = rest.firstIndex(of: "|") else { return nil }
    let parts = rest[..<end].split(separator: ",")
    guard parts.count == 3,
          let x = Double(parts[0]), let y = Double(parts[1]), let z = Double(parts[2])
    else { return nil }
    return (x, y, z)
}

@MainActor
func run() async {
    // --- Planner-level contract first (pure, no I/O) ------------------------
    let plan = TouchOff.planToolLengthOffset(toolNumber: 1, plateThickness: 3.0)
    let sequence = TouchOff.toolLengthOffsetSequence(plan)

    // AC1a: shape of the emission.
    expect(sequence.contains("M6 T1"), "plan sends the tool change M6 T1; got \(sequence)")
    expect(sequence.contains("G90"), "plan pins absolute mode G90")
    expect(sequence.contains("G10 L20 P1 Z3"), "commit is G10 L20 P1 Z3 (plate thickness); got \(sequence)")
    let probes = sequence.filter { $0.hasPrefix("G38.2 ") }
    expect(probes.count == 1, "exactly one probe line (got \(probes))")
    expect(probes.first?.hasPrefix("G38.2 Z-") == true, "the single probe is a Z-only probe")
    expect(probes.first?.contains("F120") == true, "probe carries the feed word F\(TouchOff.plan(plateThickness: 3.0).probeSpeed)")

    // AC1b: ZERO X/Y words anywhere in the emission — planner + helper agree.
    let xyLines = sequence.filter { $0.range(of: "[XY]", options: .regularExpression) != nil }
    expect(xyLines.isEmpty, "no line may contain an X or Y word (offenders: \(xyLines))")
    expect(TouchOff.isZOnly(sequence), "TouchOff.isZOnly agrees the emission is Z-only")

    // Commit math matches the shared zCommitOffset / zOffset chain.
    expect(TouchOff.zCommitOffset(plateThickness: 3.0) == TouchOff.zOffset(probeHitZ: 0, plateThickness: 3.0),
           "TLS Z commit uses the same plate math as the touch-off flow")

    // Custom inputs flow through clamping + formatting.
    let custom = TouchOff.planToolLengthOffset(toolNumber: 3, plateThickness: 6.5)
    let customSequence = TouchOff.toolLengthOffsetSequence(custom)
    expect(customSequence.contains("M6 T3"), "custom tool number reaches the M6 line")
    expect(customSequence.contains("G10 L20 P1 Z6.5"), "custom plate thickness reaches the commit (Z6.5)")

    // --- AC4 first: disconnected invocation emits nothing -------------------
    let coldSim = SimulatorTransport()
    var disconnectedRefused = false
    do {
        try await coldSim.write(Data(GCodeLine.sending("G38.2 Z-10 F120").utf8))
    } catch MachineTransportError.disconnected {
        disconnectedRefused = true
    } catch {
        disconnectedRefused = false
    }
    expect(disconnectedRefused, "disconnected write throws .disconnected (no silent ok)")
    var readRefused = false
    do {
        _ = try await coldSim.read()
    } catch MachineTransportError.disconnected {
        readRefused = true
    } catch {
        readRefused = false
    }
    expect(readRefused, "disconnected read refuses — nothing was emitted, state unchanged")

    // --- AC2/AC3: connect, park at a NON-origin XY, run the full TLS cycle --
    let sim = SimulatorTransport()
    do {
        try await sim.open(config: SerialConfig(baudRate: 115200, isSimulator: true,
                                                simulationDelayNanoseconds: 0))
    } catch {
        expect(false, "sim open failed: \(error)")
    }

    // Move to a non-origin XY so "XY unchanged" actually means something.
    do {
        try await sim.write(Data(GCodeLine.sending("G0 X120 Y45 Z8").utf8))
        let ack = try await sim.read()
        expect(String(decoding: ack, as: UTF8.self).contains("ok"), "park move acked ok")
    } catch {
        expect(false, "park move threw \(error)")
    }
    var before: (x: Double, y: Double, z: Double)?
    do {
        try await sim.write(Data(GCodeLine.sending("?").utf8))
        before = wpos(String(decoding: try await sim.read(), as: UTF8.self))
    } catch {
        expect(false, "pre-cycle status threw \(error)")
    }
    expect(before != nil && before!.x == 120 && before!.y == 45, "pre-cycle WPos reads X120 Y45 (got \(String(describing: before)))")

    // Run the whole TLS plan; every line must ack ok (AC2).
    for line in sequence {
        do {
            try await sim.write(Data(GCodeLine.sending(line).utf8))
            let ack = try await sim.read()
            expect(String(decoding: ack, as: UTF8.self).contains("ok"),
                   "'\(line)' acked ok (got '\(String(decoding: ack, as: UTF8.self))')")
        } catch {
            expect(false, "'\(line)' threw \(error) — cycle did not complete")
        }
    }

    // AC3: XY work offsets identical before/after, straight from transport
    // state; Z ends at the safe retract height.
    var after: (x: Double, y: Double, z: Double)?
    do {
        try await sim.write(Data(GCodeLine.sending("?").utf8))
        after = wpos(String(decoding: try await sim.read(), as: UTF8.self))
    } catch {
        expect(false, "post-cycle status threw \(error)")
    }
    expect(after != nil, "post-cycle status parsed")
    expect(after!.x == before!.x && after!.y == before!.y,
           "XY unchanged across the TLS cycle (before \(before!), after \(after!))")
    expect(after!.z == 5.0, "Z ended at the retract height 5 (got \(after!.z))")

    // Race-free log check: the plan's own bytes carry the commit and still
    // zero X/Y coordinate words beyond the operator's initial park move.
    // (Status-query "?" writes also reach the wire log, so locate the plan
    // slice by its leading G90 rather than taking a tail.)
    let rawLog = String(decoding: await sim.writtenBytesSnapshot, as: UTF8.self)
    let log = rawLog
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    expect(log.count >= sequence.count, "all plan lines reached the wire")
    guard let planStart = log.firstIndex(of: "G90") else {
        expect(false, "plan-leading G90 found in wire log — full log: \(rawLog.debugDescription)")
        return
    }
    let tlsLines = Array(log[planStart..<min(planStart + sequence.count, log.count)])
    expect(tlsLines == sequence, "wire bytes match the planned emission exactly (got \(tlsLines))")
    expect(containsLine(await sim.writtenBytesSnapshot, "G10 L20 P1 Z3"),
           "log shows the G10 L20 P1 Z3 commit")
    expect(TouchOff.isZOnly(tlsLines), "the transmitted plan slice carries zero X/Y words")

    // Sim stays healthy after probing: still Idle, answers status.
    do {
        try await sim.write(Data(GCodeLine.sending("?").utf8))
        let status = String(decoding: try await sim.read(), as: UTF8.self)
        expect(status.contains("<Idle|"), "sim idle after TLS cycle (got '\(status)')")
    } catch {
        expect(false, "status query after cycle threw \(error)")
    }
}

Task { @MainActor in
    await run()
    print("ShopPilotVerify2022b: PASS — TLS plan emits M6 + single Z probe + G10 L20 P1 Z[t] with ZERO X/Y words, completes on SimulatorTransport (all ok), XY WPos identical before/after from transport state, disconnected invocation is a no-op.")
    exit(0)
}
RunLoop.main.run()
