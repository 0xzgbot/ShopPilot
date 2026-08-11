import SwiftUI
import ShopPilotCore

// MARK: - Post Studio (SPK-1000)

/// Post Studio: manage post templates (shipped GRBL set + user templates)
/// with a raw-recipe editor and the document-variable blocks that resolve at
/// export. User templates persist in UserDefaults via `PostTemplateStore`.
struct PostStudioView: View {
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var editingID: String?
    @State private var name = ""
    @State private var summary = ""
    @State private var text = ""
    @State private var rotaryWrap = false
    @State private var wrapDiameter = "50.0"
    @State private var showNewForm = false
    @State private var confirmDeleteID: String?

    private var store: PostTemplateStore { session.postTemplateStore }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Post Studio")
                    .font(.headline)
                Spacer()
                Text("\(store.allTemplates.count) templates · \(session.postTemplateVariables.count) variables")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            HSplitView {
                // Template list (shipped + user).
                List {
                    Section("Shipped") {
                        ForEach(PostTemplate.shipped) { template in
                            templateRow(template, isUser: false)
                        }
                    }
                    Section("User Templates") {
                        if store.userTemplates.isEmpty {
                            Text("None yet — create one below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.userTemplates) { template in
                            templateRow(template, isUser: true)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 240)

                // Editor / variable panel.
                VStack(alignment: .leading, spacing: 10) {
                    if let editingID, let template = store.template(byID: editingID) {
                        editor(for: template, id: editingID)
                    } else {
                        Text("Select a template to inspect it, or create a new user template.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(12)
                .frame(minWidth: 320)
            }

            Divider()

            HStack {
                Button {
                    startNewTemplate()
                } label: {
                    Label("New User Template", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(showNewForm)

                Spacer()

                // Done dismisses the whole sheet — it must close even when
                // the new-template form was never opened.
                Button("Done") { showNewForm = false; dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .alert("Delete Template?", isPresented: Binding(
            get: { confirmDeleteID != nil },
            set: { if !$0 { confirmDeleteID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    _ = store.removeUserTemplate(id: id)
                    if editingID == id { editingID = nil }
                }
                confirmDeleteID = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteID = nil }
        } message: {
            Text("This user template will be removed from the post picker. Shipped templates cannot be deleted.")
        }
        // Esc closes the whole sheet like any other dialog.
        .onExitCommand { dismiss() }
    }

    private func templateRow(_ template: PostTemplate, isUser: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(template.name)
                    .font(.callout.weight(.medium))
                Text(template.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isUser {
                Button {
                    confirmDeleteID = template.id
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete this user template")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingID = template.id }
        .background(editingID == template.id ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private func editor(for template: PostTemplate, id: String) -> some View {
        let isShipped = PostTemplate.shipped.contains { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(isShipped ? "Shipped template (read-only)" : "User template")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name", text: Binding(
                    get: { template.name },
                    set: { _ in } // shipped + user edits handled via save
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(isShipped)

                TextField("Summary", text: Binding(
                    get: { template.summary },
                    set: { _ in }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(isShipped)

                Toggle("Rotary wrap (Y → A)", isOn: Binding(
                    get: { template.rotaryWrap },
                    set: { _ in }
                ))
                .disabled(isShipped)

                Text("Recipe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { template.text },
                    set: { newText in
                        guard !isShipped else { return }
                        var updated = template
                        updated = PostTemplate(
                            id: template.id, name: template.name, summary: template.summary,
                            text: newText, rotaryWrap: template.rotaryWrap,
                            wrapDiameterMm: template.wrapDiameterMm
                        )
                        store.upsertUserTemplate(updated)
                    }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                // Variable block surface: the keys the document fills at export.
                Text("Variable blocks (resolved at export)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowGrid(keys: PostTemplateStore.documentVariableKeys)
            }
            .padding(8)
        }
    }

    private func startNewTemplate() {
        let base = PostTemplate.grbl(units: .millimeter)
        let id = "user-\(UUID().uuidString.prefix(8))"
        let fresh = PostTemplate(
            id: id,
            name: "My Post",
            summary: "Custom post template",
            text: base.text,
            rotaryWrap: false,
            wrapDiameterMm: 50
        )
        store.upsertUserTemplate(fresh)
        editingID = id
        showNewForm = true
    }
}

/// Simple wrap of variable-key chips (the Post Studio block surface).
private struct FlowGrid: View {
    let keys: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text("$\(key)")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
