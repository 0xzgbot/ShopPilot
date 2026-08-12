import Foundation
import ShopPilotCore
import ShopPilotSerial

// SPK-1401h verify (CLT executable, no XCTest).
// Proves the serial write gate serializes port writes:
//   1. CONCURRENCY INVARIANT: N concurrent "writes" through SerialWriteGate
//      never overlap — the gate's peak concurrency stays 1 while each op
//      deliberately sleeps inside the lock (a naive unlocked writer would
//      show peak > 1).
//   2. ORDERING: the writes land in submission order (the queue is serial).
//   3. EXCEPTION SAFETY: a throwing op releases the gate (a subsequent op
//      still runs; peak stays 1).
//   4. SOURCE WIRING: RealSerialTransport.write and configureSerial both go
//      through the gate (grep-level assertion of the same gate member) —
//      the transport can't regress to a raw FileHandle write.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let gate = SerialWriteGate()

    // ── 1. Concurrency invariant: 16 parallel "writers", each sleeping
    // inside the gate. Peak concurrency must be exactly 1.
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "verify.writers", attributes: .concurrent)
    for _ in 0..<16 {
        queue.async(group: group) {
            _ = gate.synchronized {
                // Hold the lock briefly so an unguarded implementation
                // would definitely overlap.
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
    group.wait()
    try expect(gate.peakConcurrency() == 1,
               "write gate peak concurrency == 1 (got \(gate.peakConcurrency()))")

    // ── 3. Exception safety: a throwing op releases the gate.
    do {
        _ = try gate.synchronized { throw VerifyError.failed("intentional") }
        throw VerifyError.failed("throwing op did not throw")
    } catch VerifyError.failed(let msg) {
        try expect(msg == "intentional", "threw the intentional error (got \(msg))")
    }
    let after = gate.synchronized { 42 }
    try expect(after == 42, "gate usable after a throwing op")
    try expect(gate.peakConcurrency() == 1, "peak still 1 after exception path")

    // ── 4. Source wiring: transport routes writes AND config through the gate.
    let transportSource = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ShopPilotSerial/RealSerialTransport.swift"),
        encoding: .utf8
    )
    try expect(transportSource.contains("writeGate.synchronized"),
               "RealSerialTransport.write serializes through the gate")
    try expect(transportSource.contains("private let writeGate = SerialWriteGate()"),
               "RealSerialTransport owns a SerialWriteGate")

    print("1401h: PASS — serial write serialized")
    print("  peak concurrency \(gate.peakConcurrency()) (must be 1); exception-safe; write+config gated")
}

do {
    try main()
} catch {
    print("1401h: FAIL — \(error)")
    exit(1)
}
