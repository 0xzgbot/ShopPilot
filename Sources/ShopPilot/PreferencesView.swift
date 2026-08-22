import SwiftUI
import ShopPilotCore

// MARK: - Preferences View (Settings entry point)

struct PreferencesView: View {

    @AppStorage("shop_pilot_units")       private(set) var units:       String = "mm"
    @AppStorage("shop_pilot_theme")        private(set) var theme:       String = "system"
    @AppStorage("shop_pilot_pro_skip")     private(set) var proSkip:     Bool   = false
    /// SPK-1900c — Beginner/Advanced experience mode.
    @AppStorage("shop_pilot_beginner_mode") private(set) var beginnerMode: Bool = false

    /// UI-polish cluster — customizable shortcuts. Loaded once on appear and
    /// written back through `ShortcutStore` so the app-agnostic store stays
    /// the single source of truth.
    @State private var shortcutOverrides: [String: String] = ShortcutStore.overrides()

    /// SPK-1317 — menu-bar shortcuts (New Job, stages, palette…) read from
    /// the shared registry; remaps here live-update the app menus.
    @ObservedObject private var menuShortcuts = ShortcutRegistry.shared

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
                // SPK-1900c — experience mode switch (VP H-101 port).
                Picker("Experience mode", selection: $beginnerMode) {
                    Text("Beginner — guided, fewer panels").tag(true)
                    Text("Advanced — everything").tag(false)
                }
                .pickerStyle(.inline)
                .help("Beginner hides pro setup panels and import formats; nothing is deleted.")
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

            // ── Menu-bar shortcuts (SPK-1317) ────────────────
            // The app's menu-bar commands (New Job, stages, palette…) read
            // their key/modifiers from ShortcutRegistry.shared, so remaps
            // here live-update the menus.
            Section {
                ForEach(menuShortcuts.bindings) { binding in
                    HStack {
                        Text(binding.title)
                        Spacer()
                        TextField("Key", text: menuShortcutKeyBinding(for: binding.id))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Picker("Mods", selection: menuShortcutModsBinding(for: binding.id)) {
                            Text("⌘").tag(["command"])
                            Text("⌘⇧").tag(["command", "shift"])
                            Text("⌘⌥").tag(["command", "option"])
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
            } header: {
                Text("Menu Bar Shortcuts")
            } footer: {
                HStack {
                    Button("Reset Menu Shortcuts") {
                        menuShortcuts.resetAll()
                    }
                    Text("Key = single character (e.g. n, 4). Modifiers apply to the key.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    /// SPK-1317 — live binding to a menu command's key; writes through the
    /// shared registry (which re-renders the app menus).
    private func menuShortcutKeyBinding(for id: String) -> Binding<String> {
        Binding(
            get: { menuShortcuts.binding(for: id)?.key ?? "" },
            set: { newValue in
                let key = ShortcutStore.normalize(newValue)
                guard !key.isEmpty, let current = menuShortcuts.binding(for: id) else { return }
                _ = menuShortcuts.setOverride(id: id, key: key, modifiers: current.modifiers)
            }
        )
    }

    /// SPK-1317 — live binding to a menu command's modifier set.
    private func menuShortcutModsBinding(for id: String) -> Binding<[String]> {
        Binding(
            get: { menuShortcuts.binding(for: id)?.modifiers ?? ["command"] },
            set: { newMods in
                guard let current = menuShortcuts.binding(for: id) else { return }
                _ = menuShortcuts.setOverride(id: id, key: current.key, modifiers: newMods)
            }
        )
    }
}

// Note: #Preview requires Xcode's PreviewsMacros plugin; not available in CLI builds.
