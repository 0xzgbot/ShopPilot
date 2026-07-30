import Foundation

// MARK: - Transport Type

/// Which transport backend to use for machine communication.
public enum TransportType: String, Codable, Sendable {
    /// Simulator transport (fake machine for development/testing).
    case simulator
    /// Real serial port transport (physical CNC machine).
    case serial
    
    public var displayName: String {
        switch self {
        case .simulator: return "Simulator"
        case .serial: return "Serial"
        }
    }
}

// MARK: - Transport Factory Result

/// Result of creating a transport via the factory.
public struct TransportFactoryResult {
    
    /// The created transport (if successful).
    public let transport: MachineTransport?
    
    /// Error message if creation failed.
    public var errorMessage: String? = nil
    
    /// Whether transport creation succeeded.
    public var success: Bool { transport != nil }
}

// MARK: - Transport Factory

/// Factory for creating machine transports based on configuration.
public final class TransportFactory {
    
    /// Create a transport based on the specified type and configuration.
    public static func createTransport(for type: TransportType, config: SerialConfig? = nil) -> TransportFactoryResult {
        switch type {
        case .simulator:
            return createSimulatorTransport()
            
        case .serial:
            let serialConfig = config ?? SerialConfig(baudRate: 115200, portName: "/dev/ttyUSB0", isSimulator: false)
            return createSerialTransport(config: serialConfig)
        }
    }
    
    /// Create a simulator transport for development/testing.
    private static func createSimulatorTransport() -> TransportFactoryResult {
        let transport = SimulatorTransport()
        return TransportFactoryResult(transport: transport)
    }
    
    /// Create a serial transport with the given configuration.
    private static func createSerialTransport(config: SerialConfig) -> TransportFactoryResult {
        // Validate baud rate
        guard [9600, 19200, 38400, 57600, 115200, 250000].contains(config.baudRate) else {
            return TransportFactoryResult(
                transport: nil,
                errorMessage: "Invalid baud rate: \(config.baudRate)"
            )
        }
        
        // For now, serial transport falls back to simulator since RealSerialTransport is in ShopPilotSerial module
        // In a real implementation, this would create a RealSerialTransport instance
        let transport = SimulatorTransport()
        return TransportFactoryResult(transport: transport)
    }
    
    /// List available serial ports for user selection.
    public static func listAvailablePorts() -> [String] {
        var ports: [String] = []
        
        // Scan /dev for serial devices
        let fileManager = FileManager.default
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: "/dev")
            
            for item in contents where item.hasPrefix("cu.") || item.hasPrefix("tty.") {
                ports.append("/dev/\(item)")
            }
        } catch {
            // If we can't scan, return empty list
            print("Warning: Could not enumerate serial ports: \(error.localizedDescription)")
        }
        
        return ports.sorted()
    }
    
    /// Get the default transport type for the current environment.
    public static func defaultTransportType() -> TransportType {
        #if DEBUG
        // In debug builds, prefer simulator for safety
        return .simulator
        #else
        // In release builds, could default to serial if configured
        return .simulator
        #endif
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct TransportFactory_Previews: PreviewProvider {
    static var previews: some View {
        Text("Transport factory is a non-visual component")
    }
}
#endif
