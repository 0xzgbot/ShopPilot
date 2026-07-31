import Foundation
import SwiftUI
#if canImport(ShopPilotGeometry)
import ShopPilotGeometry
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Import Hub View

/// Unified import hub for vector design files. Provides a single entry point for importing SVG, DXF, and other supported formats into the ShopPilot document model.
public struct ImportHubView: View {

    // MARK: - State

    @State private var isImportSheetPresented = false
    @State private var importResult: ImportResult?
    @State private var selectedFormat: ImportFormat = .svg
    @State private var shapesImported: [VectorShape] = []
    @State private var errorMessage: String?

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Import Design File")
                .font(.title2.bold())
            
            // Format selector
            Picker("File Format", selection: $selectedFormat) {
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Import button
            Button(action: openFilePicker) {
                Label("Choose File", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            // Supported formats info
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported Formats")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    FormatRow(format: format)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            // Import result (if any)
            if let result = importResult {
                ImportResultView(result: result)
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $isImportSheetPresented) {
            FilePickerView(selectedFormat: selectedFormat, onFileSelected: handleFileSelection)
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        importResult = nil
        errorMessage = nil
        shapesImported.removeAll()
        isImportSheetPresented = true
    }

    private func handleFileSelection(url: URL) {
        Task {
            do {
                let result = try await performImport(url: url, format: selectedFormat)
                importResult = result
                errorMessage = nil
                shapesImported = result.shapes
            } catch {
                errorMessage = error.localizedDescription
                importResult = ImportResult(
                    fileName: url.lastPathComponent,
                    format: selectedFormat,
                    shapes: [],
                    errors: [error.localizedDescription],
                    warnings: []
                )
            }
        }
    }

    private func performImport(url: URL, format: ImportFormat) async throws -> ImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        
        switch format {
        case .svg:
            return try importSVG(content: content, fileName: url.lastPathComponent)
        case .dxf:
            // DXF is drafted but not passing build — show placeholder message
            throw ImportError.dxfNotAvailable
        }
    }

    private func importSVG(content: String, fileName: String) throws -> ImportResult {
        let parseResult = SVGImporter.parse(content)
        
        var warnings: [String] = []
        
        // Warn about unclosed paths (common in SVG exports from vector tools)
        if !parseResult.errors.isEmpty && parseResult.success {
            warnings.append("Some path elements had issues but import succeeded")
        }
        
        return ImportResult(
            fileName: fileName,
            format: .svg,
            shapes: parseResult.shapes,
            errors: parseResult.errors,
            warnings: warnings
        )
    }
}

// MARK: - Format Row Subview

/// Displays a single supported import format with its status and description.
private struct FormatRow: View {
    let format: ImportFormat
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: format.iconName)
                .foregroundColor(format.statusColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(format.displayName)
                    .font(.caption.bold())
                
                Text(format.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusBadge
        }
    }
    
    private var statusBadge: some View {
        Text(format.statusText)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(format.statusColor.opacity(0.15))
            .foregroundColor(format.statusColor)
            .cornerRadius(4)
    }
}

// MARK: - Import Result View

/// Displays the results of an import operation with shape count and any errors/warnings.
public struct ImportResultView: View {
    
    let result: ImportResult
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary header
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.success ? .green : .orange)
                
                Text("Imported \(result.fileName)")
                    .font(.headline)
                
                Spacer()
                
                Text("\(result.shapes.count) shapes")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            // Errors (if any)
            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Errors")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    
                    ForEach(result.errors, id: \.self) { error in
                        Text(error)
                            .font(.caption2.monospaced())
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(6)
            }
            
            // Warnings (if any)
            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    
                    ForEach(result.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if result.success {
                    Button(action: {}) {
                        Label("Add to Document", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(action: {}) {
                        Label("Discard", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {}) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - File Picker View

/// Native macOS file picker using NSOpenPanel for importing design files.
private struct FilePickerView: NSViewRepresentable {
    
    let selectedFormat: ImportFormat
    let onFileSelected: (URL) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        // Trigger the open panel immediately when this view appears
        context.coordinator.triggerOpen(in: view, format: selectedFormat)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFileSelected: onFileSelected)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSOpenSavePanelDelegate {
        
        let onFileSelected: (URL) -> Void
        
        init(onFileSelected: @escaping (URL) -> Void) {
            self.onFileSelected = onFileSelected
        }
        
        func triggerOpen(in view: NSView, format: ImportFormat) {
            
            let panel = NSOpenPanel()
            panel.title = "Import Design File"
            panel.allowedContentTypes = allowedTypes(for: format)
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.delegate = self
            
            // Set default directory to Documents
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                panel.directoryURL = documentsURL
            }
            
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.onFileSelected(url)
            }
        }
        
        private func allowedTypes(for format: ImportFormat) -> [UTType] {
            switch format {
            case .svg:
                return [.svg, .image, .plainText]
            case .dxf:
                return [.plainText] // DXF not in UTType registry; accept as plain text
            }
        }
    }
}

// MARK: - Import Format

/// Supported import file formats for the design hub.
public enum ImportFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case svg
    case dxf
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .svg: return "SVG"
        case .dxf: return "DXF"
        }
    }
    
    public var description: String {
        switch self {
        case .svg: return "Scalable Vector Graphics — paths, shapes, curves"
        case .dxf: return "Drawing Exchange Format — CAD vector data"
        }
    }
    
    public var iconName: String {
        switch self {
        case .svg: return "photo"
        case .dxf: return "square.grid.2x2"
        }
    }
    
    public var statusText: String {
        switch self {
        case .svg: return "Ready"
        case .dxf: return "Draft"
        }
    }
    
    public var statusColor: Color {
        switch self {
        case .svg: return .green
        case .dxf: return .orange
        }
    }
}

// MARK: - Import Result

/// Result of an import operation, containing shapes and any errors/warnings.
public struct ImportResult: Identifiable {
    
    public let id = UUID()
    
    /// The original file name that was imported.
    public let fileName: String
    
    /// The format the file was imported as.
    public let format: ImportFormat
    
    /// Parsed vector shapes from the import.
    public let shapes: [VectorShape]
    
    /// Errors encountered during import (fatal if any start with "FATAL").
    public let errors: [String]
    
    /// Non-fatal warnings about the import process.
    public let warnings: [String]
    
    /// Whether the import succeeded without fatal errors.
    public var success: Bool { !errors.contains(where: { $0.hasPrefix("FATAL") }) }
}

// MARK: - Import Errors

/// Errors specific to the import hub operations.
enum ImportError: LocalizedError {
    case dxfNotAvailable
    case unsupportedFormat(String)
    case fileReadFailed(URL, Error)
    
    var errorDescription: String? {
        switch self {
        case .dxfNotAvailable:
            return "DXF import is currently in development. Please use SVG format."
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        case .fileReadFailed(let url, let error):
            return "Failed to read '\(url.lastPathComponent)': \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct ImportHubView_Previews: PreviewProvider {
    static var previews: some View {
        ImportHubView()
            .frame(width: 400, height: 500)
    }
}
#endif
