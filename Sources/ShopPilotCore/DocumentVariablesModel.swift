import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - Document Variables Model

/// Observable model managing a collection of document variables with
/// add/update/delete operations and JSON persistence via FileManager.
public final class DocumentVariablesModel: ObservableObject {
    
    // MARK: - Published State
    
    /// All document variables, ordered by insertion.
    @Published public var variables: [DocumentVariable] = []
    
    // MARK: - Private State
    
    private let fileManager: FileManager
    private let storageKey: String
    private let customStorageURL: URL?
    
    /// All unique categories currently in use (sorted).
    public var categories: [String] {
        Array(Set(variables.map(\.category))).sorted()
    }
    
    // MARK: - Init
    
    /// Creates a new model backed by the given file manager.
    /// - Parameters:
    ///   - fileManager: FileManager instance (defaults to .default).
    ///   - storageKey: Key used to derive the persistence file path.
    ///   - customStorageURL: Optional explicit URL to use for storage (for testing).
    public init(fileManager: FileManager = .default, storageKey: String = "documentVariables", customStorageURL: URL? = nil) {
        self.fileManager = fileManager
        self.storageKey = storageKey
        self.customStorageURL = customStorageURL
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new variable with the given key, value, and category.
    /// - Returns: The newly created DocumentVariable.
    @discardableResult
    public func addVariable(key: String, value: String, category: String = DocumentVariable.defaultCategory) -> DocumentVariable {
        let variable = DocumentVariable(key: key, value: value, category: category)
        variables.append(variable)
        return variable
    }
    
    /// Update an existing variable's key and value by its id.
    /// - Returns: true if the variable was found and updated.
    @discardableResult
    public func updateVariable(id: UUID, key: String, value: String) -> Bool {
        guard let index = variables.firstIndex(where: { $0.id == id }) else {
            return false
        }
        variables[index].key = key
        variables[index].value = value
        return true
    }
    
    /// Delete a variable by its id.
    /// - Returns: true if the variable was found and deleted.
    @discardableResult
    public func deleteVariable(id: UUID) -> Bool {
        guard let index = variables.firstIndex(where: { $0.id == id }) else {
            return false
        }
        variables.remove(at: index)
        return true
    }
    
    /// Filter variables by category.
    /// - Parameter category: The category to filter by. Pass `nil` or empty to return all.
    /// - Returns: Variables matching the category, preserving original order.
    public func variables(byCategory category: String) -> [DocumentVariable] {
        guard !category.isEmpty else {
            return variables
        }
        return variables.filter { $0.category == category }
    }
    
    /// Get all unique categories currently stored.
    @available(*, deprecated, message: "Use the computed 'categories' property instead.")
    public func getCategories() -> [String] {
        categories
    }
    
    // MARK: - Persistence
    
    /// Persist variables to a JSON file in the app's application support directory.
    /// - Returns: true if the save succeeded.
    @MainActor
    public func save() -> Bool {
        do {
            let url = storageURL()
            let data = try JSONEncoder().encode(variables)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("[DocumentVariablesModel] Failed to save variables: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Load variables from the persisted JSON file.
    /// - Returns: true if the load succeeded and variables were populated.
    @MainActor
    public func load() -> Bool {
        do {
            let url = storageURL()
            guard fileManager.fileExists(atPath: url.path) else {
                variables = []
                return false
            }
            let data = try Data(contentsOf: url)
            variables = try JSONDecoder().decode([DocumentVariable].self, from: data)
            return true
        } catch {
            print("[DocumentVariablesModel] Failed to load variables: \(error.localizedDescription)")
            variables = []
            return false
        }
    }
    
    /// Clear all persisted variables and reset in-memory state.
    @MainActor
    public func clear() {
        variables.removeAll()
        do {
            let url = storageURL()
            try? fileManager.removeItem(at: url)
        } catch {
            print("[DocumentVariablesModel] Failed to clear storage: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private
    
    /// Compute the file URL for storing variables.
    /// Uses customStorageURL if provided (for testing), otherwise defaults
    /// to the app's Application Support directory.
    private func storageURL() -> URL {
        if let customURL = customStorageURL {
            // Ensure parent directory exists
            try? fileManager.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            return customURL
        }
        let supportsDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let packageDir = supportsDir.appendingPathComponent("ShopPilot")
        try? fileManager.createDirectory(at: packageDir, withIntermediateDirectories: true)
        return packageDir.appendingPathComponent("\(storageKey).json")
    }
}
