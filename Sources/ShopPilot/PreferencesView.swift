import SwiftUI
import ShopPilotCore

// MARK: - Preferences View (Settings entry point)

struct PreferencesView: View {

    @AppStorage("shop_pilot_units")       private(set) var units:       String = "mm"
    @AppStorage("shop_pilot_theme")        private(set) var theme:       String = "system"
    @AppStorage("shop_pilot_pro_skip")     private(set) var proSkip:     Bool   = false

    /// UI-polish cluster — customizable shortcuts. Loaded once on appear and
    /// written back through `ShortcutStore` so the app-agnostic store stays
    /// the single source of truth.
    @State private var shortcutOverrides: [String: String] = ShortcutStore.overrides()

    var body: some View {
        Form {
            // ── Units ────────────────────────────────────────
            Section("Units") {
                Picker("Unit System", selection: $units) {
                    Text("Millimeters (mm)").tag("mm")
                    Text("Inches (inch)").tag("inch")
                }
                .pickerStyle(.inline)
            }

            // ── Theme ────────────────────────────────────────
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .pickerStyle(.inline)
            }

            // ── Pro-skip Checklist ───────────────────────────
            Section("Pro Mode") {
                Toggle("Skip beginner coach", isOn: $proSkip)
                    .help(
                        "When enabled, the beginner coaching overlay will be skipped on first launch."
                    )
            }

            // ── Keyboard shortcuts (UI-polish cluster) ───────
            Section {
                ForEach(CommandID.allCases.filter { $0.keyboardShortcut != nil || shortcutOverrides[$0.rawValue] != nil }, id: \.rawValue) { cmd in
                    HStack {
                        Text(cmd.name)
                        Spacer()
                        TextField("Shortcut", text: shortcutBinding(for: cmd))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .help("Shortcut key, e.g. n, shift+z, delete. Empty restores the default.")
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Button("Reset All to Defaults") {
                    ShortcutStore.resetAll()
                    shortcutOverrides = ShortcutStore.overrides()
                }
            }

            // Spacer so form doesn't stretch awkwardly.
            Spacer()
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 320)
    }

    /// Live binding into the local overrides map; writes through the store.
    private func shortcutBinding(for cmd: CommandID) -> Binding<String> {
        Binding(
            get: {
                shortcutOverrides[cmd.rawValue] ?? cmd.keyboardShortcut ?? ""
            },
            set: { newValue in
                let normalized = ShortcutStore.normalize(newValue)
                ShortcutStore.setOverride(normalized.isEmpty ? nil : normalized, for: cmd.rawValue)
                shortcutOverrides = ShortcutStore.overrides()
            }
        )
    }
}

// Note: #Preview requires Xcode's PreviewsMacros plugin; not available in CLI builds.
