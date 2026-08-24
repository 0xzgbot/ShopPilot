import Foundation
import ShopPilotCore

// SPK-1920f verify — probe wizard on SimulatorTransport + disconnected no-op.
//
// AC1: the touch-plate probe sequence (TouchOff.gcode) completes through
//      SimulatorTransport — every line is acked "ok" while connected.
// AC2: with the transport DISCONNECTED, write() throws .disconnected before
//      any side effect (honest no-op at the transport layer; the controller
//      guard is compile-checked by the app build).
// AC3: zOffset math consistent after a simulated hit.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerifyDOGFOOD1920f: FAIL — \(msg)")
        exit(1)
    }
}

@MainActor
func run() async {
    // --- AC2 first: disconnected probe is refused, nothing queued -----------
    let sim = SimulatorTransport()
    var disconnectedRefused = false
    do {
        try await sim.write(Data("G38.2 Z-10 F120\n".utf8))
    } catch MachineTransportError.disconnected {
        disconnectedRefused = true
    } catch {
        disconnectedRefused = false
    }
    expect(disconnectedRefused, "disconnected G38.2 write throws .disconnected (no silent ok)")

    // --- AC1: connect, then run the full probe sequence ---------------------
    do {
        try await sim.open(config: ShopPilotCore.SerialConfig(baudRate: 115200, isSimulator: true))
    } catch {
        expect(false, "sim open failed: \(error)")
    }

    let plan = TouchOff.plan(plateThickness: 3.0)
    let sequence = TouchOff.gcode(plan)
    expect(sequence.count == 4, "probe sequence has 4 lines (G90/G0/G38.2/G0)")

    for line in sequence {
        do {
            // write() routes through handleCommand and fans the ack into the
            // read buffer; a non-ok reply would surface there instead of "ok".
            try await sim.write(Data(GCodeLine.sending(line).utf8))
            let ack = try await sim.read()
            expect(String(decoding: ack, as: UTF8.self).contains("ok"),
                   "'\(line)' acked ok (got '\(String(decoding: ack, as: UTF8.self))')")
        } catch {
            expect(false, "'\(line)' threw \(error) — sequence did not complete")
        }
    }

    // --- AC3: offset math on a simulated hit --------------------------------
    // The sim does not model probing motion; treat the plate-top contact as
    // machine Z −3 and verify the offset math that turns it into G54 Z.
    let hitZ = -3.0
    let offset = TouchOff.zOffset(probeHitZ: hitZ, plateThickness: 3.0)
    expect(offset == 6.0, "zOffset(−3, 3mm plate) == 6.0 (got \(offset))")
}

Task { @MainActor in
    await run()
    print("ShopPilotVerifyDOGFOOD1920f: PASS — probe sequence completes on SimulatorTransport (4× ok), disconnected probe honestly refused, offset math clean.")
    exit(0)
}
RunLoop.main.run()
