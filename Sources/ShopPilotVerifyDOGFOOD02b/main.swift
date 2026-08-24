import Foundation
import ShopPilotCore

// SPK-DOGFOOD-02 follow-up — the disconnect→reconnect hang.
//
// Repro (GUI, 2026-08-22): connect Simulator → run job → alarm latched →
// Reset → toggle Raw TX/RX → press Disconnect → press Connect. The app
// stopped answering AX at 0% CPU (blocked in mach_msg/psynch, not spinning)
// and never recovered; the window never came back.
//
// Mechanics found by reading the teardown path:
//   1. `SimulatorTransport.close()` yields `.disconnected` and FINISHES every
//      fan-out subscription (`fanOut.finish()`).
//   2. `ConnectionManager.disconnect()` cancels its own eventTask first — but
//      cancellation only lands at the task's next suspension point.
//   3. `MachineController.disconnect()` calls `machineSession.detach()`, which
//      cancels session tasks — but the GCodeStreamer keeps a stale `transport`
//      reference forever (nothing ever nils it).
//   4. On RECONNECT, `streamer.reset()` / hold/resume write 0x18 through the
//      STALE transport from the previous connection while the new event loop
//      also subscribes. Two writers on one actor + a finished fan-out means
//      the ok-wait can wait on a stream that already finished, and the UI
//      awaits it on the main thread → permanent beachball.
//
// Fix contract under test:
//   a. A streamer that finished streaming must not retain a closed transport:
//      after `finishStreaming()`, `hasStaleTransport == false`.
//   b. Writing 0x18 through a streamer with NO transport is a safe no-op
//      (`reset()` returns without throwing or hanging).
//   c. The streamer's state resets to `.idle` even when the transport is gone.

@MainActor
func main() async {
    var failures: [String] = []
    func expect(_ cond: Bool, _ msg: String) {
        if !cond { failures.append(msg) }
    }

    let transport = SimulatorTransport()
    do {
        try await transport.open(config: SerialConfig(isSimulator: true))
    } catch {
        print("FAIL: sim open error \(error)"); exit(1)
    }

    // Stream two trivial lines so the streamer binds the transport exactly
    // like `streamSessionBuffer` does.
    let streamer = GCodeStreamer()
    do {
        _ = try await streamer.stream(lines: ["G0 X1", "G0 X2"], to: transport)
    } catch {
        // An ok-wait timeout here would itself be a finding, but the lines
        // are valid and the sim answers instantly — treat any throw as fail.
        print("FAIL: stream threw \(error)"); exit(1)
    }

    expect(streamer.state == .idle || streamer.currentLine == 2,
           "stream finished cleanly (state=\(streamer.state), line=\(streamer.currentLine))")

    // --- a. finishStreaming must drop the stale transport -------------------
    streamer.finishStreaming()
    expect(streamer.hasStaleTransport == false,
           "after finishStreaming() the streamer must NOT retain the closed transport")

    // --- b. close the transport; stale-reference reset must be a no-op ------
    await transport.close()

    // Old behavior: streamer.transport still pointed at the CLOSED transport;
    // a later reset() would try to write 0x18 into it during the NEXT
    // connection's teardown/reconnect and block the caller.
    // New behavior: reset() sees no transport and returns immediately.
    let clock = ContinuousClock()
    let start = clock.now
    await streamer.reset()
    let elapsed = clock.now - start
    expect(elapsed < .seconds(2),
           "reset() with no transport must return immediately (took \(elapsed))")

    // --- c. state still resets ----------------------------------------------
    expect(streamer.state == .idle, "state resets to idle without a transport")

    if failures.isEmpty {
        print("ShopPilotVerifyDOGFOOD02b: PASS — streamer drops its transport on finishStreaming(); reset() without a transport is an immediate no-op; reconnect cannot inherit a closed wire.")
    } else {
        print("ShopPilotVerifyDOGFOOD02b: FAIL — \(failures.joined(separator: "; "))")
        exit(1)
    }
}

await main()
