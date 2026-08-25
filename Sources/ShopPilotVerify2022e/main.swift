import Foundation
import ShopPilotCore

// SPK-2022e verify — per-op enable flag + send-time program filter.
//
// AC1: with the middle op disabled, ToolpathTreeManager.program(from:) emits
//      ONLY ops A and C's G-code — op B's marker is absent; A and C survive
//      byte-identical and in tree order.
// AC2: re-enabling the middle op restores the FULL program byte-for-byte
//      without any regeneration (each node's toolpathResult untouched).
// AC3: recalc/export semantics unaffected — a disabled-but-dirty op still
//      appears in allDirtyNodes and still recalculates.
// AC4: legacy persistence — a payload JSON written before SPK-2022e (no
//      "isEnabled" key) decodes cleanly and restores every node enabled.
// AC5: round-trip — a disabled flag survives encode → decode → restore.

func expect(_ cond: Bool, _ msg: String) {
    if !cond {
        print("ShopPilotVerify2022e: FAIL — \(msg)")
        exit(1)
    }
}

@MainActor
func run() async throws {
    // --- Fixture: three ops with distinct markers ---------------------------
    let manager = ToolpathTreeManager()
    let gcodeA = "(OP-A)\nG0 X0 Y0\nG1 Z-1 F300"
    let gcodeB = "(OP-B)\nG0 X20 Y20\nG1 Z-2 F300"
    let gcodeC = "(OP-C)\nG0 X40 Y40\nG1 Z-3 F300"
    for (name, gcode) in [("Op A", gcodeA), ("Op B", gcodeB), ("Op C", gcodeC)] {
        let node = manager.addOperation(name)
        node.toolpathResult = gcode
        node.clearDirty()
    }
    expect(manager.root.children.count == 3, "fixture has 3 ops")
    expect(manager.allNodes.allSatisfy { $0.isEnabled }, "fresh nodes are enabled")

    // AC1: disable the middle op → filtered program drops exactly op B.
    let full = ToolpathTreeManager.program(from: manager.allNodes)
    expect(full.contains("(OP-A)") && full.contains("(OP-B)") && full.contains("(OP-C)"),
           "full program carries all three markers")
    guard let opB = manager.findNode(id: manager.root.children[1].id) else {
        print("ShopPilotVerify2022e: FAIL — cannot find Op B")
        exit(1)
    }
    opB.isEnabled = false

    let filtered = ToolpathTreeManager.program(from: manager.allNodes)
    let expectedFiltered = [gcodeA, gcodeC].joined(separator: "\n")
    expect(filtered == expectedFiltered,
           "filtered program is EXACTLY ops A + C byte-identical, order preserved")
    expect(!filtered.contains("(OP-B)") && !filtered.contains("X20"),
           "disabled op's marker AND its motion lines are excluded")
    expect(filtered.contains("(OP-A)") && filtered.contains("G1 Z-3 F300"),
           "ops A and C intact in the filtered send")

    // AC2: re-enable → full program restored byte-for-byte, no regeneration.
    let resultBeforeReenable = opB.toolpathResult
    opB.isEnabled = true
    let restored = ToolpathTreeManager.program(from: manager.allNodes)
    expect(restored == full, "re-enable restores the full program byte-for-byte")
    expect(opB.toolpathResult == resultBeforeReenable && opB.toolpathResult == gcodeB,
           "toggling never regenerates — stored G-code untouched")

    // Purity: filtering must not mutate any node.
    _ = { opB.isEnabled = false; _ = ToolpathTreeManager.program(from: manager.allNodes); opB.isEnabled = true }()
    expect(manager.root.children.allSatisfy { $0.toolpathResult != nil },
           "filter pass leaves every node's result in place")

    // AC3: dirty-recalc ignores the enable flag.
    opB.isEnabled = false
    opB.markDirty()
    expect(manager.root.allDirtyNodes.contains(where: { $0.id == opB.id }),
           "a DISABLED op still counts as dirty — recalc/export gating unchanged")
    let recalced = manager.recalculateDirtyNodes()
    expect(recalced.contains(where: { $0.id == opB.id }),
           "recalculateDirtyNodes processes a disabled op too")
    opB.clearDirty()
    opB.toolpathResult = gcodeB
    opB.isEnabled = true

    // AC4: legacy decode — strip every "isEnabled" key from an encoded
    // payload (simulating a pre-SPK-2022e package) → restores enabled.
    var payload = ShopPilotPackagePayload(job: Job(name: "Legacy"))
    opB.isEnabled = false
    payload.toolpaths = ShopPilotPackagePayload.toolpaths(from: manager)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let jsonData = try encoder.encode(payload)
    let legacyJSON = String(data: jsonData, encoding: .utf8)!
        .replacingOccurrences(of: "\"isEnabled\":false,", with: "")
        .replacingOccurrences(of: "\"isEnabled\":true,", with: "")
        .replacingOccurrences(of: ",\"isEnabled\":false", with: "")
        .replacingOccurrences(of: ",\"isEnabled\":true", with: "")
    expect(!legacyJSON.contains("isEnabled"), "legacy fixture really lacks the key")
    let legacyPayload = try JSONDecoder().decode(ShopPilotPackagePayload.self,
                                                 from: Data(legacyJSON.utf8))
    let legacyManager = ShopPilotPackagePayload.restoreToolpathTree(from: legacyPayload.toolpaths)
    expect(legacyManager.root.children.count == 3, "legacy payload restores 3 ops")
    expect(legacyManager.allNodes.allSatisfy { $0.isEnabled },
           "legacy files without the key decode to ENABLED")

    // AC5: round-trip persists the disabled flag.
    opB.isEnabled = false
    payload.toolpaths = ShopPilotPackagePayload.toolpaths(from: manager)
    let roundTripData = try encoder.encode(payload)
    let decoded = try JSONDecoder().decode(ShopPilotPackagePayload.self, from: roundTripData)
    let restoredManager = ShopPilotPackagePayload.restoreToolpathTree(from: decoded.toolpaths)
    let flags = restoredManager.root.children.map { $0.isEnabled }
    expect(flags == [true, false, true], "round-trip keeps per-op flags ([T,F,T], got \(flags))")
    expect(restoredManager.root.children[1].toolpathResult == gcodeB,
           "round-trip keeps the disabled op's G-code for instant re-enable")
    // And the restored tree filters correctly at send time.
    let restoredFiltered = ToolpathTreeManager.program(from: restoredManager.allNodes)
    expect(restoredFiltered == expectedFiltered,
           "restored tree's send filter matches the live tree's")

    print("ShopPilotVerify2022e: PASS — disabled ops excluded from the send program byte-identically, re-enable restores without regen, recalc unaffected, legacy decode enables, round-trip persists.")
    exit(0)
}

Task { @MainActor in
    do {
        try await run()
    } catch {
        print("ShopPilotVerify2022e: FAIL — threw: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
