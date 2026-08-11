import Foundation
import SwiftUI
import ShopPilotCore
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

    /// Lets the sheet close itself — macOS sheets may not render a title-bar
    /// close button, so the content must carry its own dismiss affordance.
    @Environment(\.dismiss) private var dismiss

    /// Called when the user confirms adding imported shapes to the document.
    var onShapesImported: (([VectorShape]) -> Void)?

    /// SPK-1209 — called with the picked URL when an import succeeds, so the
    /// session can remember it for the Recent rail.
    var onRecordRecent: ((URL) -> Void)?

    /// SPK-1209 — recent files shown in the rail (injected by the session;
    /// nil hides the rail).
    var recentFiles: [RecentFilesStore.RecentFile]?
    var clearRecent: () -> Void = {}

    public init(onShapesImported: (([VectorShape]) -> Void)? = nil,
                onRecordRecent: ((URL) -> Void)? = nil,
                recentFiles: [RecentFilesStore.RecentFile]? = nil,
                clearRecent: @escaping () -> Void = {}) {
        self.onShapesImported = onShapesImported
        self.onRecordRecent = onRecordRecent
        self.recentFiles = recentFiles
        self.clearRecent = clearRecent
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Import Design File")
                    .font(.title2.bold())
                Spacer()
                // Explicit close — the sheet must be dismissible without
                // importing anything.
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
            
            // Format selector
            Picker("File Format", selection: $selectedFormat) {
                ForEach(ImportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selectedFormat == .dxf {
                Text("DXF (ASCII) — LINE / Polyline / Circle / Arc entities; other entities are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Import button
            Button(action: openFilePicker) {
                Label("Choose File", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            // SPK-1209 — Recent rail: one-click re-import of files you used
            // recently (deduped, capped at 10, persisted in UserDefaults).
            if let recent = recentFiles, !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") { clearRecent() }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ForEach(recent) { file in
                        Button {
                            handleFileSelection(url: file.url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(file.url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(file.importedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 1)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }

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
                ImportResultView(
                    result: result,
                    onAdd: {
                        onShapesImported?(result.shapes)
                        shapesImported = result.shapes
                        importResult = nil
                    },
                    onDiscard: {
                        importResult = nil
                        shapesImported = []
                    }
                )
                .transition(.opacity)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $isImportSheetPresented) {
            FilePickerView(selectedFormat: selectedFormat, onFileSelected: handleFileSelection)
        }
        // Esc closes the sheet like any other dialog.
        .onExitCommand { dismiss() }
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
                // SPK-1209 — a successful import is remembered for the Recent
                // rail (even partial imports with warnings count as used).
                if !result.shapes.isEmpty {
                    onRecordRecent?(url)
                }
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
        // SPK-0216: all formats route through UnifiedImportRouter — one
        // dispatch, uniform result shape.
        let routerFormat: UnifiedImportRouter.Format
        switch format {
        case .svg: routerFormat = .svg
        case .dxf: routerFormat = .dxf
        case .eps: routerFormat = .eps
        case .pdf: routerFormat = .pdf
        case .ai: routerFormat = .ai
        case .dwg: routerFormat = .dwg
        }
        let result = UnifiedImportRouter.importFile(at: url, format: routerFormat)
        // The router emits warnings ONLY on failure (unsupported ext, read or
        // parse errors) — surface them as errors; the shape list stays intact
        // so partial imports still show a preview.
        return ImportResult(
            fileName: url.lastPathComponent,
            format: format,
            shapes: result.shapes,
            errors: result.warnings.isEmpty ? [] : result.warnings.map { "FATAL: \($0)" },
            warnings: []
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
    var onAdd: (() -> Void)?
    var onDiscard: (() -> Void)?
    
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
                    Button(action: { onAdd?() }) {
                        Label("Add to Document", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(action: { onDiscard?() }) {
                        Label("Discard", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: { onDiscard?() }) {
                        Label("Dismiss", systemImage: "xmark.circle.fill")
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
            case .eps:
                return [.plainText, .data] // EPS is text but may carry binary previews
            case .pdf:
                return [.pdf]
            case .ai:
                return [.plainText, .pdf, .data] // AI is EPS or PDF flavor
            case .dwg:
                return [.data] // DWG is binary; no UTType registry entry
            }
        }
    }
}

// MARK: - Import Format

/// Supported import file formats for the design hub (SPK-0216: one picker
/// covering every vector format the router dispatches).
public enum ImportFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case svg
    case dxf
    case eps
    case pdf
    case ai
    case dwg

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .svg: return "SVG"
        case .dxf: return "DXF"
        case .eps: return "EPS"
        case .pdf: return "PDF"
        case .ai: return "AI"
        case .dwg: return "DWG"
        }
    }

    public var description: String {
        switch self {
        case .svg: return "Scalable Vector Graphics — paths, shapes, curves"
        case .dxf: return "Drawing Exchange Format — CAD vector data"
        case .eps: return "Encapsulated PostScript — vector drawings"
        case .pdf: return "PDF — vector content streams"
        case .ai: return "Adobe Illustrator — EPS or PDF flavor"
        case .dwg: return "AutoCAD DWG — R12 (AC1009) LINE/CIRCLE/ARC/POINT"
        }
    }

    public var iconName: String {
        switch self {
        case .svg: return "photo"
        case .dxf: return "square.grid.2x2"
        case .eps: return "doc.richtext"
        case .pdf: return "doc.plaintext"
        case .ai: return "paintbrush.pointed"
        case .dwg: return "square.stack.3d.up"
        }
    }

    public var statusText: String {
        switch self {
        case .svg: return "Ready"
        case .dxf: return "Ready (ASCII)"
        case .eps: return "Ready"
        case .pdf: return "Ready"
        case .ai: return "Ready"
        case .dwg: return "Ready (R12)"
        }
    }

    public var statusColor: Color {
        switch self {
        case .svg, .dxf, .eps, .pdf, .ai: return .green
        case .dwg: return .green
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
    case unsupportedFormat(String)
    case fileReadFailed(URL, Error)
    case svgParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        case .fileReadFailed(let url, let error):
            return "Failed to read '\(url.lastPathComponent)': \(error.localizedDescription)"
        case .svgParseFailed(let message):
            return "SVG import failed: \(message)"
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
