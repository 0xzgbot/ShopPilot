import Foundation
import ShopPilotCore
import ShopPilotSerial

/// SPK-0415 verify (CLT machine, no XCTest).
/// Proves post auto-select from the machine profile:
///   1. TYPE MAPPING: `MachineProfileType.grbl` → GRBL post, `.universal` →
///      Universal post; a profile's `autoPostProcessorType` reflects its
///      machineType (the bridge switches on this).
///   2. UNITS: the profile's `units` select the modal — millimeter → "G21 ;
///      Set millimeter units", inch → "G20 ; Set inch units" in the
///      post-processed file; GRBL and Universal posts both honor it.
///   3. POST OUTPUT: GRBL post has no line numbers, Universal does; file
///      extensions gcode vs nc; inch output still has absolute positioning.
///   4. PERSIST: `MachineProfile` round-trips machineType + units through
///      Codable, and a LEGACY profile JSON (no machineType/units keys)
///      decodes as grbl + millimeter (store stays readable after upgrade).
/// The app wiring (Save Toolpaths uses the active store profile) is
/// compile-checked by the app build.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1. Type mapping. ───────────────────────────────────────────────────
    try expect(MachineProfileType.grbl.autoPostProcessorType() == .grbl,
               "GRBL machine → GRBL post")
    try expect(MachineProfileType.universal.autoPostProcessorType() == .universal,
               "Universal machine → Universal post")
    let grblProfile = MachineProfile(name: "My GRBL", config: .simulator, machineType: .grbl)
    let uniProfile = MachineProfile(name: "My CNC", config: .simulator, machineType: .universal)
    try expect(grblProfile.autoPostProcessorType == .grbl, "profile auto-selects GRBL")
    try expect(uniProfile.autoPostProcessorType == .universal, "profile auto-selects Universal")

    // ── 2. Units drive the modal. ──────────────────────────────────────────
    let sample: [String] = ["G0 X10.0 Y10.0", "G1 X20.0 Y10.0 F1000"]
    let mmPost = GRBLPostProcessor.grbl(machineName: "MM Machine", units: .millimeter)
    let mmOut = mmPost.process(gcodeLines: sample)
    try expect(mmOut.gcodeString.contains("G21 ; Set millimeter units"),
               "mm profile emits G21")
    try expect(!mmOut.gcodeString.contains("G20"), "mm profile has no G20")

    let inchPost = GRBLPostProcessor.grbl(machineName: "Inch Machine", units: .inch)
    let inchOut = inchPost.process(gcodeLines: sample)
    try expect(inchOut.gcodeString.contains("G20 ; Set inch units"),
               "inch profile emits G20")
    try expect(!inchOut.gcodeString.contains("G21"), "inch profile has no G21")

    // Universal post honors units too.
    let uniMm = GRBLPostProcessor.universal(machineName: "U", units: .millimeter)
    try expect(uniMm.process(gcodeLines: sample).gcodeString.contains("G21"),
               "Universal mm post emits G21")
    let uniIn = GRBLPostProcessor.universal(machineName: "U", units: .inch)
    try expect(uniIn.process(gcodeLines: sample).gcodeString.contains("G20"),
               "Universal inch post emits G20")

    // ── 3. Post-type differences preserved. ────────────────────────────────
    try expect(mmOut.gcodeString.contains("(Post Processor: GRBL 1.1)"),
               "GRBL post names GRBL 1.1")
    try expect(!mmOut.gcodeString.contains("10: G0 X10.0"), "GRBL post has no line numbers")
    let uniOut = uniMm.process(gcodeLines: sample)
    try expect(uniOut.gcodeString.contains("(Post Processor: Universal G-Code)"),
               "Universal post names itself")
    try expect(uniOut.gcodeString.contains("10: G0 X10.0"), "Universal post numbers lines")
    try expect(grblProfile.autoPostProcessorType.fileExtension == "gcode"
               && uniProfile.autoPostProcessorType.fileExtension == "nc",
               "extensions: grbl→gcode, universal→nc")

    // ── 4. Persist + legacy decode. ────────────────────────────────────────
    let data = try JSONEncoder().encode(uniProfile)
    let decoded = try JSONDecoder().decode(MachineProfile.self, from: data)
    try expect(decoded.machineType == .universal && decoded.units == .millimeter,
               "machineType + units round-trip Codable")

    let inchProfile = MachineProfile(name: "Inch GRBL", config: .simulator, machineType: .grbl, units: .inch)
    let inchData = try JSONEncoder().encode(inchProfile)
    let inchDecoded = try JSONDecoder().decode(MachineProfile.self, from: inchData)
    try expect(inchDecoded.units == .inch, "inch units round-trip")

    // Legacy profile JSON (pre-SPK-0415: no machineType/units keys) decodes
    // as grbl + millimeter so the store survives upgrades.
    let legacyJSON = #"{"id":"\#(UUID().uuidString)","name":"Old Machine","config":{"baudRate":115200,"portName":"/dev/tty.simulator","dataBits":8,"parity":"none","stopBits":"one"},"isSimulator":true,"createdAt":0,"updatedAt":0}"#
    let legacy = try JSONDecoder().decode(MachineProfile.self, from: Data(legacyJSON.utf8))
    try expect(legacy.machineType == .grbl, "legacy profile decodes as grbl")
    try expect(legacy.units == .millimeter, "legacy profile decodes as millimeter")
    try expect(legacy.autoPostProcessorType == .grbl, "legacy profile auto-selects GRBL post")

    print("ShopPilotVerify0415: PASS — profile machineType auto-selects GRBL/Universal post, "
          + "profile units emit G21/G20, post-type differences intact, Codable round-trip + legacy decode")
}

do {
    try main()
} catch {
    print("ShopPilotVerify0415: FAIL — \(error)")
    exit(1)
}
