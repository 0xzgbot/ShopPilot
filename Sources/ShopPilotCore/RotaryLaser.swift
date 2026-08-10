import Foundation

// MARK: - Rotary, Laser, Specialty

// Rotary axis mode.
public enum RotaryMode: String, Codable, Sendable {
    case engrave
    case cylinder
    case sphere
    case custom
}

// Rotary direction.
public enum RotaryDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise
}

// Rotary configuration.
public struct RotaryConfig: Codable, Sendable {
    public var mode: RotaryMode
    public var diameter: Double
    public var axisLength: Double
    public var direction: RotaryDirection
    public var zeroAngle: Double
    public var startAngle: Double
    public var endAngle: Double
    public var wrapEnabled: Bool
    public var wrapOverlap: Double
    public var tension: Double
    
    public init(
        mode: RotaryMode = .cylinder,
        diameter: Double = 50.0,
        axisLength: Double = 100.0,
        direction: RotaryDirection = .clockwise,
        zeroAngle: Double = 0.0,
        startAngle: Double = 0.0,
        endAngle: Double = 360.0,
        wrapEnabled: Bool = true,
        wrapOverlap: Double = 5.0,
        tension: Double = 0.5
    ) {
        self.mode = mode
        self.diameter = max(1.0, diameter)
        self.axisLength = max(1.0, axisLength)
        self.direction = direction
        self.zeroAngle = max(0.0, min(360.0, zeroAngle))
        self.startAngle = max(0.0, min(360.0, startAngle))
        self.endAngle = max(0.0, min(360.0, endAngle))
        self.wrapEnabled = wrapEnabled
        self.wrapOverlap = max(0.0, wrapOverlap)
        self.tension = max(0.0, min(1.0, tension))
    }
}

// Laser mode.
public enum LaserMode: String, Codable, Sendable {
    case engrave
    case cut
    case score
    case fill
    case raster
    case vector
}

// Laser power mode.
public enum LaserPowerMode: String, Codable, Sendable {
    case constant
    case adaptive
    case pulse
}

// Laser configuration.
public struct LaserConfig: Codable, Sendable {
    public var mode: LaserMode
    public var powerPercent: Double
    public var speedMmPerMin: Double
    public var frequencyHz: Double
    public var passes: Int
    public var powerMode: LaserPowerMode
    public var kerfWidth: Double
    public var focusOffset: Double
    public var assistGas: Bool
    public var airAssist: Bool
    
    public init(
        mode: LaserMode = .engrave,
        powerPercent: Double = 50.0,
        speedMmPerMin: Double = 500.0,
        frequencyHz: Double = 1000.0,
        passes: Int = 1,
        powerMode: LaserPowerMode = .constant,
        kerfWidth: Double = 0.1,
        focusOffset: Double = 0.0,
        assistGas: Bool = false,
        airAssist: Bool = true
    ) {
        self.mode = mode
        self.powerPercent = max(0.0, min(100.0, powerPercent))
        self.speedMmPerMin = max(1.0, speedMmPerMin)
        self.frequencyHz = max(10.0, frequencyHz)
        self.passes = max(1, passes)
        self.powerMode = powerMode
        self.kerfWidth = max(0.0, kerfWidth)
        self.focusOffset = focusOffset
        self.assistGas = assistGas
        self.airAssist = airAssist
    }
}

// Specialty tool type.
public enum SpecialtyToolType: String, Codable, Sendable {
    case vBit
    case ballNose
    case dragKnife
    case pocketV
    case chamfer
    case bevel
    case pocketMill
    case contourMill
    case drill
    case tap
}

// Specialty tool configuration.
public struct SpecialtyToolConfig: Codable, Sendable {
    public var toolType: SpecialtyToolType
    public var diameter: Double
    public var tipAngle: Double
    public var length: Double
    public var shankDiameter: Double
    public var flutes: Int
    public var coating: String
    public var maxRPM: Int
    public var recommendedFeedMmPerMin: Double
    public var recommendedPlungeMmPerMin: Double
    
    public init(
        toolType: SpecialtyToolType = .vBit,
        diameter: Double = 3.175,
        tipAngle: Double = 30.0,
        length: Double = 25.0,
        shankDiameter: Double = 3.175,
        flutes: Int = 2,
        coating: String = "",
        maxRPM: Int = 20000,
        recommendedFeedMmPerMin: Double = 800.0,
        recommendedPlungeMmPerMin: Double = 200.0
    ) {
        self.toolType = toolType
        self.diameter = max(0.1, diameter)
        self.tipAngle = max(15.0, min(90.0, tipAngle))
        self.length = max(1.0, length)
        self.shankDiameter = max(0.1, shankDiameter)
        self.flutes = max(1, flutes)
        self.coating = coating
        self.maxRPM = max(1000, maxRPM)
        self.recommendedFeedMmPerMin = max(1.0, recommendedFeedMmPerMin)
        self.recommendedPlungeMmPerMin = max(1.0, recommendedPlungeMmPerMin)
    }
}

// Rotary result.
public struct RotaryResult: Codable, Sendable {
    public var config: RotaryConfig
    public var unrolledPathLength: Double
    public var wrappedPathLength: Double
    public var circumference: Double
    public var angularCoverage: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: RotaryConfig,
        unrolledPathLength: Double,
        wrappedPathLength: Double,
        circumference: Double,
        angularCoverage: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.unrolledPathLength = unrolledPathLength
        self.wrappedPathLength = wrappedPathLength
        self.circumference = circumference
        self.angularCoverage = angularCoverage
        self.success = success
        self.errorMessage = errorMessage
    }
}

// Laser result.
public struct LaserResult: Codable, Sendable {
    public var config: LaserConfig
    public var estimatedTimeMinutes: Double
    public var energyUsedJoules: Double
    public var cutDepthMm: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: LaserConfig,
        estimatedTimeMinutes: Double,
        energyUsedJoules: Double,
        cutDepthMm: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.energyUsedJoules = energyUsedJoules
        self.cutDepthMm = cutDepthMm
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - RotaryEngine

// Handles rotary axis calculations and toolpath generation.
public final class RotaryEngine {
    
    // Generates a rotary configuration.
    public static func createConfig(
        mode: RotaryMode = .cylinder,
        diameter: Double = 50.0,
        axisLength: Double = 100.0,
        direction: RotaryDirection = .clockwise
    ) -> RotaryConfig {
        RotaryConfig(
            mode: mode,
            diameter: diameter,
            axisLength: axisLength,
            direction: direction
        )
    }
    
    // Calculates circumference.
    public static func circumference(for config: RotaryConfig) -> Double {
        .pi * config.diameter
    }
    
    // Converts linear to angular position.
    public static func linearToAngular(
        linearPosition: Double,
        config: RotaryConfig
    ) -> Double {
        let circumference = circumference(for: config)
        let angle = (linearPosition / circumference) * 360.0
        return ((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    }
    
    // Converts angular to linear position.
    public static func angularToLinear(
        angle: Double,
        config: RotaryConfig
    ) -> Double {
        let circumference = circumference(for: config)
        return (angle / 360.0) * circumference
    }
    
    // Generates rotary toolpath result.
    public static func generateToolpath(
        config: RotaryConfig,
        pathLength: Double
    ) -> RotaryResult {
        let circumference = circumference(for: config)
        let angularCoverage = (pathLength / circumference) * 360.0
        
        // Check bounds
        if config.startAngle > config.endAngle {
            return RotaryResult(
                config: config,
                unrolledPathLength: 0,
                wrappedPathLength: 0,
                circumference: circumference,
                angularCoverage: 0,
                success: false,
                errorMessage: "Start angle must be less than end angle"
            )
        }
        
        if pathLength > circumference && !config.wrapEnabled {
            return RotaryResult(
                config: config,
                unrolledPathLength: 0,
                wrappedPathLength: 0,
                circumference: circumference,
                angularCoverage: 0,
                success: false,
                errorMessage: "Path exceeds circumference. Enable wrap or reduce path length."
            )
        }
        
        let wrappedLength = config.wrapEnabled ? pathLength * (1.0 + config.wrapOverlap / 100.0) : pathLength
        let unrolledLength = pathLength
        
        return RotaryResult(
            config: config,
            unrolledPathLength: unrolledLength,
            wrappedPathLength: wrappedLength,
            circumference: circumference,
            angularCoverage: angularCoverage,
            success: true
        )
    }
    
    // Validates rotary config.
    public static func validate(_ config: RotaryConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.diameter <= 0 { errors.append("Diameter must be positive") }
        if config.axisLength <= 0 { errors.append("Axis length must be positive") }
        if config.startAngle < 0 || config.startAngle > 360 { errors.append("Start angle must be 0-360") }
        if config.endAngle < 0 || config.endAngle > 360 { errors.append("End angle must be 0-360") }
        if config.wrapOverlap < 0 { errors.append("Wrap overlap cannot be negative") }
        if config.tension < 0 || config.tension > 1 { errors.append("Tension must be 0-1") }
        
        return (errors.isEmpty, errors)
    }
}

// MARK: - LaserEngine

// Handles laser cutting/engraving calculations.
public final class LaserEngine {
    
    // Generates a laser configuration.
    public static func createConfig(
        mode: LaserMode = .engrave,
        powerPercent: Double = 50.0,
        speedMmPerMin: Double = 500.0
    ) -> LaserConfig {
        LaserConfig(mode: mode, powerPercent: powerPercent, speedMmPerMin: speedMmPerMin)
    }
    
    // Calculates estimated time.
    public static func estimatedTime(
        config: LaserConfig,
        pathLengthMm: Double
    ) -> Double {
        let cuttingTime = pathLengthMm / config.speedMmPerMin * 60.0
        let totalPasses = config.passes
        return cuttingTime * Double(totalPasses) / 60.0
    }
    
    // Calculates energy used.
    public static func energyUsed(
        config: LaserConfig,
        pathLengthMm: Double
    ) -> Double {
        let powerWatts = (config.powerPercent / 100.0) * 1000.0 // Assume 1000W max
        let timeSeconds = pathLengthMm / config.speedMmPerMin * 60.0
        return powerWatts * timeSeconds
    }
    
    // Generates laser result.
    public static func generateToolpath(
        config: LaserConfig,
        pathLengthMm: Double
    ) -> LaserResult {
        let estimatedTime = estimatedTime(config: config, pathLengthMm: pathLengthMm)
        let energy = energyUsed(config: config, pathLengthMm: pathLengthMm)
        
        // Estimate cut depth
        var cutDepth = 0.0
        switch config.mode {
        case .cut:
            cutDepth = config.powerPercent / 100.0 * 20.0 // Assume 20mm max cut
        case .engrave:
            cutDepth = config.powerPercent / 100.0 * 3.0 // Assume 3mm max depth
        case .score:
            cutDepth = config.powerPercent / 100.0 * 0.5
        default:
            cutDepth = 0.0
        }
        
        return LaserResult(
            config: config,
            estimatedTimeMinutes: estimatedTime,
            energyUsedJoules: energy,
            cutDepthMm: cutDepth,
            success: true
        )
    }
    
    // Validates laser config.
    public static func validate(_ config: LaserConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.powerPercent < 0 || config.powerPercent > 100 { errors.append("Power must be 0-100%") }
        if config.speedMmPerMin <= 0 { errors.append("Speed must be positive") }
        if config.frequencyHz < 10 { errors.append("Frequency must be at least 10 Hz") }
        if config.passes < 1 { errors.append("Passes must be at least 1") }
        if config.kerfWidth < 0 { errors.append("Kerf width cannot be negative") }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - G-code emission (SPK-0906)
    
    /// Formats a coordinate with 3 decimals for G-code output.
    private static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
    
    /// Emits real laser CUT G-code for the given 2D path (mm coordinates):
    /// G0 rapid to the start point, M3 S<power> on, G1 F<speed> through the
    /// path, M5 off, with a G0 Z lift between passes and after the last pass.
    /// The pass loop repeats `config.passes` times.
    public static func gcodeForCut(config: LaserConfig, path: [(Double, Double)]) -> [String] {
        guard path.count >= 2 else { return [] }
        let passes = max(1, config.passes)
        let power = String(format: "%.0f", config.powerPercent)
        let speed = String(format: "%.0f", config.speedMmPerMin)
        let first = path[0]
        let closesLoop = path.last!.0 != first.0 || path.last!.1 != first.1
        
        var lines: [String] = []
        lines.append("; Laser cut — \(passes) pass(es), \(power)% power, \(speed) mm/min")
        for passNumber in 1...passes {
            lines.append("; pass \(passNumber)/\(passes)")
            if passNumber > 1 {
                // Lift between passes, then re-rapid to the start point.
                lines.append("G0 Z5.0")
            }
            lines.append("G0 X\(fmt(first.0)) Y\(fmt(first.1))")
            lines.append("M3 S\(power)")
            lines.append("G1 F\(speed)")
            for point in path.dropFirst() {
                lines.append("G1 X\(fmt(point.0)) Y\(fmt(point.1))")
            }
            if closesLoop {
                // Close the contour back to the start point.
                lines.append("G1 X\(fmt(first.0)) Y\(fmt(first.1))")
            }
            lines.append("M5")
        }
        lines.append("G0 Z5.0")
        return lines
    }
    
    /// Emits raster-style laser ENGRAVE G-code: M3 constant power at a
    /// reduced (half-speed) feed, tracing the path in a single scan pass,
    /// ending with M5. Engraving stays at Z0 (surface op).
    public static func gcodeForEngrave(config: LaserConfig, path: [(Double, Double)]) -> [String] {
        guard path.count >= 2 else { return [] }
        let power = String(format: "%.0f", config.powerPercent)
        let feed = String(format: "%.0f", config.speedMmPerMin * 0.5) // engrave runs slower
        let first = path[0]
        
        var lines: [String] = []
        lines.append("; Laser engrave — \(power)% power, \(feed) mm/min (raster)")
        lines.append("G0 X\(fmt(first.0)) Y\(fmt(first.1))")
        lines.append("M3 S\(power)")
        lines.append("G1 F\(feed)")
        for point in path.dropFirst() {
            lines.append("G1 X\(fmt(point.0)) Y\(fmt(point.1))")
        }
        lines.append("M5")
        return lines
    }
    
    /// Dispatches to the right emitter for the config's mode. Cut-like modes
    /// (.cut/.score/.vector) emit pass-loop cutting G-code; surface modes
    /// (.engrave/.raster/.fill) emit raster-style engraving G-code.
    public static func gcodeForMode(config: LaserConfig, path: [(Double, Double)]) -> [String] {
        switch config.mode {
        case .engrave, .raster, .fill:
            return gcodeForEngrave(config: config, path: path)
        case .cut, .score, .vector:
            return gcodeForCut(config: config, path: path)
        }
    }
}

// MARK: - SpecialtyToolManager

// Manages specialty tool configurations.
public final class SpecialtyToolManager {
    
    // Preset specialty tools.
    public static let presetTools: [SpecialtyToolConfig] = [
        SpecialtyToolConfig(
            toolType: .vBit,
            diameter: 3.175,
            tipAngle: 30.0,
            length: 25.0,
            shankDiameter: 3.175,
            flutes: 1,
            maxRPM: 20000,
            recommendedFeedMmPerMin: 600.0,
            recommendedPlungeMmPerMin: 150.0
        ),
        SpecialtyToolConfig(
            toolType: .vBit,
            diameter: 3.175,
            tipAngle: 60.0,
            length: 25.0,
            shankDiameter: 3.175,
            flutes: 1,
            maxRPM: 20000,
            recommendedFeedMmPerMin: 800.0,
            recommendedPlungeMmPerMin: 200.0
        ),
        SpecialtyToolConfig(
            toolType: .ballNose,
            diameter: 3.175,
            length: 25.0,
            shankDiameter: 3.175,
            flutes: 2,
            maxRPM: 20000,
            recommendedFeedMmPerMin: 1000.0,
            recommendedPlungeMmPerMin: 250.0
        ),
        SpecialtyToolConfig(
            toolType: .dragKnife,
            diameter: 10.0,
            length: 20.0,
            shankDiameter: 3.175,
            flutes: 0,
            maxRPM: 10000,
            recommendedFeedMmPerMin: 2000.0,
            recommendedPlungeMmPerMin: 100.0
        ),
        SpecialtyToolConfig(
            toolType: .drill,
            diameter: 3.175,
            length: 25.0,
            shankDiameter: 3.175,
            flutes: 2,
            maxRPM: 15000,
            recommendedFeedMmPerMin: 400.0,
            recommendedPlungeMmPerMin: 100.0
        )
    ]
    
    // Gets a preset tool by type.
    public static func getPresetTool(by type: SpecialtyToolType) -> [SpecialtyToolConfig] {
        presetTools.filter { $0.toolType == type }
    }
    
    // Gets all preset tools.
    public static func getAllPresets() -> [SpecialtyToolConfig] {
        presetTools
    }
    
    // Creates a custom tool.
    public static func createTool(
        toolType: SpecialtyToolType,
        diameter: Double,
        tipAngle: Double = 0.0,
        length: Double = 25.0,
        shankDiameter: Double = 3.175,
        flutes: Int = 2,
        maxRPM: Int = 20000
    ) -> SpecialtyToolConfig {
        SpecialtyToolConfig(
            toolType: toolType,
            diameter: diameter,
            tipAngle: tipAngle,
            length: length,
            shankDiameter: shankDiameter,
            flutes: flutes,
            maxRPM: maxRPM
        )
    }
    
    // Validates a tool config.
    public static func validate(_ config: SpecialtyToolConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.diameter <= 0 { errors.append("Diameter must be positive") }
        if config.tipAngle > 0 && (config.tipAngle < 15.0 || config.tipAngle > 90.0) {
            errors.append("Tip angle must be 15-90 degrees")
        }
        if config.length <= 0 { errors.append("Length must be positive") }
        if config.flutes < 0 { errors.append("Flutes cannot be negative") }
        if config.maxRPM < 1000 { errors.append("Max RPM must be at least 1000") }
        
        return (errors.isEmpty, errors)
    }
}
