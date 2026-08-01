import Foundation

// MARK: - Document Variable Binding

/// Binds a document variable to a specific field in a job object.
public struct DocumentVariableBinding: Identifiable, Codable, Hashable {
    public let id: UUID
    public var variableKey: String
    public var targetField: String
    public var targetObject: String
    public var active: Bool
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
    
    // MARK: - Equatable
    
    public static func == (lhs: DocumentVariableBinding, rhs: DocumentVariableBinding) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Variable Binding Manager

/// Manages document variable bindings and resolution.
public final class VariableBindingManager: ObservableObject {
    @Published public var bindings: [DocumentVariableBinding]
    @Published public var documentVariables: [DocumentVariable]
    
    public init(
        bindings: [DocumentVariableBinding] = [],
        documentVariables: [DocumentVariable] = []
    ) {
        self.bindings = bindings
        self.documentVariables = documentVariables
    }
    
    /// Adds a binding.
    @discardableResult
    public func addBinding(_ binding: DocumentVariableBinding) -> DocumentVariableBinding {
        bindings.append(binding)
        return binding
    }
    
    /// Adds a binding by key.
    @discardableResult
    public func addBinding(
        variableKey: String,
        targetField: String,
        targetObject: String,
        active: Bool = true,
        fallbackValue: Double? = nil
    ) -> DocumentVariableBinding {
        let binding = DocumentVariableBinding(
            variableKey: variableKey,
            targetField: targetField,
            targetObject: targetObject,
            active: active,
            fallbackValue: fallbackValue
        )
        return addBinding(binding)
    }
    
    /// Removes a binding by ID.
    @discardableResult
    public func removeBinding(_ id: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return false }
        bindings.remove(at: index)
        return true
    }
    
    /// Gets the resolved value for a field.
    public func getResolvedValue(for field: String, object: String) -> Double? {
        guard let binding = bindings.first(where: {
            $0.targetField == field && $0.targetObject == object && $0.active
        }) else {
            return nil
        }
        
        // Look up the variable by key
        if let variable = documentVariables.first(where: { $0.key == binding.variableKey }) {
            if let value = Double(variable.value) {
                return value
            }
        }
        
        // Return fallback
        return binding.fallbackValue
    }
    
    /// Updates resolved values from current variables.
    public func updateFromVariables(_ variables: [DocumentVariable]) {
        documentVariables = variables
    }
    
    /// Validates all bindings and returns errors.
    public func validateBindings() -> [String] {
        var errors: [String] = []
        
        for binding in bindings {
            if binding.variableKey.isEmpty {
                errors.append("Variable key is empty for binding to \(binding.targetField)")
            }
            
            if binding.targetField.isEmpty {
                errors.append("Target field is empty for binding to variable \(binding.variableKey)")
            }
            
            if binding.targetObject.isEmpty {
                errors.append("Target object is empty for binding to variable \(binding.variableKey)")
            }
            
            // Check that the variable exists
            if !documentVariables.contains(where: { $0.key == binding.variableKey }) {
                errors.append("Variable '\(binding.variableKey)' not found in document variables")
            }
        }
        
        return errors
    }
    
    /// Clears inactive bindings.
    public func clearInactiveBindings() {
        bindings.removeAll { !$0.active }
    }
    
    /// Gets all active bindings.
    public func getActiveBindings() -> [DocumentVariableBinding] {
        bindings.filter { $0.active }
    }
    
    /// Gets bindings by target object.
    public func getBindings(byTargetObject object: String) -> [DocumentVariableBinding] {
        bindings.filter { $0.targetObject == object }
    }
    
    /// Gets bindings by variable key.
    public func getBindings(byVariableKey variableKey: String) -> [DocumentVariableBinding] {
        bindings.filter { $0.variableKey == variableKey }
    }
    
    /// Resolves a variable value from the document.
    public static func resolveVariable(
        _ key: String,
        in variables: [DocumentVariable]
    ) -> Double? {
        guard let variable = variables.first(where: { $0.key == key }) else {
            return nil
        }
        return Double(variable.value)
    }
}
