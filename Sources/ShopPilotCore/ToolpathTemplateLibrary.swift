import Foundation

// MARK: - Toolpath Template Library

/// Strategy-facing wrapper around `ToolpathTemplateManager` (SPK-1311).
///
/// The manager owns persistence; the library owns the strategy-facing
/// contract: validated saves (no empty names, no non-JSON params, no
/// duplicate names), apply/delete that stay in sync with the published
/// `templates` array, type-filtered queries, and a static strategy-name
/// matcher used by the Save/Apply panel wiring.
public final class ToolpathTemplateLibrary: ObservableObject, @unchecked Sendable {

    /// All templates currently in the library (loaded on init, reloaded
    /// after every save/delete).
    @Published public private(set) var templates: [ToolpathTemplate]

    /// The underlying persistence manager.
    public let manager: ToolpathTemplateManager

    // MARK: - Initialization

    /// Create a library wrapping the given manager (defaults to a fresh
    /// manager backed by the user's Documents `toolpath_templates.json`).
    /// Existing templates are loaded on init.
    public init(manager: ToolpathTemplateManager = ToolpathTemplateManager()) {
        self.manager = manager
        self.templates = manager.templates
    }

    // MARK: - Public API

    /// Save a new template.
    ///
    /// Returns `nil` (without saving) when:
    ///  - the name is empty/whitespace-only,
    ///  - `paramsJson` does not start with `{` (invalid JSON params),
    ///  - a template with the same name already exists (case-insensitive).
    ///
    /// On success the template is persisted via the manager, the published
    /// `templates` array is reloaded, and the new template is returned.
    @discardableResult
    public func save(name: String, type: ToolpathTemplateType, paramsJson: String) -> ToolpathTemplate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard paramsJson.hasPrefix("{") else { return nil }
        guard !manager.templateExists(withName: trimmedName) else { return nil }
        let saved = manager.saveTemplate(name: trimmedName, type: type, paramsJson: paramsJson)
        reload()
        return saved
    }

    /// Apply a template by ID, returning its `paramsJson` (nil if missing).
    public func apply(id: UUID) -> String? {
        manager.applyTemplate(id: id)
    }

    /// Delete a template by ID and reload the published array.
    public func delete(id: UUID) {
        manager.deleteTemplate(id: id)
        reload()
    }

    /// Templates filtered by toolpath type.
    public func templates(for type: ToolpathTemplateType) -> [ToolpathTemplate] {
        templates.filter { $0.toolpathType == type }
    }

    /// Number of templates of the given toolpath type.
    public func count(for type: ToolpathTemplateType) -> Int {
        templates(for: type).count
    }

    /// Whether a strategy name matches a template type, by case-insensitive
    /// substring match on the type's display name (e.g. "Profile Outer"
    /// matches `.profile`, "V-Carve Text" matches `.vcarve`).
    public static func strategyMatches(_ strategyName: String, _ type: ToolpathTemplateType) -> Bool {
        strategyName.lowercased().contains(type.displayName.lowercased())
    }

    // MARK: - Internal

    /// Sync the published array with the manager's current templates.
    private func reload() {
        templates = manager.templates
    }
}
