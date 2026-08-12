import Foundation
import ShopPilotCore

// SPK-1401d verify (CLT executable, no XCTest).
// Proves GCodeStreamer.waitForOk:
//   (a) a normal 'ok' completes the wait;
//   (b) 'ALARM:1' throws an alarm failure (code 5);
//   (c) 'error:24' and 'error 24' throw a command-rejected failure (code 6);
//   (d) a silent transport times out (code 4) instead of hanging forever —
//       an injected short timeout keeps the CLT fast.
// Also checks the GCodeResponse.parse classifier directly.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

// MARK: - Scripted transport

/// Fake transport that replays scripted response lines shortly after the
/// streamer subscribes, so an ok-wait that subscribes after `write` never
/// misses a response. An empty script is a silent controller: the event
/// stream stays open but nothing ever arrives.
final class ScriptedTransport: MachineTransport, @unchecked Sendable {
    private let script: [String]

    init(_ script: [String]) { self.script = script }

    var events: AsyncStream<TransportEvent> {
        AsyncStream { continuation in
            let lines = self.script
            Task {
                for line in lines {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continuation.yield(.dataReceived(Data((line + "\n").utf8)))
                }
            }
        }
    }

    func open(config: SerialConfig) async throws {}
    func close() async {}
    func write(_ data: Data) async throws {}
    func read() async throws -> Data { Data() }
}

func main() throws {
    let streamer = GCodeStreamer()

    // (a) normal 'ok' completes the wait
    try awaitBlocking {
        try await streamer.waitForOk(from: ScriptedTransport(["ok"]), timeout: 2.0)
    }

    // (b) 'ALARM:1' throws
    var threw = false
    do {
        try awaitBlocking {
            try await streamer.waitForOk(from: ScriptedTransport(["ALARM:1"]), timeout: 2.0)
        }
    } catch let error as NSError {
        threw = true
        try expect(error.domain == "GCodeStreamer" && error.code == 5,
                   "ALARM:1 should surface as streamer alarm error, got \(error.domain)/\(error.code): \(error.localizedDescription)")
    } catch {
        threw = true
        try expect(false, "ALARM:1 threw unexpected error type: \(error)")
    }
    try expect(threw, "ALARM:1 should throw")

    // (c) 'error:24' and 'error 24' both throw
    for bad in ["error:24", "error 24"] {
        threw = false
        do {
            try awaitBlocking {
                try await streamer.waitForOk(from: ScriptedTransport([bad]), timeout: 2.0)
            }
        } catch let error as NSError {
            threw = true
            try expect(error.domain == "GCodeStreamer" && error.code == 6,
                       "'\(bad)' should surface as streamer error response, got \(error.domain)/\(error.code): \(error.localizedDescription)")
        } catch {
            threw = true
            try expect(false, "'\(bad)' threw unexpected error type: \(error)")
        }
        try expect(threw, "'\(bad)' should throw")
    }

    // Classifier direct checks (pure function)
    try expect(GCodeResponse.parse("ok") == .ok, "parse('ok') should be .ok")
    try expect(GCodeResponse.parse("ALARM:1") == .alarm("ALARM:1"), "parse('ALARM:1') should be .alarm")
    try expect(GCodeResponse.parse("error:24") == .error("error:24"), "parse('error:24') should be .error")
    try expect(GCodeResponse.parse("error 24") == .error("error 24"), "parse('error 24') should be .error")
    try expect(GCodeResponse.parse("<Idle|MPos:0,0,0>") == .other, "status reports are not failures")
    try expect(GCodeResponse.parse("") == .other, "empty line is not a failure")

    // (d) silent transport times out with the injected short timeout
    let start = Date()
    threw = false
    do {
        try awaitBlocking {
            try await streamer.waitForOk(from: ScriptedTransport([]), timeout: 0.2)
        }
    } catch let error as NSError {
        threw = true
        try expect(error.domain == "GCodeStreamer" && error.code == 4,
                   "silence should surface as streamer timeout, got \(error.domain)/\(error.code): \(error.localizedDescription)")
    } catch {
        threw = true
        try expect(false, "silent transport threw unexpected error type: \(error)")
    }
    try expect(threw, "silent transport should time out")
    let elapsed = Date().timeIntervalSince(start)
    try expect(elapsed < 3.0, "timeout must fire promptly, took \(elapsed)s")

    print("1401d: PASS — alarm/error/timeout")
    print("  (a) 'ok' completes, (b) 'ALARM:1' throws, (c) 'error:24'/'error 24' throw, (d) silent transport times out in \(String(format: "%.2f", elapsed))s")
}

// Minimal async runner: keep the verify main synchronous on CLT.
private func awaitBlocking<T>(_ op: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task {
        do { result = .success(try await op()) }
        catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result!.get()
}

do {
    try main()
} catch {
    fputs("1401d: FAIL — \(error)\n", stderr)
    exit(1)
}
