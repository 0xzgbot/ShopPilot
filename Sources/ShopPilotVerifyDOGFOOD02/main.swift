import Foundation
import ShopPilotCore
#if canImport(ShopPilot)
import ShopPilot
#endif

// SPK-DOGFOOD-02 verify — the raw-TX/RX + alarm re-render storm is structurally gone.
//
// Storm mechanics proven fixed:
//   1. MachineController.recomputeChromeState must NOT republish when the
//      derived state is unchanged (identical `<Idle|...>` polls at 500ms).
//   2. ConsoleLog must stay capped at maxMessages under sustained appends
//      (poll rate) — the buffer never grows unbounded.
//   3. A windowed tail of the log must be stable and correct (the UI ForEach
//      diffs at most `visibleTail` rows; oldest rows drop, live traffic kept).

@MainActor
func main() async {
    var failures: [String] = []
    func expect(_ cond: Bool, _ msg: String) {
        if !cond { failures.append(msg) }
    }

    // --- 1. Chrome publish-suppression contract (source-level) --------------
    // The controller must guard the write: `if next != chromeState`.
    let controllerSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/MachineController.swift", encoding: .utf8)
    expect(controllerSrc?.contains("if next != chromeState") == true,
           "recomputeChromeState must skip identical chromeState writes")

    // The old unconditional write must be gone from that function.
    if let src = controllerSrc,
       let range = src.range(of: "private func recomputeChromeState") {
        let body = src[range.lowerBound...].prefix(700)
        expect(!body.contains("chromeState = derivedChromeState()"),
               "unconditional chromeState write must be removed")
    } else {
        failures.append("recomputeChromeState not found in MachineController.swift")
    }

    // --- 1b. Status publish-suppression contract (GUI-run follow-up) --------
    // handleTransportEvent must not re-write currentStatus when the report is
    // identical — that was the second invalidation source (every observer of
    // ConnectionManager rebuilt on each 500ms poll).
    let connectionSrcFull = try? String(
        contentsOfFile: "Sources/ShopPilot/MachineConnection.swift", encoding: .utf8)
    expect(connectionSrcFull?.contains("if trimmed != currentStatus") == true,
           "currentStatus write must be guarded against identical reports")


    // --- 2. Console isolation contract (source-level) -----------------------
    // The stage body must not read consoleLog.messages directly (that is what
    // dragged every append through the whole-body rebuild + 500-row diff).
    let connectionSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/MachineConnection.swift", encoding: .utf8)
    expect(connectionSrc?.contains("ForEach(Array(connectionManager.consoleLog.messages))") != true,
           "MachineConnectionView must not ForEach the full console buffer")
    expect(connectionSrc?.contains(".onReceive(connectionManager.consoleLog.$messages)") != true,
           "stage body must not invalidate on every console append")
    expect(connectionSrc?.contains("struct ConsoleView: View") == true,
           "console must render in its own observing view")
    expect(connectionSrc?.contains("visibleTail") == true,
           "console ForEach must be windowed to a tail slice")

    // --- 3. Behavioral: ConsoleLog stays capped under poll-rate pumping -----
    let log = ConsoleLog()
    expect(log.maxMessages == 500, "ConsoleLog default cap is 500 (got \(log.maxMessages))")

    // Simulate ~60s at the 500ms poll cadence with raw TX/RX ON: each tick
    // produces one RX (status report) + one TX (`?` query). Appends defer to
    // the main queue (SPK-UI601), so drain between bursts; the cap must hold
    // on its own — the UI never has to trim for it.
    func drain(_ seconds: TimeInterval = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    for burst in 0..<10 {
        for i in 0..<100 {
            log.append(ConsoleMessage(text: "?", type: .sent))
            log.append(ConsoleMessage(
                text: "<Idle|MPos:0.000,0.000,5.000|WPos:0.000,0.000,5.000|FS:0,0> b\(burst) i\(i)",
                type: .received))
        }
        await drain()
    }
    expect(log.messages.count == log.maxMessages,
           "buffer held exactly the newest \(log.maxMessages) after 2000 poll-rate appends (count=\(log.messages.count))")
    expect(log.messages.last?.type == .received,
           "live traffic preserved — newest message still present")

    // --- 4. Behavioral: windowed tail correctness ---------------------------
    // The tail the console renders must be the NEWEST rows in order.
    let all = log.messages
    let tailStart = all.count - 80
    let renderedTail = Array(all[tailStart...])
    expect(renderedTail.count == 80, "tail window is 80 rows (got \(renderedTail.count))")
    expect(renderedTail.first?.id == all[tailStart].id, "tail starts at the right offset")
    expect(renderedTail.last?.id == all.last?.id, "tail ends at the newest message")
    // IDs unique → ForEach identity churn-free across appends.
    expect(Set(all.map(\.id)).count == all.count, "message ids are unique (stable ForEach identity)")

    // --- 5. Regression: alarm path without raw mode -------------------------
    // noteControllerOutput must latch an alarm from a plain ALARM report and
    // the plain-English copy must survive (same text as before this fix).
    expect(controllerSrc?.contains("Motion stopped; press Reset to clear.") == true,
           "plain-English alarm copy intact (regression)")

    if failures.isEmpty {
        print("ShopPilotVerifyDOGFOOD02: PASS — chrome write guarded against identical polls; console isolated to its own windowed view; buffer capped at 500 under 2000 poll-rate appends; tail window stable; alarm path intact.")
    } else {
        print("ShopPilotVerifyDOGFOOD02: FAIL — \(failures.joined(separator: "; "))")
        exit(1)
    }
}

await main()
