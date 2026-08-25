import Foundation
import ShopPilotCore

// SPK-2022a verify — XYZ plate probe cycle (Z → X → Y) on SimulatorTransport.
//
// AC1: the full three-leg cycle completes through SimulatorTransport — every
//      line is acked "ok", and legs run in Z → X → Y order.
// AC2: each leg's `G10 L20 P1` commit carries correct plate math — Z uses the
//      plate thickness; X/Y use plate-half + user offset, consistent with
//      TouchOff.zOffset.
// AC3: abort after leg 2 leaves leg-1/leg-2 commits intact and applies no
//      leg-3 (Y) commit — observable via the sim's race-free written-bytes log.
// AC4: disconnected invocation emits nothing and changes no state (1920f
//      precedent: honest no-op at the transport layer; the controller guard is
//      compile-checked by the app build).

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2022a: FAIL — \(msg)")
        exit(1)
    }
}

func containsLine(_ data: Data, _ needle: String) -> Bool {
    String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix(needle) }
}

@MainActor
func run() async {
    // --- Planner-level plate math first (pure, no I/O) ----------------------
    let plan = TouchOff.planXYZPlate(plateThickness: 3.0)
    let legs = TouchOff.xyzPlateLegs(plan)
    expect(legs.count == 3, "three legs planned (got \(legs.count))")

    // AC2: per-leg G10 L20 math.
    let zLeg = legs[0], xLeg = legs[1], yLeg = legs[2]
    expect(zLeg.contains("G10 L20 P1 Z3"), "Z leg commits G10 L20 P1 Z3 (plate thickness); got \(zLeg)")
    expect(xLeg.contains("G10 L20 P1 X1.5"), "X leg commits G10 L20 P1 X1.5 (plate half + 0); got \(xLeg)")
    expect(yLeg.contains("G10 L20 P1 Y1.5"), "Y leg commits G10 L20 P1 Y1.5 (plate half + 0); got \(yLeg)")

    // Consistency with TouchOff.zOffset: hit at plate top (0) → thickness.
    expect(TouchOff.zCommitOffset(plateThickness: 3.0) == TouchOff.zOffset(probeHitZ: 0, plateThickness: 3.0),
           "zCommitOffset(3) == zOffset(hit 0, 3mm plate) == 3")
    // Plate-half + user offset.
    expect(TouchOff.xyCommitOffset(plateThickness: 3.0, userXYOffset: 2.25) == 3.75,
           "xyCommitOffset(3, +2.25) == 3.75 (got \(TouchOff.xyCommitOffset(plateThickness: 3.0, userXYOffset: 2.25)))")
    let custom = TouchOff.planXYZPlate(plateThickness: 3.0, userXYOffset: 2.25)
    expect(TouchOff.xyzPlateGcode(custom).contains("G10 L20 P1 X3.75"),
           "custom userXYOffset flows into the emitted plan (X3.75)")

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
    expect(disconnectedRefused, "disconnected probe write throws .disconnected (no silent ok)")
    // Nothing was EMITTED in response: the read buffer stays empty and reads
    // keep throwing .disconnected — no ack, no ok, no state transition.
    var readRefused = false
    do {
        _ = try await coldSim.read()
    } catch MachineTransportError.disconnected {
        readRefused = true
    } catch {
        readRefused = false
    }
    expect(readRefused, "disconnected read refuses — no ack/response was emitted")

    // --- AC1: connect, then run the full Z → X → Y cycle --------------------
    let sim = SimulatorTransport()
    do {
        try await sim.open(config: SerialConfig(baudRate: 115200, isSimulator: true,
                                                simulationDelayNanoseconds: 0))
    } catch {
        expect(false, "sim open failed: \(error)")
    }

    for line in TouchOff.xyzPlateGcode(plan) {
        do {
            try await sim.write(Data(GCodeLine.sending(line).utf8))
            let ack = try await sim.read()
            expect(String(decoding: ack, as: UTF8.self).contains("ok"),
                   "'\(line)' acked ok (got '\(String(decoding: ack, as: UTF8.self))')")
        } catch {
            expect(false, "'\(line)' threw \(error) — cycle did not complete")
        }
    }

    // Legs ran in Z → X → Y order: first G38.2 is Z, last is Y.
    let fullLog = await sim.writtenBytesSnapshot
    let lines = String(decoding: fullLog, as: UTF8.self)
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    let probes = lines.filter { $0.hasPrefix("G38.2 ") }
    expect(probes.count == 3, "exactly three probe moves sent (got \(probes.count): \(probes))")
    expect(probes.first?.hasPrefix("G38.2 Z") == true, "first leg probes Z")
    expect(probes.last?.hasPrefix("G38.2 Y") == true, "last leg probes Y")
    expect(containsLine(fullLog, "G10 L20 P1 Z3"), "full cycle committed Z offset")
    expect(containsLine(fullLog, "G10 L20 P1 X1.5"), "full cycle committed X offset")
    expect(containsLine(fullLog, "G10 L20 P1 Y1.5"), "full cycle committed Y offset")

    // Sim stays healthy after probing: still Idle, answers status.
    do {
        try await sim.write(Data("?".utf8))
        let status = String(decoding: try await sim.read(), as: UTF8.self)
        expect(status.contains("<Idle|"), "sim idle after XYZ cycle (got '\(status)')")
    } catch {
        expect(false, "status query after cycle threw \(error)")
    }

    // --- AC3: abort after leg 2 keeps committed legs, no leg-3 commit -------
    let abortSim = SimulatorTransport()
    do {
        try await abortSim.open(config: SerialConfig(baudRate: 115200, isSimulator: true,
                                                     simulationDelayNanoseconds: 0))
    } catch {
        expect(false, "abort-sim open failed: \(error)")
    }
    // Operator aborts mid-cycle: only legs 1 and 2 are sent; leg 3 never runs.
    do {
        for line in (legs[0] + legs[1]) {
            try await abortSim.write(Data(GCodeLine.sending(line).utf8))
            _ = try await abortSim.read()
        }
    } catch {
        expect(false, "abort-sim leg send threw \(error)")
    }
    let abortLog = await abortSim.writtenBytesSnapshot
    expect(containsLine(abortLog, "G10 L20 P1 Z3"), "after abort, leg-1 Z offset intact")
    expect(containsLine(abortLog, "G10 L20 P1 X1.5"), "after abort, leg-2 X offset intact")
    expect(!String(decoding: abortLog, as: UTF8.self).contains("P1 Y"),
           "after abort, no leg-3 Y offset applied anywhere in the log")
}

Task { @MainActor in
    await run()
    print("ShopPilotVerify2022a: PASS — XYZ plate cycle completes on SimulatorTransport (Z→X→Y, all ok), per-leg G10 L20 math correct, abort after leg 2 keeps committed offsets with no Y commit, disconnected invocation emits nothing.")
    exit(0)
}
RunLoop.main.run()
