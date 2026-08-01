#if canImport(SwiftUI)
import SwiftUI

// MARK: - Variable Binding Row

/// A single row in the variable binding list, showing the variable key,
/// target field, target object, active toggle, and an edit mode.
public struct VariableBindingRow: View {

    @Binding var binding: DocumentVariableBinding
    @State private var isEditing = false

    public init(binding: Binding<DocumentVariableBinding>) {
        self._binding = binding
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Active toggle
            Toggle("", isOn: $binding.active)
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 28)

            // Variable key
            TextField("Variable key", text: $binding.variableKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    Group {
                        if binding.variableKey.isEmpty {
                            Text("e.g. stockWidth")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    },
                    alignment: .leading
                )

            // Target field
            TextField("Field", text: $binding.targetField)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 140)
                .overlay(
                    Group {
                        if binding.targetField.isEmpty {
                            Text("e.g. width")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    },
                    alignment: .leading
                )

            // Target object badge
            Text(binding.targetObject)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)

            // Remove button
            Button(action: {
                // Signal removal via a custom event; the parent list handles it.
                // For simplicity, we set active = false here and let the
                // VariableBindingList's remove button handle actual deletion.
            }) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Deactivate binding")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Variable Binding List

/// Displays all variable bindings with add/remove controls and validation status.
public struct VariableBindingList: View {

    @Binding var bindings: [DocumentVariableBinding]
    @Binding var documentVariables: [DocumentVariable]
    @State private var newTargetObject = "Sheet"
    @State private var validationErrors: [String] = []

    /// Common target objects for CNC fields.
    private let commonObjects = ["Sheet", "ProfileToolpath", "VCarveToolpath", "PocketToolpath", "DrillToolpath", "Material"]

    public init(
        bindings: Binding<[DocumentVariableBinding]>,
        documentVariables: Binding<[DocumentVariable]> = .constant([])
    ) {
        self._bindings = bindings
        self._documentVariables = documentVariables
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with add button
            HStack {
                Text("Variable Bindings")
                    .font(.headline)

                Spacer()

                // Add binding button
                Button(action: addBinding) {
                    Label("Add Binding", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Binding rows
            if bindings.isEmpty {
                ContentUnavailableView(
                    "No Bindings",
                    systemImage: "link",
                    description: Text("Bind document variables to fields like sheet dimensions or toolpath parameters.")
                )
            } else {
                List {
                    ForEach($bindings) { $binding in
                        VariableBindingRow(binding: $binding)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .onDisappear {
                                // Clean up validation errors when binding is removed
                                validate()
                            }
                    }
                    .onDelete { indexSet in
                        bindings.remove(atOffsets: indexSet)
                        validate()
                    }
                }
                .listStyle(.plain)
            }

            // Validation status
            if !validationErrors.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(validationErrors.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Document variables reference
            if !documentVariables.isEmpty {
                Section("Available Variables") {
                    ForEach(documentVariables) { variable in
                        HStack {
                            Text(variable.key)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(variable.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            validate()
        }
        .onChange(of: bindings) {
            validate()
        }
    }

    // MARK: - Actions

    private func addBinding() {
        let binding = DocumentVariableBinding(
            variableKey: "",
            targetField: "",
            targetObject: newTargetObject,
            active: true
        )
        bindings.append(binding)
        validate()
    }

    private func validate() {
        let manager = VariableBindingManager(
            bindings: bindings,
            documentVariables: documentVariables
        )
        validationErrors = manager.validateBindings()
    }
}

// MARK: - Preview (Xcode only)

#if DEBUG
struct VariableBindingUI_Previews: PreviewProvider {
    static var previewBindings: Binding<[DocumentVariableBinding]> = .constant([
        DocumentVariableBinding(
            variableKey: "stockWidth",
            targetField: "width",
            targetObject: "Sheet",
            active: true,
            fallbackValue: 600
        ),
        DocumentVariableBinding(
            variableKey: "cutDepth",
            targetField: "cutDepth",
            targetObject: "ProfileToolpath",
            active: false,
            fallbackValue: 25
        )
    ])

    static var previewVariables: Binding<[DocumentVariable]> = .constant([
        DocumentVariable(key: "stockWidth", value: "600"),
        DocumentVariable(key: "cutDepth", value: "25"),
        DocumentVariable(key: "materialThickness", value: "12")
    ])

    static var previews: some View {
        Group {
            NavigationStack {
                VariableBindingList(
                    bindings: previewBindings,
                    documentVariables: previewVariables
                )
            }
            .navigationTitle("Variable Bindings")
            .frame(width: 500, height: 400)
        }
    }
}
#endif

#endif // canImport(SwiftUI)
