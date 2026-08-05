import Foundation
import Combine
import ShopPilotCore

// SPK-UI601 verification — console message append must never deadlock the
// main thread on a re-entrant Combine/@Published send.
//
// Observed bug: pressing Stop Stream while the sim was in a soft-limit
// alarm froze the app — the alarm event-stream message append landed inside
// the view update triggered by `isStreamingJob = false`, and Combine's
// subject send is not re-entrant (deadlock in PublishedSubject.send).
// ConsoleLog defers all mutations to the main queue; these tests prove the
// deadlock class is gone and ordering/trim/clear still behave.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

/// Drain the main queue so deferred appends land.
func drainMain(_ seconds: TimeInterval = 0.4) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Test 1 — THE SPK-UI601 deadlock class: a subscriber re-enters append
/// during the send. Pre-fix this hangs in PublishedSubject.send; post-fix
/// the append defers and returns immediately.
func testReentrantAppendDoesNotDeadlock() throws {
    let log = ConsoleLog()
    var subscriberFires = 0
    let sub = log.$messages.sink { messages in
        subscriberFires += 1
        if messages.count == 1 {
            log.append(ConsoleMessage(text: "re-entrant", type: .system))
        }
    }
    log.append(ConsoleMessage(text: "first", type: .system)) // must return
    drainMain()
    try expect(log.messages.count == 2,
               "re-entrant append lost: \(log.messages.map(\.text))")
    try expect(log.messages.map(\.text) == ["first", "re-entrant"],
               "order wrong: \(log.messages.map(\.text))")
    // @Published.$messages delivers the current value on subscription, so:
    // 1 initial + 2 append sends = 3 subscriber fires (never more — the
    // re-entrant append must not loop).
    try expect(subscriberFires == 3, "subscriber fired \(subscriberFires) times")
    _ = sub
    print("  [1/5] re-entrant @Published append returns (no deadlock) PASS")
}

/// Test 2 — FIFO ordering across a burst of appends.
func testOrderingPreserved() throws {
    let log = ConsoleLog()
    log.append(ConsoleMessage(text: "A", type: .system))
    log.append(ConsoleMessage(text: "B", type: .received))
    log.append(ConsoleMessage(text: "C", type: .system))
    drainMain()
    try expect(log.messages.map(\.text) == ["A", "B", "C"],
               "FIFO order broken: \(log.messages.map(\.text))")
    print("  [2/5] FIFO ordering preserved PASS")
}

/// Test 3 — trim to max keeps the newest, drops the oldest.
func testTrim() throws {
    let log = ConsoleLog(maxMessages: 5)
    for i in 0..<12 {
        log.append(ConsoleMessage(text: "m\(i)", type: .system))
    }
    drainMain()
    try expect(log.messages.count == 5, "trim to max failed: \(log.messages.count)")
    try expect(log.messages.first?.text == "m7",
               "oldest not dropped: \(log.messages.first?.text ?? "nil")")
    try expect(log.messages.last?.text == "m11", "newest lost: \(log.messages.last?.text ?? "nil")")
    print("  [3/5] trim to max PASS")
}

/// Test 4 — clear empties the buffer.
func testClear() throws {
    let log = ConsoleLog()
    log.append(ConsoleMessage(text: "x", type: .system))
    drainMain()
    try expect(log.messages.count == 1, "append before clear failed")
    log.clear()
    drainMain()
    try expect(log.messages.isEmpty, "clear failed: \(log.messages.count) remain")
    print("  [4/5] clear PASS")
}

/// Test 5 — alarm-path burst: many event-stream appends interleaved with a
/// second @Published-style change (isStreamingJob analog) never block.
func testAlarmPathBurst() throws {
    let log = ConsoleLog()
    let flag = CurrentValueSubject<Bool, Never>(true)
    let flagSub = flag.sink { _ in
        log.append(ConsoleMessage(text: "flag", type: .system))
    }
    let sub = log.$messages.sink { _ in } // view analog
    for i in 0..<40 {
        log.append(ConsoleMessage(text: "evt\(i)", type: .received))
    }
    flag.send(false) // interleaved state change during the burst
    drainMain()
    // CurrentValueSubject delivers on subscription: "flag" is queued once at
    // subscribe and once at send(false) — 40 evt + 2 flag = 42.
    try expect(log.messages.count == 42, "burst count: \(log.messages.count)")
    try expect(log.messages[1].text == "evt0" && log.messages[40].text == "evt39",
               "evt order wrong: \(log.messages.prefix(3).map(\.text))...\(log.messages.suffix(2).map(\.text))")
    try expect(log.messages.first?.text == "flag" && log.messages.last?.text == "flag",
               "flag bookends wrong: \(log.messages.first?.text ?? "nil")...\(log.messages.last?.text ?? "nil")")
    _ = sub; _ = flagSub
    print("  [5/5] alarm-path burst interleave PASS")
}

do {
    try testReentrantAppendDoesNotDeadlock()
    try testOrderingPreserved()
    try testTrim()
    try testClear()
    try testAlarmPathBurst()
    print("ShopPilotVerifyUI601: PASS — console append never deadlocks on re-entrant @Published send (SPK-UI601)")
} catch {
    print("ShopPilotVerifyUI601: FAIL — \(error)")
    exit(1)
}
