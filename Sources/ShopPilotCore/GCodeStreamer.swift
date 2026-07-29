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
    
    private var transport: MachineTransport?
    private var isPaused = false
    
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
        totalLines = lines.count
        currentLine = 0
        state = .streaming
        
        for line in lines {
            guard !Task.isCancelled else { return }
            
            // Skip if paused
            while isPaused && !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            guard !Task.isCancelled else { return }
            
            do {
                let command = line + "\n"
                let data = Data(command.utf8)
                try await transport.write(data)
                
                // Wait for "ok" response from GRBL
                try await waitForOk(from: transport)
                
                currentLine += 1
                progress = Double(currentLine) / Double(totalLines)
            } catch {
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                throw error
            }
        }
        
        // Stream complete
        if !Task.isCancelled {
            state = .idle
            progress = 1.0
            currentLine = totalLines
        }
    }
    
    /// Wait for "ok" response from GRBL after sending a command.
    private func waitForOk(from transport: MachineTransport) async throws {
        for await event in transport.events {
            switch event {
            case .dataReceived(let data):
                if let text = String(data: data, encoding: .utf8),
                   text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ok") {
                    return // Got ok response
                }
            case .error(let msg):
                throw NSError(domain: "GCodeStreamer", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
            default:
                continue
            }
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
}
