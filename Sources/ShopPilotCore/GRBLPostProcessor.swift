import Foundation

// MARK: - Post Processor Type

/// Types of G-code post processors supported.
public enum PostProcessorType: String, Codable, Sendable {
    /// GRBL 1.1 format (most common for hobby CNC).
    case grbl
    /// Universal G-code with minimal assumptions.
    case universal
    
    public var displayName: String {
        switch self {
        case .grbl: return "GRBL 1.1"
        case .universal: return "Universal G-Code"
        }
    }

    /// Whether this post handles mid-file tool changes (ATC). Neither GRBL nor
    /// Universal does — a multi-tool tree must be split into ordered per-tool
    /// files (SPK-FM-R019). Future ATC posts return true here.
    public var supportsToolChange: Bool {
        switch self {
        case .grbl, .universal: return false
        }
    }
    
    /// File extension for this post processor type.
    public var fileExtension: String {
        switch self {
        case .grbl: return "gcode"
        case .universal: return "nc"
        }
    }
}

// MARK: - G-Code Units

/// Units the machine controller works in — drives the G21/G20 modal at the
/// top of the post-processed file (SPK-0415: per-machine units).
public enum GCodeUnits: String, Codable, Sendable {
    case millimeter
    case inch

    public var displayName: String {
        switch self {
        case .millimeter: return "mm (G21)"
        case .inch: return "inch (G20)"
        }
    }

    /// The G-code modal that selects these units.
    public var modalCode: String {
        switch self {
        case .millimeter: return "G21"
        case .inch: return "G20"
        }
    }
}

// MARK: - Post Processor Configuration

/// Configuration options for G-code post processing.
public struct PostProcessorConfiguration {
    
    public var postType: PostProcessorType
    
    /// Machine name to include in header comments.
    public var machineName: String
    
    /// Tool information to include in header.
    public var toolInfo: String?
    
    /// Whether to include line numbers.
    public var useLineNumbers: Bool
    
    /// Absolute (G90) vs relative (G91) positioning.
    public var absolutePositioning: Bool
    
    /// Millimeter (G21) vs inches (G20) units.
    public var millimeterUnits: Bool
    
    /// Coolant behavior on start (M7/M8).
    public var enableCoolant: Bool
    
    /// Safe Z height for rapid moves.
    public var safeZHeight: Double
    
    /// Program number.
    public var programNumber: Int
    
    public init(
        postType: PostProcessorType = .grbl,
        machineName: String = "ShopPilot",
        toolInfo: String? = nil,
        useLineNumbers: Bool = false,
        absolutePositioning: Bool = true,
        millimeterUnits: Bool = true,
        enableCoolant: Bool = true,
        safeZHeight: Double = 5.0,
        programNumber: Int = 1000
    ) {
        self.postType = postType
        self.machineName = machineName
        self.toolInfo = toolInfo
        self.useLineNumbers = useLineNumbers
        self.absolutePositioning = absolutePositioning
        self.millimeterUnits = millimeterUnits
        self.enableCoolant = enableCoolant
        self.safeZHeight = safeZHeight
        self.programNumber = programNumber
    }
}

// MARK: - Post Processed Output

/// Result of post processing G-code.
public struct PostProcessedOutput {
    
    /// The processed G-code as a string.
    public let gcodeString: String

    /// File name with appropriate extension.
    public var fileName: String {
        "toolpath.\(configuration.postType.fileExtension)"
    }
    
    /// The configuration used for processing.
    public let configuration: PostProcessorConfiguration

    public init(gcodeString: String, configuration: PostProcessorConfiguration) {
        self.gcodeString = gcodeString
        self.configuration = configuration
    }
    
    /// Number of lines in the output.
    public var lineCount: Int { gcodeString.components(separatedBy: "\n").count }
    
    /// File size in bytes (UTF-8).
    public var fileSizeBytes: Int { gcodeString.utf8.count }
}

// MARK: - GRBL Post Processor

/// Processes raw G-code into GRBL-compatible format with proper labeling.
public struct GRBLPostProcessor {
    
    private let configuration: PostProcessorConfiguration

    /// The configuration backing this post (exposed for callers that build
    /// their own output, e.g. the SPK-1134 template engine).
    public var currentConfiguration: PostProcessorConfiguration { configuration }
    
    init(configuration: PostProcessorConfiguration) {
        self.configuration = configuration
    }
    
    /// Create a post processor for GRBL 1.1.
    /// - Parameter units: controller units (default mm) — emits G21/G20 (SPK-0415).
    public static func grbl(machineName: String = "ShopPilot", units: GCodeUnits = .millimeter) -> GRBLPostProcessor {
        let config = PostProcessorConfiguration(
            postType: .grbl,
            machineName: machineName,
            useLineNumbers: false,
            absolutePositioning: true,
            millimeterUnits: units == .millimeter,
            enableCoolant: true,
            safeZHeight: 5.0
        )
        return GRBLPostProcessor(configuration: config)
    }
    
    /// Create a post processor for universal G-code.
    /// - Parameter units: controller units (default mm) — emits G21/G20 (SPK-0415).
    public static func universal(machineName: String = "ShopPilot", units: GCodeUnits = .millimeter) -> GRBLPostProcessor {
        let config = PostProcessorConfiguration(
            postType: .universal,
            machineName: machineName,
            useLineNumbers: true,
            absolutePositioning: true,
            millimeterUnits: units == .millimeter,
            enableCoolant: true,
            safeZHeight: 5.0
        )
        return GRBLPostProcessor(configuration: config)
    }
    
    /// Process raw G-code lines into post-processed output.
    public func process(gcodeLines: [String], toolInfo: String? = nil) -> PostProcessedOutput {
        var processedLines: [String] = []
        
        // Add header with metadata
        processedLines.append("%")
        processedLines.append("(Machine: \(configuration.machineName))")
        processedLines.append("(Post Processor: \(configuration.postType.displayName))")
        
        if let tool = toolInfo ?? configuration.toolInfo {
            processedLines.append("(Tool: \(tool))")
        }
        
        processedLines.append("(Generated by ShopPilot)")
        processedLines.append("")
        
        // Add initialization G-code
        if configuration.millimeterUnits {
            processedLines.append("G21 ; Set millimeter units")
        } else {
            processedLines.append("G20 ; Set inch units")
        }
        
        if configuration.absolutePositioning {
            processedLines.append("G90 ; Absolute positioning")
        } else {
            processedLines.append("G91 ; Relative positioning")
        }
        
        // Add coolant setup if enabled
        if configuration.enableCoolant {
            processedLines.append("M8 ; Flood coolant on")
        }
        
        processedLines.append("")
        
        // Process each line
        var lineNumber = 0
        
        for line in gcodeLines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments from input (we'll add our own)
            if trimmed.isEmpty || trimmed.hasPrefix("(") || trimmed.hasPrefix("%") || trimmed.hasPrefix("O=") {
                continue
            }
            
            // SPK-1609 — inch mode must scale the COORDINATES, not just emit
            // G20: "G20 with mm numbers" would move 25.4× too far. Scale the
            // numeric coordinate tokens (X/Y/Z/I/J/K/R) from mm to inches.
            if !configuration.millimeterUnits {
                trimmed = GCodeUnitConverter.scaleToInches(trimmed)
            }
            
            // Add line number if enabled
            if configuration.useLineNumbers {
                lineNumber += 10
                processedLines.append("\(lineNumber): \(trimmed)")
            } else {
                processedLines.append(trimmed)
            }
        }
        
        // Add cleanup G-code
        processedLines.append("")
        processedLines.append("M9 ; Coolant off")
        // SPK-1609 — the safe-Z header must follow the output units too
        // (mm mode: 5.0; inch mode: 5.0/25.4).
        let safeZ = configuration.millimeterUnits
            ? String(format: "%.1f", configuration.safeZHeight)
            : String(format: "%.4f", configuration.safeZHeight / GCodeUnitConverter.mmPerInch)
        processedLines.append("G0 Z\(safeZ) ; Rapid to safe height")
        processedLines.append("M2 ; Program end")
        processedLines.append("%")
        
        let gcodeString = processedLines.joined(separator: "\n")
        
        return PostProcessedOutput(
            gcodeString: gcodeString,
            configuration: configuration
        )
    }
    
    /// Process a single G-code string.
    public func process(gcodeString: String) -> PostProcessedOutput {
        let lines = gcodeString.components(separatedBy: "\n")
        return process(gcodeLines: lines)
    }
}

// MARK: - GCodeUnitConverter (SPK-1609)

/// Scales G-code coordinate tokens between unit systems. Inch output must
/// not be "G20 with mm numbers" — every coordinate word (X/Y/Z/I/J/K/R) is
/// divided by 25.4 so the controller moves the same physical distance.
public enum GCodeUnitConverter {

    /// Millimetres per inch.
    public static let mmPerInch = 25.4

    /// Coordinate word letters whose numbers are lengths (mm → inch).
    private static let coordinateLetters: Set<Character> = ["X", "Y", "Z", "I", "J", "K", "R"]

    /// Scale a g-code line's coordinate tokens from mm to inches.
    public static func scaleToInches(_ line: String) -> String {
        scale(line, by: 1.0 / mmPerInch)
    }

    /// Scale every coordinate token in `line` by `factor` (mm→inch uses
    /// 1/25.4). Non-coordinate words (G/M/S/F/T, comments) pass through
    /// untouched. Handles "X1.5" and "X-0.25" forms with optional signs.
    public static func scale(_ line: String, by factor: Double) -> String {
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if coordinateLetters.contains(ch) {
                result.append(ch)
                index = line.index(after: index)
                // Preserve the optional sign, then parse the number.
                var sign = ""
                if index < line.endIndex, line[index] == "-" || line[index] == "+" {
                    sign = String(line[index])
                    index = line.index(after: index)
                }
                var numberEnd = index
                while numberEnd < line.endIndex, line[numberEnd].isNumber || line[numberEnd] == "." {
                    numberEnd = line.index(after: numberEnd)
                }
                if index < numberEnd,
                   let value = Double(String(line[index..<numberEnd])) {
                    let scaled = value * factor
                    result.append(sign)
                    result.append(String(format: "%.4f", scaled))
                    index = numberEnd
                    continue
                }
                // No number after the letter — copy the sign back as-is.
                result.append(sign)
                continue
            }
            result.append(ch)
            index = line.index(after: index)
        }
        return result
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct GRBLPostProcessor_Previews: PreviewProvider {
    static var previews: some View {
        Text("GRBL post processor is a non-visual component")
    }
}
#endif
