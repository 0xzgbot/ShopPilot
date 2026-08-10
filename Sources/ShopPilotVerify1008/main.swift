import Foundation
import ShopPilotCore

/// SPK-1008 verify (CLT machine, no XCTest).
/// Proves the MULTI-FILE QUEUE + NETWORK BRIDGE contract:
///   1. QUEUE ENQUEUE: empty queue → first program becomes current.
///   2. QUEUE ADVANCE: marking the current program done moves to the next in
///      order; the last advance exhausts the queue (current = nil) and every
///      program is marked completed.
///   3. QUEUE REMOVE/CLEAR: removing a program re-bases the cursor; clear
///      empties everything.
///   4. QUEUE SUMMARIES: total line count + completed count aggregate.
///   5. BRIDGE CONFIG: NetworkBridgeConfig carries the connection model
///      (address/port/protocol) and maps to a PowerUserConfig; validation
///      rejects bad ports and non-network protocols; store persists bridges.
/// The webcam overlay (Preview-stage camera card, AVFoundation) is a
/// compile-checked surface — hardware capture can't be exercised by CLTs.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // ── 1 + 2. Queue enqueue + advance semantics. ─────────────────────────
    let queue = JobQueue()
    try expect(queue.current == nil, "fresh queue has no current program")

    queue.enqueue(name: "A", gcode: ["G0 X0", "G1 X10"])
    queue.enqueue(name: "B", gcode: ["G0 X20"])
    queue.enqueue(name: "C", gcode: ["G0 X30", "G1 X40", "G1 X50"])
    try expect(queue.current?.name == "A", "first enqueued program is current")
    try expect(queue.programs.count == 3, "three programs queued")

    // Advance A → B.
    let next = queue.advance()
    try expect(next?.name == "B", "advance moves to program B")
    try expect(queue.programs[0].completed, "program A marked completed")
    try expect(queue.current?.name == "B", "current is now B")

    // Advance B → C.
    _ = queue.advance()
    try expect(queue.current?.name == "C", "current is now C")
    try expect(queue.completedCount == 2, "two programs completed")

    // Advance C → exhausted.
    let afterC = queue.advance()
    try expect(afterC == nil, "advancing the last program exhausts the queue")
    try expect(queue.current == nil, "no current after exhaustion")
    try expect(queue.completedCount == 3, "all three completed")

    // ── 3. Remove re-bases the cursor; clear empties. ─────────────────────
    let q2 = JobQueue()
    q2.enqueue(name: "X", gcode: ["G0 X0"])
    q2.enqueue(name: "Y", gcode: ["G0 X1"])
    q2.enqueue(name: "Z", gcode: ["G0 X2"])
    let yID = q2.programs[1].id
    q2.remove(id: yID)
    try expect(q2.programs.count == 2, "remove drops the program")
    try expect(q2.current?.name == "X", "cursor still on X after removing Y")

    // Remove the CURRENT program re-bases to the (new) same index.
    q2.advance() // X done → current Z (index 1 after Y removed)
    try expect(q2.current?.name == "Z", "current is Z after advancing past X")
    let zID = q2.programs[1].id
    q2.remove(id: zID)
    try expect(q2.current == nil, "removing the last current program exhausts the queue")
    q2.clear()
    try expect(q2.programs.isEmpty, "clear empties the queue")

    // ── 4. Summaries. ─────────────────────────────────────────────────────
    let q3 = JobQueue()
    q3.enqueue(name: "P1", gcode: ["a", "b", "c"])
    q3.enqueue(name: "P2", gcode: ["d", "e"])
    try expect(q3.totalLineCount == 5, "total line count aggregates (got \(q3.totalLineCount))")
    try expect(q3.completedCount == 0, "nothing completed yet")

    // ── 5. Network bridge config + store. ─────────────────────────────────
    let bridge = NetworkBridgeConfig(name: "Garage CNC", protocolKind: .ethernet,
                                     address: "192.168.1.50", port: 23, baudRate: 115200)
    try expect(bridge.powerUserConfig.connectionAddress == "192.168.1.50", "bridge maps to PowerUserConfig")
    try expect(bridge.powerUserConfig.connectionProtocol == .ethernet, "protocol mapped")
    try expect(bridge.powerUserConfig.connectionPort == 23, "port mapped")

    let valid = NetworkBridgeConfig.validate(bridge)
    try expect(valid.isValid, "ethernet bridge with valid port passes validation")
    let badPort = NetworkBridgeConfig(name: "B", protocolKind: .ethernet, address: "1.2.3.4", port: 99999)
    try expect(!NetworkBridgeConfig.validate(badPort).isValid, "port > 65535 rejected")
    let usb = NetworkBridgeConfig(name: "U", protocolKind: .usb, address: "1.2.3.4", port: 23)
    try expect(!NetworkBridgeConfig.validate(usb).isValid, "USB protocol rejected for a network bridge")

    // Store persists bridges across instances.
    let defaults = UserDefaults(suiteName: "verify1008-\(UUID().uuidString)")!
    let store = NetworkBridgeStore(defaults: defaults)
    store.upsert(bridge)
    let store2 = NetworkBridgeStore(defaults: defaults)
    try expect(store2.bridges.count == 1, "bridge persists across instances")
    try expect(store2.bridges.first?.address == "192.168.1.50", "bridge fields persist")
    try expect(store2.remove(id: bridge.id), "bridge removal succeeds")
    try expect(store2.bridges.isEmpty, "store empty after removal")

    print("ShopPilotVerify1008: PASS — queue enqueue/advance/remove/clear + summaries, bridge config validation + PowerUserConfig mapping + store persistence")
}

do {
    try main()
} catch {
    print("ShopPilotVerify1008: FAIL — \(error)")
    exit(1)
}
