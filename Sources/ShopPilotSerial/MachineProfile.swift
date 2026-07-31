import Foundation
import ShopPilotCore

#if canImport(Combine)
import Combine
#endif

// MARK: - Machine Profile Type (for post processor auto-select)

/// Broad classification of machine type used to auto-select the appropriate G-code post processor.
public enum MachineProfileType: String, Codable, Sendable {
    /// GRBL 1.1-compatible controller (most hobby CNC routers).
    case grbl
    /// Universal/other G-code controller.
    case universal
    
    public var displayName: String {
        switch self {
        case .grbl: return "GRBL 1.1"
        case .universal: return "Universal"
        }
    }
    
    /// Auto-select post processor type based on machine profile type.
    public func autoPostProcessorType() -> PostProcessorType {
        switch self {
        case .grbl: return .grbl
        case .universal: return .universal
        }
    }
}

// MARK: - Parity

/// Serial port parity configuration.
public enum Parity: String, Codable, Sendable {
    case none
    case even
    case odd
}

// MARK: - StopBits

/// Serial port stop bit configuration.
public enum StopBits: String, Codable, Sendable {
    case one
    case two
}

// MARK: - SerialConfig

/// Configuration for a serial port connection.
public struct SerialConfig: Codable, Sendable {
    public let baudRate: Int
    public let portName: String
    public let dataBits: Int
    public let parity: Parity
    public let stopBits: StopBits

    public init(
        baudRate: Int,
        portName: String,
        dataBits: Int = 8,
        parity: Parity = .none,
        stopBits: StopBits = .one
    ) {
        self.baudRate = baudRate
        self.portName = portName
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
    }

    // MARK: - Default Simulator Config

    /// Default configuration for the ShopPilot simulator.
    public static var simulator: SerialConfig {
        SerialConfig(
            baudRate: 115200,
            portName: "/dev/tty.simulator",
            parity: .none,
            stopBits: .one
        )
    }
}

// MARK: - MachineProfile

/// A named machine configuration profile with serial settings.
public struct MachineProfile: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public let config: SerialConfig
    public let isSimulator: Bool
    
    /// Machine type classification used to auto-select the appropriate G-code post processor on export.
    public var machineType: MachineProfileType
    
    public var createdAt: Date
    public var updatedAt: Date

    /// Whether this profile has unsaved changes.
    public var isDirty: Bool { false } // Managed by DirtyDocument protocol

    /// Auto-selected post processor type based on the machine's classification.
    /// GRBL machines → GRBL 1.1 post; Universal/other → universal G-code post.
    public var autoPostProcessorType: PostProcessorType {
        machineType.autoPostProcessorType()
    }

    public init(
        id: UUID = UUID(),
        name: String,
        config: SerialConfig,
        isSimulator: Bool = false,
        machineType: MachineProfileType = .grbl,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.isSimulator = isSimulator
        self.machineType = machineType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Default Simulator Profile

    /// The built-in simulator profile for development without hardware.
    public static var simulatorProfile: MachineProfile {
        MachineProfile(
            name: "ShopPilot Simulator",
            config: .simulator,
            isSimulator: true,
            machineType: .grbl // Simulators default to GRBL-compatible output
        )
    }
}

// MARK: - MachineProfileStore

/// Observable store for machine profiles backed by UserDefaults.
public final class MachineProfileStore: ObservableObject {

    // MARK: - Published State

    @Published public var profiles: [MachineProfile] = []

    // MARK: - Private Keys

    private static let profilesKey = "shop_pilot_machine_profiles"
    private static let defaultSimulatorIncludedKey = "shop_pilot_default_simulator_included"

    // MARK: - UserDefaults Accessor

    private var userDefaults: UserDefaults {
        UserDefaults.standard
    }

    // MARK: - Lifecycle

    /// Initialize and load persisted profiles. If no profiles exist, creates the default simulator profile.
    public init() {
        load()
    }

    // MARK: - CRUD Methods

    /// Add a new machine profile. Updates `updatedAt` on all existing profiles to mark them stale.
    @discardableResult
    public func add(_ profile: MachineProfile) -> MachineProfile {
        let updated = profile.updatedAt
        for i in profiles.indices {
            profiles[i].updatedAt = updated
        }
        profiles.append(profile)
        save()
        return profile
    }

    /// Remove a profile by ID. Returns true if a profile was removed.
    @discardableResult
    public func remove(id: UUID) -> Bool {
        let beforeCount = profiles.count
        profiles.removeAll { $0.id == id }
        guard profiles.count < beforeCount else { return false }
        save()
        return true
    }

    /// Update an existing profile by ID. Returns the updated profile, or nil if not found.
    @discardableResult
    public func update(_ profile: MachineProfile) -> MachineProfile? {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return nil }
        profiles[index] = profile
        save()
        return profile
    }

    /// Retrieve a profile by ID.
    public func profile(id: UUID) -> MachineProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Persistence

    /// Save all profiles to UserDefaults as JSON data.
    public func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profiles)
            userDefaults.set(data, forKey: Self.profilesKey)
        } catch {
            // Persistence failure is non-fatal; profiles remain in memory.
        }
    }

    /// Load profiles from UserDefaults. If empty or corrupted, seed the default simulator profile.
    public func load() {
        if let data = userDefaults.data(forKey: Self.profilesKey) {
            if let decoded = try? JSONDecoder().decode([MachineProfile].self, from: data), !decoded.isEmpty {
                profiles = decoded
                return
            }
        }

        // No persisted profiles or corrupted — seed simulator.
        profiles = [MachineProfile.simulatorProfile]
    }
}
