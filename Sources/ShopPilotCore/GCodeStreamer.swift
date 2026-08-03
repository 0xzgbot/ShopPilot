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
    
    /// Wait for "ok" response from GRBL after sending a command.
    private func waitForOk(from transport: MachineTransport) async throws {
        var iterator = transport.events.makeAsyncIterator()
        try await waitForOk(iterator: &iterator)
    }

    private func waitForOk(iterator: inout AsyncStream<TransportEvent>.Iterator) async throws {
        while let event = await iterator.next() {
            switch event {
            case .dataReceived(let data):
                if let text = String(data: data, encoding: .utf8),
                   text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: { $0.isNewline })
                    .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ok") }) {
                    return
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
}
