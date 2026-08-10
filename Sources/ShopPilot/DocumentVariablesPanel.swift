import SwiftUI
import ShopPilotCore

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

// MARK: - Driven Dimensions Panel (SPK-0807)

/// Parametric-lite: expressions over the document variables, evaluated live
/// and persisted on the Job. Each row shows key → expression = resolved
/// value; add/edit/remove route through the session (undo + dirty).
struct DrivenDimensionsPanelView: View {
    @ObservedObject var session: AppSession
    @State private var showAddForm = false
    @State private var newKey = ""
    @State private var newExpression = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DRIVEN DIMENSIONS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("(\(session.job.drivenDimensions.count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if session.job.drivenDimensions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No driven dimensions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("e.g. halfWidth = stockWidth / 2")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(session.job.drivenDimensions) { dim in
                            HStack(spacing: 6) {
                                Text(dim.key)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text("=")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(dim.expression)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(valueText(dim))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(valueColor(dim))
                                Button {
                                    session.removeDrivenDimension(id: dim.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this driven dimension")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            if showAddForm {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Key (e.g. halfWidth)", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Expression (e.g. $width / 2)", text: $newExpression)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Add") { addCurrent() }
                            .buttonStyle(.borderedProminent)
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                                      || newExpression.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { showAddForm = false }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(12)
            } else {
                Button {
                    newKey = ""
                    newExpression = ""
                    showAddForm = true
                } label: {
                    Label("Add Driven Dimension", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .frame(minHeight: 180)
    }

    private func addCurrent() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        let expr = newExpression.trimmingCharacters(in: .whitespaces)
        if session.addDrivenDimension(key: key, expression: expr) != nil {
            showAddForm = false
        }
    }

    private func valueText(_ dim: DrivenDimension) -> String {
        guard let value = session.drivenDimensionValue(dim) else { return "?" }
        return String(format: "%.3f", value)
    }

    private func valueColor(_ dim: DrivenDimension) -> Color {
        session.drivenDimensionValue(dim) == nil ? .red : .primary
    }
}

// MARK: - Golden Jobs Panel (SPK-0808)

/// Runs the seeded production golden jobs against the REAL toolpath engines
/// and shows pass/fail + measured span per run. One button per job.
struct GoldenJobsPanelView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GOLDEN JOBS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(passedCount)/\(session.goldenJobManager.jobs.count) passed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if session.goldenJobManager.jobs.isEmpty {
                VStack(spacing: 8) {
                    Text("No golden jobs seeded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Seed Default Calibration") {
                        let job = ProductionGoldenJobConfig(
                            name: "Calibration 50×50",
                            description: "Golden profile on the 50mm calibration square",
                            jobType: .calibration,
                            expectedDimensions: ["width": 50, "depth": 50],
                            tolerance: 0.5
                        )
                        session.goldenJobManager.jobs.append(job)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(session.goldenJobManager.jobs.enumerated()), id: \.element.name) { _, job in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(job.name)
                                        .font(.callout.weight(.medium))
                                    Text(job.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                statusBadge(job.status)
                                Button("Run") {
                                    let result = session.goldenJobManager.runJob(job)
                                    session.statusMessage = result.notes
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minHeight: 140)
    }

    private var passedCount: Int {
        session.goldenJobManager.jobs.filter { $0.status == .passed }.count
    }

    @ViewBuilder
    private func statusBadge(_ status: GoldenJobStatus) -> some View {
        switch status {
        case .passed:
            Text("PASS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        case .failed:
            Text("FAIL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
        case .warning:
            Text("WARN")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
        default:
            Text(status.rawValue.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
