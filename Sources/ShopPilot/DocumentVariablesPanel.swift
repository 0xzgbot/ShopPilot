import SwiftUI

// MARK: - Document Variable

/// A user-defined key-value pair attached to a ShopPilot document.
/// Examples: material, stock size, project name, toolpath template.
public struct DocumentVariable: Identifiable, Codable, Hashable {
    public let id: UUID
    public var key: String
    public var value: String
    public var category: String
    
    /// Default category used when none is specified.
    public static let defaultCategory = "General"
    
    public init(id: UUID = UUID(), key: String, value: String, category: String = DocumentVariable.defaultCategory) {
        self.id = id
        self.key = key
        self.value = value
        self.category = category
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: DocumentVariable, rhs: DocumentVariable) -> Bool {
        lhs.id == rhs.id
    }
}

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

// MARK: - Document Variables Panel View

/// SwiftUI panel for managing document variables.
/// Displays a table of key-value pairs with add/edit/delete controls
/// and a category filter dropdown.
public struct DocumentVariablesPanelView: View {
    
    @ObservedObject var model: DocumentVariablesModel
    
    @State private var filterCategory: String = ""
    @State private var showAddForm = false
    @State private var editingVariable: DocumentVariable? = nil
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newCategory = DocumentVariable.defaultCategory
    @State private var showingDeleteConfirmation = false
    @State private var variableToDelete: DocumentVariable? = nil
    
    /// Whether any variables exist.
    public var hasVariables: Bool { !model.variables.isEmpty }
    
    /// Count of currently visible (filtered) variables.
    public var visibleCount: Int {
        if filterCategory.isEmpty {
            return model.variables.count
        }
        return model.variables(byCategory: filterCategory).count
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("DOCUMENT VARIABLES")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("(\(visibleCount))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Toolbar: category filter + add button
            HStack(spacing: 8) {
                // Category filter
                Menu {
                    Button("All Categories") {
                        filterCategory = ""
                    }
                    Divider()
                    ForEach(model.categories, id: \.self) { cat in
                        Button(cat) {
                            filterCategory = cat
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.secondary)
                        Text(filterCategory.isEmpty ? "All" : filterCategory)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                // Add button
                Button(action: {
                    editingVariable = nil
                    newKey = ""
                    newValue = ""
                    newCategory = DocumentVariable.defaultCategory
                    showAddForm = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add new variable")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            // Variables table
            if model.variables.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No variables defined")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add document variables")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Table of variables
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Column headers
                        HStack(spacing: 0) {
                            Text("KEY")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                            
                            Text("VALUE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                            
                            Text("CATEGORY")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                                .padding(.horizontal, 8)
                            
                            Spacer().frame(width: 40)
                        }
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.05))
                        
                        // Variable rows
                        ForEach(filteredVariables()) { variable in
                            variableRow(variable)
                        }
                    }
                }
            }
        }
        .alert("Delete Variable", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let varToDelete = variableToDelete {
                    model.deleteVariable(id: varToDelete.id)
                }
            }
        } message: {
            if let varToDelete = variableToDelete {
                Text("Are you sure you want to delete \"\(varToDelete.key)\"?")
            }
        }
        .sheet(isPresented: $showAddForm) {
            addEditSheet()
        }
    }
    
    // MARK: - Private Helpers
    
    /// Filtered list of variables based on the current category filter.
    private func filteredVariables() -> [DocumentVariable] {
        if filterCategory.isEmpty {
            return model.variables
        }
        return model.variables(byCategory: filterCategory)
    }
    
    /// A single row for a variable with edit and delete controls.
    private func variableRow(_ variable: DocumentVariable) -> some View {
        HStack(spacing: 0) {
            // Key
            Text(variable.key)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            
            // Value
            Text(variable.value)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            
            // Category
            Text(variable.category)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 8)
            
            // Actions
            HStack(spacing: 4) {
                Button(action: {
                    editingVariable = variable
                    newKey = variable.key
                    newValue = variable.value
                    newCategory = variable.category
                    showAddForm = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit")
                
                Button(action: {
                    variableToDelete = variable
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .frame(width: 40)
        }
        .padding(.vertical, 4)
        .background(Color.clear)
        .onTapGesture {
            editingVariable = variable
            newKey = variable.key
            newValue = variable.value
            newCategory = variable.category
            showAddForm = true
        }
    }
    
    /// Shared sheet for adding or editing a variable.
    private func addEditSheet() -> some View {
        NavigationView {
            Form {
                Section("Variable") {
                    TextField("Key (e.g., material)", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Value (e.g., Aluminum 6061)", text: $newValue)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Category", text: $newCategory)
                        .textFieldStyle(.roundedBorder)
                }
                
                if editingVariable != nil {
                    Section("Actions") {
                        Button("Save Changes", action: saveEdit)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        
                        Button("Delete", role: .destructive, action: deleteCurrent)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                }
            }
            .navigationTitle(editingVariable != nil ? "Edit Variable" : "New Variable")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdit() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddForm = false
                    }
                }
            }
        }
    }
    
    private func saveEdit() {
        guard !newKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        if let varToEdit = editingVariable {
            // Update existing
            _ = model.updateVariable(id: varToEdit.id, key: newKey, value: newValue)
        } else {
            // Add new
            _ = model.addVariable(key: newKey, value: newValue, category: newCategory)
        }
        
        showAddForm = false
    }
    
    private func deleteCurrent() {
        if let varToDelete = editingVariable {
            model.deleteVariable(id: varToDelete.id)
        }
        showAddForm = false
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
struct DocumentVariablesPanelView_Previews: PreviewProvider {
    static var previews: some View {
        let model = DocumentVariablesModel()
        model.variables = [
            DocumentVariable(key: "Material", value: "Aluminum 6061", category: "Material"),
            DocumentVariable(key: "Stock Size", value: "12 × 12 × 1 in", category: "Stock"),
            DocumentVariable(key: "Project Name", value: "Sign Prototype", category: "Project"),
        ]
        
        return DocumentVariablesPanelView(model: model)
            .frame(width: 320, height: 400)
    }
}
#endif
