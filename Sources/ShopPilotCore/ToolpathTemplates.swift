import Foundation

// MARK: - Toolpath Template Type

/// Represents the type of toolpath operation a template applies to.
public enum ToolpathTemplateType: String, Codable, Sendable, CaseIterable {
    case profile
    case pocket
    case drill
    case vcarve
    case quickengrave
    
    public var displayName: String {
        switch self {
        case .profile: return "Profile"
        case .pocket: return "Pocket"
        case .drill: return "Drill"
        case .vcarve: return "V-Carve"
        case .quickengrave: return "Quick Engrave"
        }
    }
}

// MARK: - Toolpath Template

/// A saved set of toolpath parameters that can be reused across jobs.
public struct ToolpathTemplate: Codable, Identifiable, Equatable {
    
    public let id: UUID
    public var name: String
    public let toolpathType: ToolpathTemplateType
    public let paramsJson: String
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        toolpathType: ToolpathTemplateType,
        paramsJson: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.toolpathType = toolpathType
        self.paramsJson = paramsJson
        self.createdAt = createdAt
    }
    
    public static func == (lhs: ToolpathTemplate, rhs: ToolpathTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toolpath Template Manager

/// Manages persistence and lifecycle of toolpath templates.
///
/// Templates are stored as a JSON array in the user's Documents directory.
/// Each template holds its parameters as a JSON string, allowing any
/// Codable toolpath params struct (ProfileToolpathParams, VCarveParams, etc.)
/// to be serialized and restored.
public final class ToolpathTemplateManager: ObservableObject {
    
    /// All saved templates, published for SwiftUI binding.
    @Published public var templates: [ToolpathTemplate] = []
    
    private let fileURL: URL
    
    // MARK: - Initialization
    
    /// Create a new manager. Templates are loaded from disk on init.
    public init() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docsDir.appendingPathComponent("toolpath_templates.json")
        self.templates = self.loadTemplates()
    }
    
    /// Create a manager with a custom file URL (useful for testing).
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.templates = self.loadTemplates()
    }
    
    // MARK: - Public API
    
    /// Save a new template with the given name, type, and JSON-serialized params.
    /// - Returns: The newly created template.
    public func saveTemplate(name: String, type: ToolpathTemplateType, paramsJson: String) -> ToolpathTemplate {
        let template = ToolpathTemplate(
            name: name,
            toolpathType: type,
            paramsJson: paramsJson
        )
        templates.append(template)
        saveTemplates()
        return template
    }
    
    /// Load templates from disk.
    public func loadTemplates() -> [ToolpathTemplate] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([ToolpathTemplate].self, from: data)
            return loaded.sorted { $0.createdAt < $1.createdAt }
        } catch {
            // File doesn't exist or is corrupt — start fresh
            return []
        }
    }
    
    /// Delete a template by ID and persist the change.
    public func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        saveTemplates()
    }
    
    /// Apply a template by ID, returning its JSON params string.
    /// - Returns: The paramsJson string, or nil if the template was not found.
    public func applyTemplate(id: UUID) -> String? {
        templates.first(where: { $0.id == id })?.paramsJson
    }
    
    /// Get templates filtered by type.
    public func templates(for type: ToolpathTemplateType) -> [ToolpathTemplate] {
        templates.filter { $0.toolpathType == type }
    }
    
    /// Check if a template with the given name already exists.
    public func templateExists(withName name: String) -> Bool {
        templates.contains { $0.name.lowercased() == name.lowercased() }
    }
    
    // MARK: - Persistence
    
    /// Save all templates to disk.
    private func saveTemplates() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(templates)
            try data.write(to: fileURL)
        } catch {
            // Silently fail — UI should surface via @Published error state
            // In production, this would notify the user
        }
    }
}
