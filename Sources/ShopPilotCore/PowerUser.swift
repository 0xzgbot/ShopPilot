import Foundation

// MARK: - Power User & Distribution

// Distribution channel.
public enum DistributionChannel: String, Codable, Sendable {
    case directUSB
    case network
    case cloud
    case file
}

// Connection protocol.
public enum ConnectionProtocol: String, Codable, Sendable {
    case usb
    case ethernet
    case wifi
    case bluetooth
}

// Power user configuration.
public struct PowerUserConfig: Codable, Sendable {
    public var machineName: String
    public var machineID: String
    public var connectionProtocol: ConnectionProtocol
    public var connectionAddress: String
    public var connectionPort: Int
    public var baudRate: Int
    public var autoConnect: Bool
    public var autoReconnect: Bool
    public var maxRetries: Int
    public var timeoutSeconds: Double
    public var telemetryEnabled: Bool
    public var loggingLevel: LoggingLevel
    public var advancedMode: Bool
    public var debugMode: Bool
    
    public init(
        machineName: String = "CNC Machine",
        machineID: String = "",
        connectionProtocol: ConnectionProtocol = .usb,
        connectionAddress: String = "",
        connectionPort: Int = 0,
        baudRate: Int = 115200,
        autoConnect: Bool = true,
        autoReconnect: Bool = true,
        maxRetries: Int = 3,
        timeoutSeconds: Double = 30.0,
        telemetryEnabled: Bool = false,
        loggingLevel: LoggingLevel = .info,
        advancedMode: Bool = false,
        debugMode: Bool = false
    ) {
        self.machineName = machineName
        self.machineID = machineID
        self.connectionProtocol = connectionProtocol
        self.connectionAddress = connectionAddress
        self.connectionPort = connectionPort
        self.baudRate = baudRate
        self.autoConnect = autoConnect
        self.autoReconnect = autoReconnect
        self.maxRetries = maxRetries
        self.timeoutSeconds = max(1.0, timeoutSeconds)
        self.telemetryEnabled = telemetryEnabled
        self.loggingLevel = loggingLevel
        self.advancedMode = advancedMode
        self.debugMode = debugMode
    }
}

// Logging level.
public enum LoggingLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
    case none
}

// Export format.
public enum ExportFormat: String, Codable, Sendable {
    case gcode
    case hpgl
    case svg
    case pdf
    case dxf
    case stl
    case step
    case json
    case csv
    case custom
}

// Export configuration.
public struct ExportConfig: Codable, Sendable {
    public var format: ExportFormat
    public var includeHeader: Bool
    public var includeComments: Bool
    public var units: String
    public var precision: Int
    public var outputDirectory: String
    public var fileName: String
    public var overwrite: Bool
    
    public init(
        format: ExportFormat = .gcode,
        includeHeader: Bool = true,
        includeComments: Bool = true,
        units: String = "mm",
        precision: Int = 3,
        outputDirectory: String = "",
        fileName: String = "",
        overwrite: Bool = false
    ) {
        self.format = format
        self.includeHeader = includeHeader
        self.includeComments = includeComments
        self.units = units
        self.precision = max(0, min(10, precision))
        self.outputDirectory = outputDirectory
        self.fileName = fileName
        self.overwrite = overwrite
    }
}

// Export result.
public struct ExportResult: Codable, Sendable {
    public var success: Bool
    public var outputPath: String
    public var fileSizeBytes: Int
    public var format: ExportFormat
    public var errorMessage: String?
    
    public init(
        success: Bool,
        outputPath: String = "",
        fileSizeBytes: Int = 0,
        format: ExportFormat = .gcode,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.outputPath = outputPath
        self.fileSizeBytes = fileSizeBytes
        self.format = format
        self.errorMessage = errorMessage
    }
}

// Import format.
public enum ImportFormat: String, Codable, Sendable {
    case svg
    case dxf
    case stl
    case step
    case png
    case jpg
    case json
    case csv
    case custom
}

// Import configuration.
public struct ImportConfig: Codable, Sendable {
    public var format: ImportFormat
    public var scale: Double
    public var originX: Double
    public var originY: Double
    public var flipY: Bool
    public var convertToCurves: Bool
    public var mergeOverlapping: Bool
    public var simplifyTolerance: Double
    
    public init(
        format: ImportFormat = .svg,
        scale: Double = 1.0,
        originX: Double = 0.0,
        originY: Double = 0.0,
        flipY: Bool = false,
        convertToCurves: Bool = true,
        mergeOverlapping: Bool = true,
        simplifyTolerance: Double = 0.01
    ) {
        self.format = format
        self.scale = max(0.01, scale)
        self.originX = originX
        self.originY = originY
        self.flipY = flipY
        self.convertToCurves = convertToCurves
        self.mergeOverlapping = mergeOverlapping
        self.simplifyTolerance = max(0.0, simplifyTolerance)
    }
}

// Import result.
public struct ImportResult: Codable, Sendable {
    public var success: Bool
    public var shapeCount: Int
    public var totalPoints: Int
    public var boundingBox: BoundingBox3D
    public var errorMessage: String?
    
    public init(
        success: Bool,
        shapeCount: Int = 0,
        totalPoints: Int = 0,
        boundingBox: BoundingBox3D = BoundingBox3D(),
        errorMessage: String? = nil
    ) {
        self.success = success
        self.shapeCount = shapeCount
        self.totalPoints = totalPoints
        self.boundingBox = boundingBox
        self.errorMessage = errorMessage
    }
}

// Package format for distribution.
public enum PackageFormat: String, Codable, Sendable {
    case dmg
    case zip
    case tarGz
    case appBundle
    case standalone
}

// Package configuration.
public struct PackageConfig: Codable, Sendable {
    public var format: PackageFormat
    public var includeSources: Bool
    public var includeDocumentation: Bool
    public var includeExamples: Bool
    public var includePlugins: Bool
    public var version: String
    public var buildNumber: Int
    public var outputDirectory: String
    
    public init(
        format: PackageFormat = .dmg,
        includeSources: Bool = false,
        includeDocumentation: Bool = true,
        includeExamples: Bool = true,
        includePlugins: Bool = false,
        version: String = "1.0.0",
        buildNumber: Int = 1,
        outputDirectory: String = ""
    ) {
        self.format = format
        self.includeSources = includeSources
        self.includeDocumentation = includeDocumentation
        self.includeExamples = includeExamples
        self.includePlugins = includePlugins
        self.version = version
        self.buildNumber = max(1, buildNumber)
        self.outputDirectory = outputDirectory
    }
}

// Package result.
public struct PackageResult: Codable, Sendable {
    public var success: Bool
    public var outputPath: String
    public var fileSizeBytes: Int
    public var checksum: String
    public var errorMessage: String?
    
    public init(
        success: Bool,
        outputPath: String = "",
        fileSizeBytes: Int = 0,
        checksum: String = "",
        errorMessage: String? = nil
    ) {
        self.success = success
        self.outputPath = outputPath
        self.fileSizeBytes = fileSizeBytes
        self.checksum = checksum
        self.errorMessage = errorMessage
    }
}

// Telemetry event type.
public enum TelemetryEventType: String, Codable, Sendable {
    case jobStarted
    case jobCompleted
    case jobFailed
    case machineConnected
    case machineDisconnected
    case errorOccurred
    case configChanged
    case exportCompleted
    case importCompleted
    case packageCreated
}

// Telemetry event data.
public struct TelemetryEventData: Codable, Sendable {
    public var machineID: String
    public var data: [String: String]
    public var duration: Double
    
    public init(machineID: String = "", data: [String: String] = [:], duration: Double = 0.0) {
        self.machineID = machineID
        self.data = data
        self.duration = duration
    }
}

// Telemetry event.
public struct TelemetryEvent: Codable, Sendable {
    public let id: UUID
    public let eventType: TelemetryEventType
    public let timestamp: Date
    public var eventData: TelemetryEventData
    
    public init(
        id: UUID = UUID(),
        eventType: TelemetryEventType,
        timestamp: Date = Date(),
        eventData: TelemetryEventData = TelemetryEventData()
    ) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.eventData = eventData
    }
}

// MARK: - PowerUserManager

// Manages power user configurations and operations.
public final class PowerUserManager {
    
    // Creates a power user config.
    public static func createConfig(
        machineName: String,
        connectionProtocol: ConnectionProtocol = .usb,
        connectionAddress: String = "",
        connectionPort: Int = 0,
        baudRate: Int = 115200
    ) -> PowerUserConfig {
        PowerUserConfig(
            machineName: machineName,
            connectionProtocol: connectionProtocol,
            connectionAddress: connectionAddress,
            connectionPort: connectionPort,
            baudRate: baudRate
        )
    }
    
    // Validates a power user config.
    public static func validate(_ config: PowerUserConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.machineName.isEmpty { errors.append("Machine name is required") }
        if config.connectionAddress.isEmpty && config.connectionProtocol != .usb {
            errors.append("Connection address is required for network connections")
        }
        if config.connectionPort < 0 || config.connectionPort > 65535 {
            errors.append("Connection port must be 0-65535")
        }
        if config.baudRate < 9600 { errors.append("Baud rate must be at least 9600") }
        if config.maxRetries < 0 { errors.append("Max retries cannot be negative") }
        if config.timeoutSeconds < 1.0 { errors.append("Timeout must be at least 1 second") }
        
        return (errors.isEmpty, errors)
    }
    
    // Creates an export config.
    public static func createExportConfig(
        format: ExportFormat = .gcode,
        units: String = "mm",
        precision: Int = 3
    ) -> ExportConfig {
        ExportConfig(format: format, units: units, precision: precision)
    }
    
    // Creates an import config.
    public static func createImportConfig(
        format: ImportFormat = .svg,
        scale: Double = 1.0
    ) -> ImportConfig {
        ImportConfig(format: format, scale: scale)
    }
    
    // Validates export config.
    public static func validateExport(_ config: ExportConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.precision < 0 || config.precision > 10 { errors.append("Precision must be 0-10") }
        if config.units.isEmpty { errors.append("Units are required") }
        
        return (errors.isEmpty, errors)
    }
    
    // Validates import config.
    public static func validateImport(_ config: ImportConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.scale <= 0 { errors.append("Scale must be positive") }
        if config.simplifyTolerance < 0 { errors.append("Simplify tolerance cannot be negative") }
        
        return (errors.isEmpty, errors)
    }
    
    // Creates a package config.
    public static func createPackageConfig(
        format: PackageFormat = .dmg,
        version: String = "1.0.0"
    ) -> PackageConfig {
        PackageConfig(format: format, version: version)
    }
    
    // Validates package config.
    public static func validatePackage(_ config: PackageConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Basic semver check
        let components = config.version.split(separator: ".")
        if components.count != 3 { errors.append("Version must be in format X.Y.Z") }
        
        return (errors.isEmpty, errors)
    }
    
    // Creates a telemetry event.
    public static func createTelemetryEvent(
        eventType: TelemetryEventType,
        machineID: String,
        data: [String: String] = [:],
        duration: Double = 0.0
    ) -> TelemetryEvent {
        let eventData = TelemetryEventData(machineID: machineID, data: data, duration: duration)
        return TelemetryEvent(eventType: eventType, eventData: eventData)
    }
}
