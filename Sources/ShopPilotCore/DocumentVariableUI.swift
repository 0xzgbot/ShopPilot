#if canImport(SwiftUI)

import SwiftUI

// MARK: - VariableBindingRow

/// A SwiftUI row showing a single variable binding with editable fields.
public struct VariableBindingRow: View {
    @Binding var binding: DocumentVariableBinding
    
    public init(binding: Binding<DocumentVariableBinding>) {
        self._binding = binding
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Active toggle
            Toggle("", isOn: $binding.active)
                .toggleStyle(.checkbox)
                .labelsHidden()
            
            // Variable key
            TextField("Variable", text: $binding.variableKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
            
            // Target object
            TextField("Object", text: $binding.targetObject)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
            
            // Target field
            TextField("Field", text: $binding.targetField)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
            
            // Fallback value
            TextField("Fallback", value: $binding.fallbackValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 80)
            
            // Remove button
            Button(action: {
                // Handled by parent via removeBinding
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(binding.active ? Color.clear : Color.gray.opacity(0.2))
    }
}

// MARK: - VariableBindingList

/// A SwiftUI list showing all variable bindings with add/remove controls.
public struct VariableBindingList: View {
    @Binding var bindings: [DocumentVariableBinding]
    @State private var showValidation = false
    @State private var validationErrors: [String] = []
    
    public init(bindings: Binding<[DocumentVariableBinding]>) {
        self._bindings = bindings
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Variable Bindings")
                    .font(.headline)
                
                Spacer()
                
                // Validation button
                Button(action: {
                    showValidation = true
                }) {
                    Image(systemName: "checkmark.seal")
                }
                .help("Validate bindings")
                
                // Add binding button
                Button(action: addBinding) {
                    Image(systemName: "plus.circle.fill")
                }
                .help("Add binding")
            }
            
            // Binding rows
            if bindings.isEmpty {
                Text("No bindings configured. Click + to add one.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(bindings.indices, id: \.self) { index in
                    HStack {
                        VariableBindingRow(binding: $bindings[index])
                        
                        // Remove button
                        Button(action: {
                            bindings.remove(at: index)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                }
            }
            
            // Validation status
            if !validationErrors.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Validation Errors:")
                        .font(.caption)
                        .bold()
                    ForEach(validationErrors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onChange(of: bindings) {
            updateValidation()
        }
    }
    
    // MARK: - Actions
    
    private func addBinding() {
        let binding = DocumentVariableBinding(
            variableKey: "width",
            targetField: "width",
            targetObject: "Sheet"
        )
        bindings.append(binding)
    }
    
    private func updateValidation() {
        // Validation would require access to VariableBindingManager
        // This is a simplified version for standalone use
        validationErrors = bindings.filter {
            $0.variableKey.isEmpty || $0.targetField.isEmpty || $0.targetObject.isEmpty
        }.map {
            "Binding '\($0.id.uuidString.prefix(8))' has empty fields"
        }
    }
}

// MARK: - VariableBindingManagerView

/// SwiftUI view wrapping VariableBindingManager for full CRUD.
public struct VariableBindingManagerView: View {
    @ObservedObject var manager: VariableBindingManager
    
    public init(manager: VariableBindingManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Document variables section
            VStack(alignment: .leading, spacing: 8) {
                Text("Document Variables")
                    .font(.headline)
                
                ForEach(manager.documentVariables) { variable in
                    HStack {
                        Text(variable.key)
                            .font(.body)
                        Spacer()
                        Text(variable.value)
                            .foregroundColor(.gray)
                    }
                    .padding(4)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Bindings section
            VariableBindingList(bindings: $manager.bindings)
            
            // Action buttons
            HStack {
                Button("Clear Inactive") {
                    manager.clearInactiveBindings()
                }
                
                Spacer()
                
                Button("Validate All") {
                    let errors = manager.validateBindings()
                    if errors.isEmpty {
                        // All valid
                    }
                }
            }
        }
        .padding(16)
    }
}

#endif
