import Foundation

// MARK: - Post template store (SPK-1000 Post Studio)

/// Persisted collection of post templates: the shipped GRBL set (SPK-1134)
/// plus user-created templates with variable blocks. Backed by UserDefaults
/// JSON (same pattern as ToolDatabase / MachineProfileStore).
public final class PostTemplateStore: ObservableObject {

    @Published public private(set) var userTemplates: [PostTemplate]

    private let defaults: UserDefaults
    private static let storageKey = "shop_pilot_post_templates_v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([PostTemplate].self, from: data),
           !decoded.isEmpty {
            self.userTemplates = decoded
        } else {
            self.userTemplates = []
        }
    }

    /// All selectable templates: shipped first, then user templates.
    public var allTemplates: [PostTemplate] {
        PostTemplate.shipped + userTemplates
    }

    /// Resolve a template by id across shipped + user templates.
    public func template(byID id: String) -> PostTemplate? {
        allTemplates.first { $0.id == id }
    }

    /// Add (or replace, by id) a user template and persist.
    public func upsertUserTemplate(_ template: PostTemplate) {
        if let idx = userTemplates.firstIndex(where: { $0.id == template.id }) {
            userTemplates[idx] = template
        } else {
            userTemplates.append(template)
        }
        save()
    }

    /// Remove a user template by id. Shipped templates are never removed.
    @discardableResult
    public func removeUserTemplate(id: String) -> Bool {
        guard let idx = userTemplates.firstIndex(where: { $0.id == id }) else { return false }
        userTemplates.remove(at: idx)
        save()
        return true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(userTemplates) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Default document variables for a template — the Post Studio block
    /// surface. Values are filled from the live document at export time;
    /// these are the keys the UI advertises.
    public static let documentVariableKeys: [String] = [
        "jobName", "sheetWidth", "sheetDepth", "sheetHeight",
        "materialName", "toolName", "feedRate", "spindleRpm",
    ]
}
