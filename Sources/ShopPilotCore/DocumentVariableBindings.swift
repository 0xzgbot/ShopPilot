import Foundation

// MARK: - Document Variable Binding

/// Binds a document variable to a specific field on a ShopPilot object
/// (e.g. Sheet.width, ProfileToolpathParams.cutDepth).
public struct DocumentVariableBinding: Identifiable, Codable, Hashable {

    /// Unique identifier for this binding.
    public let id: UUID

    /// The document variable key to resolve (e.g. "stockWidth", "materialThickness").
    public var variableKey: String

    /// The target field path, dot-separated (e.g. "sheet.width", "toolpath.cutDepth").
    public var targetField: String

    /// The object type this field belongs to (e.g. "Sheet", "ProfileToolpath", "VCarveToolpath").
    public var targetObject: String

    /// Whether the binding is active. Inactive bindings are ignored during resolution.
    public var active: Bool

    /// Fallback value used when the document variable is not set or non-numeric.
    public var fallbackValue: Double?

    public init(
        id: UUID = UUID(),
        variableKey: String,
        targetField: String,
        targetObject: String,
        active: Bool = true,
        fallbackValue: Double? = nil
    ) {
        self.id = id
        self.variableKey = variableKey
        self.targetField = targetField
        self.targetObject = targetObject
        self.active = active
        self.fallbackValue = fallbackValue
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DocumentVariableBinding, rhs: DocumentVariableBinding) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Variable Binding Manager

/// Manages the relationship between document variables and their target fields.
/// ObservableObject for SwiftUI consumption.
public final class VariableBindingManager: ObservableObject {

    /// All configured bindings.
    @Published public var bindings: [DocumentVariableBinding]

    /// Current document variables available for resolution.
    @Published public var documentVariables: [DocumentVariable]

    public init(
        bindings: [DocumentVariableBinding] = [],
        documentVariables: [DocumentVariable] = []
    ) {
        self.bindings = bindings
        self.documentVariables = documentVariables
    }

    // MARK: - CRUD

    /// Add a binding to the manager.
    public func addBinding(_ binding: DocumentVariableBinding) {
        bindings.append(binding)
    }

    /// Remove a binding by ID. Returns true if a binding was removed.
    @discardableResult
    public func removeBinding(_ id: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return false }
        bindings.remove(at: index)
        return true
    }

    // MARK: - Resolution

    /// Resolve a variable binding for a given field and object type.
    ///
    /// Searches for an active binding matching the field + object, then resolves
    /// the variable key against the current document variables. Returns the
    /// resolved value, the fallback (if set and variable is unavailable), or nil.
    ///
    /// - Parameters:
    ///   - field: The field path (e.g. "width").
    ///   - object: The object type (e.g. "Sheet").
    /// - Returns: The resolved `Double`, or `nil` if no binding or resolution fails.
    public func getResolvedValue(for field: String, object: String) -> Double? {
        let active = bindings.filter { $0.active }

        // Exact match on field + object
        if let binding = active.first(where: { $0.targetField == field && $0.targetObject == object }) {
            return resolveVariable(binding.variableKey) ?? binding.fallbackValue
        }

        // Wildcard match on object only (targetField == "*")
        if let binding = active.first(where: { $0.targetField == "*" && $0.targetObject == object }) {
            return resolveVariable(binding.variableKey) ?? binding.fallbackValue
        }

        return nil
    }

    /// Resolve a single variable key to a Double from the current document variables.
    ///
    /// - Parameter key: The document variable key.
    /// - Returns: The numeric value, or `nil` if the variable is not found or non-numeric.
    private func resolveVariable(_ key: String) -> Double? {
        guard let variable = documentVariables.first(where: { $0.key == key }) else {
            return nil
        }
        return Double(variable.value)
    }

    // MARK: - Update

    /// Update the manager's document variables (e.g. from a Job document).
    /// Call this whenever the document's variables change so bindings can be re-resolved.
    public func updateFromVariables(_ variables: [DocumentVariable]) {
        documentVariables = variables
    }

    // MARK: - Validation

    /// Validate all bindings and return a list of human-readable error messages.
    ///
    /// Checks:
    /// - Empty variable key
    /// - Empty target field
    /// - Empty target object
    /// - Variable key not found in current document variables (with a warning, not error)
    /// - Invalid fallback value
    /// - Duplicate bindings (same variable key + target field + target object)
    public func validateBindings() -> [String] {
        var errors: [String] = []

        var seenKeys: Set<String> = Set()

        for binding in bindings {
            let prefix = "Binding '\(binding.id.uuidString.prefix(8))'"

            if binding.variableKey.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("\(prefix): variable key is empty")
            }

            if binding.targetField.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("\(prefix): target field is empty")
            }

            if binding.targetObject.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("\(prefix): target object is empty")
            }

            if let fallback = binding.fallbackValue, fallback.isNaN || fallback.isInfinite {
                errors.append("\(prefix): fallback value is not a finite number")
            }

            // Check for duplicates (same variable key + target field + target object)
            let dupKey = "\(binding.variableKey)|\(binding.targetField)|\(binding.targetObject)"
            if seenKeys.contains(dupKey) {
                errors.append("\(prefix): duplicate binding (same variable key, field, and object)")
            }
            seenKeys.insert(dupKey)
        }

        return errors
    }

    // MARK: - Cleanup

    /// Remove all inactive bindings.
    public func clearInactiveBindings() {
        bindings.removeAll { !$0.active }
    }
}
