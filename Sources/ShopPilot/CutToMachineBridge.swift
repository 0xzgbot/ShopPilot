import Foundation
import SwiftUI
import ShopPilotCore
import ShopPilotSerial

// MARK: - Bridge Export Result

/// Result of a Cut→Machine bridge export operation.
public struct CutToMachineBridgeResult {
    
    /// The post-processor type used.
    public let postProcessorType: PostProcessorType
    
    /// The post template used (SPK-1134) when the export ran through the
    /// template engine; nil when the legacy post was used.
    public let postTemplateID: String?
    
    /// The exported G-code file URL.
    public let outputFileURL: URL?
    
    /// Number of lines in the exported file.
    public let lineCount: Int
    
    /// Error message if export failed.
    public var errorMessage: String?
    
    /// Whether the export succeeded.
    public var success: Bool { outputFileURL != nil && errorMessage == nil }
}

// MARK: - Cut-to-Machine Bridge

/// Bridges the Cut stage (G-code generation) to the Machine stage (streaming).
///
/// Workflow:
/// 1. Receive raw G-code lines from the Cut stage
/// 2. Post-process using GRBLPostProcessor based on machine profile
/// 3. Write to a temp directory for the Machine stage to consume
/// 4. Return result with file URL for streaming
public final class CutToMachineBridge {
    
    /// Export G-code from the Cut stage and prepare it for machine streaming.
    ///
    /// - Parameters:
    ///   - gcodeLines: Raw G-code lines from toolpath engine
    ///   - toolInfo: Tool description for header comments
    ///   - machineProfile: Machine profile determining post-processor type
    ///   - fileName: Base name for the output file
    /// - Returns: Bridge export result with file URL
    public static func export(
        gcodeLines: [String],
        toolInfo: String?,
        machineProfile: MachineProfile,
        fileName: String = "job",
        postTemplate: PostTemplate? = nil,
        postVariables: [String: String] = [:],
        unitsOverride: GCodeUnits? = nil
    ) throws -> CutToMachineBridgeResult {
        
        // Validate input
        guard !gcodeLines.isEmpty else {
            return CutToMachineBridgeResult(
                postProcessorType: .grbl,
                postTemplateID: nil,
                outputFileURL: nil,
                lineCount: 0,
                errorMessage: "No G-code lines to export"
            )
        }
        
        // Select post-processor based on machine profile (SPK-0415: the
        // profile's machine type picks GRBL vs Universal, and its units pick
        // G21 vs G20). SPK-1609: the Preferences unit choice OVERRIDES the
        // profile when set — and inch mode also scales the coordinates
        // (G20 with mm numbers would move 25.4× too far).
        let units = unitsOverride ?? machineProfile.units
        let postProcessor: GRBLPostProcessor
        let postType: PostProcessorType
        
        switch machineProfile.autoPostProcessorType {
        case .grbl:
            postProcessor = GRBLPostProcessor.grbl(machineName: machineProfile.name, units: units)
            postType = .grbl
        case .universal:
            postProcessor = GRBLPostProcessor.universal(machineName: machineProfile.name, units: units)
            postType = .universal
        }
        
        // SPK-1134: when a post template is selected, run the G-code through
        // the template engine instead of the legacy wrapper.
        let output: PostProcessedOutput
        let postTemplateID: String?
        if let postTemplate {
            let result = PostTemplateEngine.emit(gcodeLines: gcodeLines, template: postTemplate,
                                                 variables: postVariables)
            let processed = result.lines.joined(separator: "\n")
            output = PostProcessedOutput(
                gcodeString: processed,
                configuration: postProcessor.currentConfiguration
            )
            postTemplateID = postTemplate.id
        } else {
            // Post-process the G-code through the legacy wrapper.
            output = postProcessor.process(gcodeLines: gcodeLines, toolInfo: toolInfo)
            postTemplateID = nil
        }
        
        // Write to temp directory
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopPilotExports")
        
        try FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true
        )
        
        let fileExtension = postType.fileExtension
        let filePath = "\(fileName).\(fileExtension)"
        let outputFileURL = exportDir.appendingPathComponent(filePath)
        
        do {
            try output.gcodeString.write(
                to: outputFileURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            return CutToMachineBridgeResult(
                postProcessorType: postType,
                postTemplateID: postTemplateID,
                outputFileURL: nil,
                lineCount: 0,
                errorMessage: "Failed to write G-code file: \(error.localizedDescription)"
            )
        }
        
        return CutToMachineBridgeResult(
            postProcessorType: postType,
            postTemplateID: postTemplateID,
            outputFileURL: outputFileURL,
            lineCount: output.lineCount,
            errorMessage: nil
        )
    }
    
    /// Get the most recent exported G-code file from the bridge.
    ///
    /// - Returns: URL to the most recent export file, or nil if none exists.
    public static func latestExport() -> URL? {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopPilotExports")
        
        guard FileManager.default.fileExists(atPath: exportDir.path) else {
            return nil
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: exportDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            
            let gcodeFiles = files
                .filter { $0.pathExtension == "gcode" || $0.pathExtension == "nc" }
                .sorted { urlA, urlB in
                    let dateA = (try? urlA.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate) ?? Date.distantPast
                    let dateB = (try? urlB.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate) ?? Date.distantPast
                    return dateA > dateB
                }
            
            return gcodeFiles.first
        } catch {
            return nil
        }
    }
    
    /// Clear all exported G-code files from the bridge.
    public static func clearExports() {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopPilotExports")
        
        try? FileManager.default.removeItem(at: exportDir)
    }
}
