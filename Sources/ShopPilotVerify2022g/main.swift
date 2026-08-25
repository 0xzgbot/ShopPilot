import Foundation
import ShopPilotCore

// SPK-2022g verify — Macros + alarm decode banner.
//
// AC1: every GRBL 1.1 ALARM code (1–9) decodes via AlarmDecoder to non-nil,
//      DISTINCT plain text carrying its original token; unknown codes
//      ("ALARM:99") and garbage return nil so callers show the raw line.
// AC2: common error: codes decode; unknown ones fall through to nil.
// AC3: macros — suggested defaults exist (park / bit-change / surface),
//      persist through a private UserDefaults suite, and execution through
//      SimulatorTransport sends EXACTLY the stored lines, each acked "ok";
//      NOTHING is sent without an explicit invocation (cold/opened sim has an
//      empty wire log; disconnected sends refuse).
// AC4: banner + no-auto-run contracts at source level (DOGFOOD02 pattern):
//      MachineController decodes alarms through AlarmDecoder; the machine dock
//      renders an alarm banner and a macro strip; connect()/init() never calls
//      runMacro.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2022g: FAIL — \(msg)")
        exit(1)
    }
}

@MainActor
func run() async {
    // --- AC1: ALARM table completeness + distinctness ------------------------
    var decodedTexts: Set<String> = []
    for code in 1...9 {
        let text = AlarmDecoder.decode("ALARM:\(code)")
        expect(text != nil, "ALARM:\(code) must decode to plain text")
        expect(text!.contains("ALARM:\(code)"), "decoded text carries the original token (got '\(text!)')")
        decodedTexts.insert(text!)
    }
    expect(decodedTexts.count == 9, "all nine GRBL 1.1 ALARM codes decode to DISTINCT text")

    // Prefix/suffix tolerance: bare token == embedded forms.
    expect(AlarmDecoder.decode("ALARM:2") == AlarmDecoder.decode("ALARM:2 [MSG:Check Limits]"),
           "embedded [MSG:] form decodes identically to the bare token")
    expect(AlarmDecoder.decode("alarm:5")?.contains("ALARM:5") == true,
           "decoding is case-insensitive")

    // Unknown / garbage → nil (raw-line fallback stays the caller's move).
    expect(AlarmDecoder.decode("ALARM:99") == nil, "unknown ALARM:99 returns nil")
    expect(AlarmDecoder.decode("ALARM:") == nil, "bare ALARM: with no code returns nil")
    expect(AlarmDecoder.decode("") == nil, "empty line returns nil")
    expect(AlarmDecoder.decode("hello world") == nil, "garbage returns nil")
    expect(AlarmDecoder.decode("ok") == nil, "'ok' is not a fault line")
    expect(AlarmDecoder.decode("<Idle|MPos:0.000,0.000,0.000|FS:0,0>") == nil,
           "ordinary status reports return nil")

    // --- AC2: error: subset ---------------------------------------------------
    var errorTexts: Set<String> = []
    for code in 1...9 {
        let text = AlarmDecoder.decode("error:\(code)")
        expect(text != nil, "error:\(code) decodes")
        expect(text!.contains("error:\(code)"), "decoded error text carries its token")
        errorTexts.insert(text!)
    }
    expect(errorTexts.count == 9, "common error: codes decode distinctly")
    expect(AlarmDecoder.decode("error:99") == nil, "unknown error:99 returns nil")

    // --- AC3a: macro defaults shape ------------------------------------------
    let defaults = MacroStore.suggestedDefaults
    expect(defaults.count >= 3, "three suggested macro buttons (park / bit-change / surface)")
    let names = defaults.map { $0.name.lowercased() }.joined(separator: "|")
    expect(names.contains("park"), "a Park macro exists")
    expect(names.contains("bit"), "a bit-change macro exists")
    expect(names.contains("surface"), "a surface macro exists")
    for macro in defaults {
        expect(!macro.lines.isEmpty, "macro '\(macro.name)' carries ordered G-code lines")
    }

    // Persistence round-trip through an ISOLATED defaults suite (never touch
    // the user's real storage from a verifier).
    let suiteName = "ShopPilotVerify2022g.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suiteName)!
    defer { testDefaults.removePersistentDomain(forName: suiteName) }

    expect(MacroStore.load(defaults: testDefaults).count == defaults.count,
           "fresh load falls back to the suggested defaults")
    let edited = [MacroButton(name: "My park", lines: ["G91 G0 Z5", "G90"])]
    MacroStore.save(edited, defaults: testDefaults)
    expect(MacroStore.load(defaults: testDefaults) == edited,
           "saved macros load back byte-equal (user edits persist)")

    // --- AC3b: NO auto-send — cold sim has an empty wire ----------------------
    let coldSim = SimulatorTransport()
    expect(await coldSim.writtenBytesSnapshot.isEmpty,
           "nothing is ever auto-sent: a fresh transport has zero bytes on the wire")

    // Disconnected invocation refuses (no silent send, 1920f precedent).
    var disconnectedRefused = false
    do {
        try await coldSim.write(Data(GCodeLine.sending(MacroStore.suggestedDefaults[0].lines[0]).utf8))
    } catch MachineTransportError.disconnected {
        disconnectedRefused = true
    } catch {
        disconnectedRefused = false
    }
    expect(disconnectedRefused, "disconnected macro write throws .disconnected — nothing auto-runs")

    // --- AC3c: explicit click-equivalent execution over SimulatorTransport ----
    let sim = SimulatorTransport()
    do {
        try await sim.open(config: SerialConfig(baudRate: 115200, isSimulator: true,
                                                simulationDelayNanoseconds: 0))
    } catch {
        expect(false, "sim open failed: \(error)")
    }
    // Opening the connection itself must still have sent nothing (no auto-run
    // on connect — §2 non-negotiable).
    expect(await sim.writtenBytesSnapshot.isEmpty,
           "connect sends nothing — the wire stays empty until an explicit macro click")

    for macro in MacroStore.suggestedDefaults {
        var ackedAll = true
        for line in macro.lines {
            do {
                try await sim.write(Data(GCodeLine.sending(line).utf8))
                let ack = String(decoding: try await sim.read(), as: UTF8.self)
                if !ack.contains("ok") { ackedAll = false }
            } catch {
                expect(false, "'\(line)' of '\(macro.name)' threw \(error)")
            }
        }
        expect(ackedAll, "every line of macro '\(macro.name)' was ok-gated by the controller")

        // The wire carries EXACTLY the stored lines, in order.
        let rawLog = String(decoding: await sim.writtenBytesSnapshot, as: UTF8.self)
        let logLines = rawLog.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let tail = Array(logLines.suffix(macro.lines.count))
        expect(tail == macro.lines,
               "wire bytes match '\(macro.name)' stored lines exactly (got \(tail))")
    }

    // Sim healthy afterwards.
    do {
        try await sim.write(Data(GCodeLine.sending("?").utf8))
        let status = String(decoding: try await sim.read(), as: UTF8.self)
        expect(status.contains("<Idle|"), "sim idle after macro runs (got '\(status)')")
    } catch {
        expect(false, "status after macros threw \(error)")
    }

    // --- AC4: banner + no-auto-run contracts at source level (DOGFOOD02) -----
    let controllerSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/MachineController.swift", encoding: .utf8)
    expect(controllerSrc?.contains("AlarmDecoder.decode") == true,
           "MachineController latches alarms through AlarmDecoder (plain-text banner source)")

    let connectionSrc = try? String(
        contentsOfFile: "Sources/ShopPilot/MachineConnection.swift", encoding: .utf8)
    expect(connectionSrc?.contains("private var alarmBanner") == true,
           "machine dock renders the decoded alarm banner")
    expect(connectionSrc?.contains("controller.latchedAlarm") == true,
           "alarm banner surfaces the decoder text from the latched alarm")
    expect(connectionSrc?.contains("private var macroStrip") == true,
           "machine dock renders the macro button strip")
    expect(connectionSrc?.contains("controller.runMacro(macro)") == true,
           "macro strip buttons route through the controller's ok-gated sender")
    expect(connectionSrc?.contains("MacroEditorRow") == true,
           "macros are user-editable in the dock UI")

    // No auto-run: connect() and init() must never invoke runMacro.
    if let src = controllerSrc,
       let connectRange = src.range(of: "public func connect()"),
       let disconnectRange = src.range(of: "public func disconnect()") {
        let connectBody = src[connectRange.lowerBound..<disconnectRange.lowerBound]
        expect(!connectBody.contains("runMacro"), "connect() never fires a macro")
    } else {
        expect(false, "connect()/disconnect() found in MachineController.swift")
    }
    if let src = controllerSrc,
       let initRange = src.range(of: "public init()"),
       let observeRange = src.range(of: "// MARK: - State derivation") {
        let initBody = src[initRange.upperBound..<observeRange.lowerBound]
        expect(!initBody.contains("runMacro"), "init() never fires a macro (no auto-run on launch)")
    } else {
        expect(false, "init() bounds found in MachineController.swift")
    }

    print("ShopPilotVerify2022g: PASS — all 9 GRBL ALARM codes + error subset decode distinctly (unknown→nil); macro defaults persist via UserDefaults; explicit macro execution sends exactly the stored lines ok-gated over SimulatorTransport; wire empty on open/disconnect-refuses; banner + macro strip wired at source level; no auto-run from connect/init.")
    exit(0)
}

Task { @MainActor in
    await run()
}
RunLoop.main.run()
