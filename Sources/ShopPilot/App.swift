import SwiftUI
import ShopPilotCore
import ShopPilotSerial

@main
struct ShopPilotApp: App {
    @StateObject private var session = AppSession()

    init() {
        // Register real serial transport for Core factory callers (sim remains default in UI).
        ShopPilotCore.TransportFactory.serialTransportBuilder = { _ in
            RealSerialTransport()
        }
        // SPK-UI606: avoid restored-window + fresh-scene double launch after force-quit.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        // SPK-1317 — remappable shortcuts: every CommandGroup button below
        // reads its key/modifiers from the session's ShortcutRegistry, so a
        // Preferences pane can reassign them at runtime.
        Window("ShopPilot", id: "main") {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job") {
                    session.selectedStage = .setup
                }
                .keyboardShortcut(shortcut("file.new"))
            }

            CommandGroup(after: .undoRedo) {
                Button("Group") {
                    _ = session.applyGroup()
                }
                .keyboardShortcut(shortcut("edit.group"))

                Button("Ungroup") {
                    _ = session.applyUngroup()
                }
                .keyboardShortcut(shortcut("edit.ungroup"))
            }

            // Stage navigation belongs on the keyboard as well as the rail.
            CommandMenu("Stage") {
                ForEach(Stage.allCases) { stage in
                    Button(stage.title) {
                        withAnimation(SP.Motion.stage) { session.selectedStage = stage }
                    }
                    .keyboardShortcut(shortcut("stage.\(stage.rawValue)"))
                }
            }

            CommandMenu("ShopPilot") {
                Button("Command Palette…") {
                    session.showCommandPalette = true
                }
                .keyboardShortcut(shortcut("palette"))

                Button("Preferences…") {
                    session.showPreferences = true
                }
                .keyboardShortcut(shortcut("prefs"))

                Button("Show Safety Notice") {
                    session.showSafetyDisclaimer = true
                }

                Divider()

                Button("Generate Profile Toolpath") {
                    session.generateProfileToolpath()
                }

                Button("Go to Machine") {
                    session.loadFixtureGCodeIfNeeded()
                    session.selectedStage = .machine
                }
            }
        }

        Settings {
            PreferencesView()
        }
    }

    /// Resolve a command's current key/modifiers from the shared shortcut
    /// registry, falling back to the shipped default when the id is unknown.
    /// Reads ShortcutRegistry.shared so Preferences remaps live-update.
    private func shortcut(_ id: String) -> KeyboardShortcut {
        guard let binding = ShortcutRegistry.shared.binding(for: id) else {
            return KeyboardShortcut("n", modifiers: .command)
        }
        let key = KeyEquivalent(Character(binding.key))
        var modifiers: EventModifiers = []
        for name in binding.modifiers {
            switch name {
            case "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "option": modifiers.insert(.option)
            case "control": modifiers.insert(.control)
            default: break
            }
        }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
