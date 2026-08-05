import Foundation
import Combine

// MARK: - Console Message

/// A single message in the machine console.
public struct ConsoleMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let type: ConsoleMessageType

    public enum ConsoleMessageType: String, Codable, Sendable {
        /// User input (sent to machine).
        case sent
        /// Machine output (received from machine).
        case received
        /// System message.
        case system
    }

    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String, type: ConsoleMessageType) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.type = type
    }
}

// MARK: - Console Log

/// Thread-safe console message buffer.
///
/// SPK-UI601: appending synchronously inside another Combine `@Published`
/// send deadlocks the main thread — Combine's subject `send` is not
/// re-entrant, and the machine event stream can deliver a message while a
/// view update from a different `@Published` change is in flight (observed:
/// Stop Stream during a soft-limit alarm froze the app in
/// `PublishedSubject.send`). All mutations are therefore deferred to the
/// main queue: ordering is preserved (main queue is FIFO), and no mutation
/// ever runs inside another send.
public final class ConsoleLog: ObservableObject {
    @Published public private(set) var messages: [ConsoleMessage] = []
    public let maxMessages: Int

    public init(maxMessages: Int = 500) {
        self.maxMessages = maxMessages
    }

    /// Append a message. Never mutates `messages` synchronously.
    public func append(_ message: ConsoleMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.messages.append(message)
            while self.messages.count > self.maxMessages {
                self.messages.removeFirst()
            }
        }
    }

    /// Append a system message (internal for SwiftUI view access).
    public func appendSystem(_ text: String) {
        append(ConsoleMessage(text: text, type: .system))
    }

    /// Clear the console. Never mutates `messages` synchronously.
    public func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.messages.removeAll()
        }
    }
}
