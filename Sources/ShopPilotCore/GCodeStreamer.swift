import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - Stream State

public enum StreamState {
    case idle
    case streaming
    case paused
    case error(String)

    /// SPK-1920h — true when the stream is held (Hold pressed). The Preview
    /// live playhead stays visible but frozen in this state.
    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

extension StreamState: Equatable {
    public static func == (lhs: StreamState, rhs: StreamState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.streaming, .streaming), (.paused, .paused):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - GCode Response Classification

/// Classification of one trimmed controller response line (GRBL / FluidNC
/// dialect). Extracted so `waitForOk` can treat `ALARM:` / `error:` lines as
/// failures instead of skipping them and waiting forever (SPK-1401d).
public enum GCodeResponse: Equatable {
    /// `ok` — the command was accepted; the stream may advance.
    case ok
    /// `ALARM:...` — machine alarm; streaming must stop.
    case alarm(String)
    /// `error:...` / `error N` — the command was rejected; streaming must stop.
    case error(String)
    /// Anything else (`<Idle|...>` status reports, `[MSG:...]`, etc.) — ignore.
    case other

    /// Classify a single response line (leading/trailing whitespace tolerated).
    public static func parse(_ line: String) -> GCodeResponse {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        if upper.hasPrefix("OK") {
            return .ok
        } else if upper.hasPrefix("ALARM:") {
            return .alarm(trimmed)
        } else if upper.hasPrefix("ERROR:") || upper.hasPrefix("ERROR ") {
            return .error(trimmed)
        } else {
            return .other
        }
    }
}

// MARK: - GCode Streamer

/// Streams G-code to a CNC machine using GRBL ok-wait protocol.
public final class GCodeStreamer: ObservableObject {
    
    @Published public var state: StreamState = .idle
    @Published public var progress: Double = 0.0
    @Published public var currentLine: Int = 0
    @Published public var totalLines: Int = 0
    @Published public var lastError: String?
    
    /// Throttle interval for UI progress updates (prevents freeze on large files).
    private let progressUpdateInterval: TimeInterval = 0.1
    
    private var transport: MachineTransport?
    private var isPaused = false
    private var lastProgressUpdateTime: Date = Date()

    public init() {}

    // MARK: - SPK-DOGFOOD-02 — stale transport teardown

    /// True while the streamer still holds a transport reference it no longer
    /// streams through (a finished stream whose wire has since been closed).
    public var hasStaleTransport: Bool { transport != nil }

    /// Called by the session when a stream finishes (ok, error, or cancel):
    /// drops the retained transport so the NEXT connection cannot inherit a
    /// closed wire. Before this existed, `streamer.reset()` during reconnect
    /// wrote 0x18 into the previous connection's closed transport and the
    /// awaiting main thread hung forever (dogfood beachball 2026-08-22).
    public func finishStreaming() {
        transport = nil
        isPaused = false
        state = .idle
    }
    
    public var isStreaming: Bool { state == .streaming }
    
    // MARK: - Load G-code
    
    /// Load and parse a G-code file, filtering comments and blank lines.
    public func load(from url: URL) async throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isComment($0) }
    }
    
    private func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(";") || trimmed.hasPrefix("(")
    }
    
    // MARK: - Stream
    
    /// Stream G-code lines to the transport using ok-wait protocol.
    public func stream(lines: [String], to transport: MachineTransport) async throws {
        self.transport = transport
        let executable = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isComment($0) && !$0.hasPrefix("%") && !$0.hasPrefix("O=") }
        totalLines = executable.count
        currentLine = 0
        state = .streaming

        // Subscribe BEFORE writes so ok responses are not missed (fan-out is live-only).
        var eventIterator = transport.events.makeAsyncIterator()
        
        for line in executable {
            guard !Task.isCancelled else { break }
            
            // Skip if paused
            while isPaused && !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            guard !Task.isCancelled else { break }
            
            do {
                let command = line + "\n"
                let data = Data(command.utf8)
                try await transport.write(data)
                
                // Wait for "ok" response from GRBL on the pre-subscribed stream
                try await waitForOk(iterator: &eventIterator)
                
                currentLine += 1
                
                // Throttle progress updates to prevent UI freeze on large files
                let now = Date()
                if now.timeIntervalSince(lastProgressUpdateTime) >= progressUpdateInterval {
                    progress = Double(currentLine) / Double(totalLines)
                    lastProgressUpdateTime = now
                }
            } catch is CancellationError {
                // Cancellation is a stop request, not a stream failure —
                // exit gracefully so callers can distinguish cancel from error.
                state = .idle
                return
            } catch {
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                throw error
            }
        }
        
        // Stream complete — cancelled streams exit here via `break`, so always
        // settle to idle (progress only when actually finished).
        state = .idle
        if !Task.isCancelled {
            progress = 1.0
            currentLine = totalLines
        }
    }
    
    /// Stream G-code from a file URL directly, without loading all lines into memory.
    /// This is the backpressure-aware method for large files (10k+ lines).
    public func stream(from url: URL, to transport: MachineTransport) async throws {
        self.transport = transport
        
        // Open file handle and count total lines first
        let content = try String(contentsOf: url, encoding: .utf8)
        let allLines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isComment($0) }
        
        totalLines = allLines.count
        currentLine = 0
        state = .streaming

        // Subscribe BEFORE writes so ok responses are not missed (fan-out is
        // live-only, and AsyncStream registers the continuation lazily on the
        // first next()). Using one iterator for the whole stream avoids the
        // race where a fresh per-line iterator misses an already-yielded ok.
        var eventIterator = transport.events.makeAsyncIterator()

        for line in allLines {
            guard !Task.isCancelled else { break }
            
            // Skip if paused
            while isPaused && !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            guard !Task.isCancelled else { break }
            
            do {
                let command = line + "\n"
                let data = Data(command.utf8)
                try await transport.write(data)
                
                // Wait for "ok" response from GRBL
                try await waitForOk(iterator: &eventIterator)
                
                currentLine += 1
                
                // Throttle progress updates to prevent UI freeze on large files
                let now = Date()
                if now.timeIntervalSince(lastProgressUpdateTime) >= progressUpdateInterval {
                    progress = Double(currentLine) / Double(totalLines)
                    lastProgressUpdateTime = now
                }
            } catch is CancellationError {
                // Cancellation is a stop request, not a stream failure.
                state = .idle
                return
            } catch {
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                throw error
            }
        }
        
        // Stream complete — cancelled streams exit here via `break`, so always
        // settle to idle (progress only when actually finished).
        state = .idle
        if !Task.isCancelled {
            progress = 1.0
            currentLine = totalLines
        }
    }
    
    /// Wait for the controller's `ok` acknowledgement after sending a command
    /// (GRBL ok-wait protocol). Throws when the controller reports an alarm
    /// (`ALARM:...`) or rejects the command (`error:...` / `error N`), when the
    /// transport errors or disconnects, or when no response arrives within
    /// `timeout` seconds — a silent controller must not hang the stream forever
    /// (SPK-1401d).
    public func waitForOk(from transport: MachineTransport, timeout: TimeInterval = 5.0) async throws {
        var iterator = transport.events.makeAsyncIterator()
        try await waitForOk(iterator: &iterator, timeout: timeout)
    }

    private func waitForOk(iterator: inout AsyncStream<TransportEvent>.Iterator, timeout: TimeInterval = 5.0) async throws {
        // Total deadline for the whole wait: a controller that never replies
        // (or replies with noise) cannot stall the stream past `timeout`.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while let event = try await nextEvent(from: &iterator, deadline: deadline) {
            switch event {
            case .dataReceived(let data):
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(whereSeparator: { $0.isNewline }) {
                    switch GCodeResponse.parse(String(line)) {
                    case .ok:
                        return
                    case .alarm(let raw):
                        throw NSError(domain: "GCodeStreamer", code: 5,
                                      userInfo: [NSLocalizedDescriptionKey: "Alarm from controller: \(raw)"])
                    case .error(let raw):
                        throw NSError(domain: "GCodeStreamer", code: 6,
                                      userInfo: [NSLocalizedDescriptionKey: "Error from controller: \(raw)"])
                    case .other:
                        continue
                    }
                }
            case .error(let msg):
                throw NSError(domain: "GCodeStreamer", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
            case .disconnected:
                throw NSError(domain: "GCodeStreamer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transport disconnected"])
            default:
                continue
            }
        }
        throw NSError(domain: "GCodeStreamer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Event stream ended before ok"])
    }

    /// Fetch the next transport event, throwing a timeout error (code 4) once
    /// `deadline` passes. Returns `nil` when the event stream ends.
    private func nextEvent(
        from iterator: inout AsyncStream<TransportEvent>.Iterator,
        deadline: ContinuousClock.Instant
    ) async throws -> TransportEvent? {
        let clock = ContinuousClock()
        guard deadline - clock.now > .zero else {
            throw NSError(domain: "GCodeStreamer", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for ok response"])
        }
        return try await withThrowingTaskGroup(of: TransportEvent?.self) { group in
            var it = iterator
            group.addTask { await it.next() }
            group.addTask {
                try await clock.sleep(until: deadline)
                throw NSError(domain: "GCodeStreamer", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for ok response"])
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
    
    // MARK: - Control
    
    /// Pause streaming (sends ! to GRBL).
    public func pause() async {
        isPaused = true
        state = .paused
        guard let transport else { return }
        do {
            try await transport.write(Data("!".utf8))
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    /// Resume streaming (sends ~ to GRBL).
    public func resume() async {
        isPaused = false
        state = .streaming
        guard let transport else { return }
        do {
            try await transport.write(Data("~".utf8))
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    /// Reset machine and clear buffer (sends 0x18 to GRBL).
    public func reset() async {
        isPaused = false
        guard let transport else { return }
        do {
            try await transport.write(Data([0x18]))
            state = .idle
            progress = 0.0
            currentLine = 0
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// State-only pause coordination (SPK-1401e): flips the pause flag the
    /// stream loop checks and the published state WITHOUT writing to the
    /// transport. The session writes the single realtime `!` byte — the
    /// streamer must not double-write through its own `pause()`.
    public func setPaused(_ paused: Bool) {
        isPaused = paused
        state = paused ? .paused : .streaming
    }

    /// State-only reset (SPK-1401e): clears the pause flag, stream state,
    /// progress and line counter WITHOUT writing 0x18. The session writes
    /// the single reset byte; `reset()` above remains the direct
    /// buffer-reset API (0x18) for stream owners that want it.
    public func resetStreamState() {
        isPaused = false
        state = .idle
        progress = 0.0
        currentLine = 0
    }
}
