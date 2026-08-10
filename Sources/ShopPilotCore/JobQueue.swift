import Foundation

// MARK: - Multi-file job queue (SPK-1008)

/// A queue of G-code programs (multi-file jobs): programs are appended, the
/// queue advances one program at a time, and each program's completion moves
/// the queue to the next. The machine stage streams the CURRENT program and
/// calls `advance()` when it completes — a sequential multi-file run without
/// any auto-start semantics (the machine must still be told to run each
/// program explicitly).
public final class JobQueue: ObservableObject {

    public struct QueuedProgram: Identifiable, Codable, Sendable {
        public let id: UUID
        public var name: String
        public var gcode: [String]
        public var completed: Bool

        public init(id: UUID = UUID(), name: String, gcode: [String], completed: Bool = false) {
            self.id = id
            self.name = name
            self.gcode = gcode
            self.completed = completed
        }
    }

    @Published public private(set) var programs: [QueuedProgram] = []
    @Published public private(set) var currentIndex: Int? = nil

    public init() {}

    /// Append a program to the queue (and start it when the queue was empty).
    public func enqueue(name: String, gcode: [String]) {
        programs.append(QueuedProgram(name: name, gcode: gcode))
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    /// The program the queue is currently on (nil = empty).
    public var current: QueuedProgram? {
        guard let currentIndex, programs.indices.contains(currentIndex) else { return nil }
        return programs[currentIndex]
    }

    /// Mark the current program complete and advance to the next. Returns
    /// the next program (nil when the queue is exhausted).
    @discardableResult
    public func advance() -> QueuedProgram? {
        guard let currentIndex, programs.indices.contains(currentIndex) else { return nil }
        programs[currentIndex].completed = true
        let next = currentIndex + 1
        if programs.indices.contains(next) {
            self.currentIndex = next
            return programs[next]
        }
        self.currentIndex = nil
        return nil
    }

    /// Remove a program from the queue by id (re-bases the cursor to the
    /// next uncompleted program when the current one was removed).
    public func remove(id: UUID) {
        guard let idx = programs.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentIndex == idx
        programs.remove(at: idx)
        if wasCurrent {
            // Land on the next program that still needs running (or nil).
            if let nextIdx = programs.indices.first(where: { !programs[$0].completed }) {
                currentIndex = nextIdx
            } else {
                currentIndex = nil
            }
        } else if let currentIndex, idx < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    /// Clear the whole queue.
    public func clear() {
        programs.removeAll()
        currentIndex = nil
    }

    /// Total line count across every program (for queue summaries).
    public var totalLineCount: Int {
        programs.reduce(0) { $0 + $1.gcode.count }
    }

    /// Count of completed programs.
    public var completedCount: Int {
        programs.filter(\.completed).count
    }
}

// MARK: - Network bridge config (SPK-1008)

/// A network bridge: connect to a machine over the network (Ethernet/Wi-Fi)
/// instead of USB. Built on `PowerUserConfig`'s connection model and
/// persisted like the machine profiles. The serial factory keeps a
/// registration hook (`TransportFactory.serialTransportBuilder`) — a network
/// transport would register there; this config carries the address/port the
/// bridge targets.
public struct NetworkBridgeConfig: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var protocolKind: ConnectionProtocol   // .ethernet / .wifi
    public var address: String
    public var port: Int
    public var baudRate: Int
    public var timeoutSeconds: Double

    public init(
        id: UUID = UUID(),
        name: String = "Network Bridge",
        protocolKind: ConnectionProtocol = .ethernet,
        address: String = "192.168.1.50",
        port: Int = 23,
        baudRate: Int = 115200,
        timeoutSeconds: Double = 30.0
    ) {
        self.id = id
        self.name = name
        self.protocolKind = protocolKind
        self.address = address
        self.port = max(1, port)
        self.baudRate = baudRate
        self.timeoutSeconds = max(1.0, timeoutSeconds)
    }

    /// A power-user config view of this bridge (the machine-side model).
    public var powerUserConfig: PowerUserConfig {
        PowerUserConfig(
            machineName: name,
            connectionProtocol: protocolKind,
            connectionAddress: address,
            connectionPort: port,
            baudRate: baudRate,
            timeoutSeconds: timeoutSeconds
        )
    }

    public static func validate(_ bridge: NetworkBridgeConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        if bridge.name.isEmpty { errors.append("Name is required") }
        if bridge.address.isEmpty { errors.append("Address is required") }
        if bridge.port < 1 || bridge.port > 65535 { errors.append("Port must be 1–65535") }
        if bridge.protocolKind == .usb || bridge.protocolKind == .bluetooth {
            errors.append("Network bridge requires Ethernet or Wi-Fi")
        }
        return (errors.isEmpty, errors)
    }
}

/// Persisted network-bridge store (UserDefaults JSON).
public final class NetworkBridgeStore: ObservableObject {

    @Published public private(set) var bridges: [NetworkBridgeConfig]

    private let defaults: UserDefaults
    private static let storageKey = "shop_pilot_network_bridges_v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([NetworkBridgeConfig].self, from: data) {
            self.bridges = decoded
        } else {
            self.bridges = []
        }
    }

    public func upsert(_ bridge: NetworkBridgeConfig) {
        if let idx = bridges.firstIndex(where: { $0.id == bridge.id }) {
            bridges[idx] = bridge
        } else {
            bridges.append(bridge)
        }
        save()
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        guard let idx = bridges.firstIndex(where: { $0.id == id }) else { return false }
        bridges.remove(at: idx)
        save()
        return true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bridges) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
