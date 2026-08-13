import SwiftUI
import ShopPilotCore
import ShopPilotSerial

@main
struct ShopPilotApp: App {
    @StateObject private var session = AppSession()

    init() {
        // Register real serial transport for Core factory callers (sim remains default in UI).
        ShopPilotCore.TransportFactory.serialTransportBuilder = { config in
            // SPK-1401a: the factory hands the UI's SerialConfig (port/baud)
            // to the serial builder — the config argument is used, not `_`.
            // RealSerialTransport applies it at open(config:) (port path +
            // termios baud, SPK-1401b).
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
                    // SPK-1601 — File New replaces the session (blank
                    // Untitled + Setup), not a stage-only switch.
                    _ = session.newJob()
                }
                .keyboardShortcut(shortcut("file.new"))

                // SPK-1500 — File menu Open Job… uses the SAME session path
                // as the Welcome sheet (handleCommand(.openJob) →
                // openPackageFromPanel), so ⌘O and the File menu both open the
                // real package picker. The ⌘O key is the existing Commands
                // palette binding (CommandID.openJob = "o").
                Button("Open Job…") {
                    session.handleCommand(.openJob)
                }
                .keyboardShortcut(shortcut("file.open"))

                // SPK-1600 — File Save / Save As. Plain Save re-saves to
                // packageURL when known, else prompts; Save As always prompts
                // and updates packageURL (same session path as ⌘K Save).
                Button("Save") {
                    session.savePackageFromPanel()
                }
                .keyboardShortcut(shortcut("file.save"))

                Button("Save As…") {
                    session.savePackageFromPanel(isSaveAs: true)
                }
                .keyboardShortcut(shortcut("file.saveAs"))
            }

            // SPK-1606 — Edit menu Undo/Redo call the session stack (the
            // 1403b snapshot undo). Placed before the default group so the
            // session's stack is what ⌘Z / ⇧⌘Z drive.
            CommandGroup(before: .undoRedo) {
                Button("Undo") {
                    if session.undo() {
                        session.statusMessage = "Undo"
                    }
                }
                .keyboardShortcut(shortcut("edit.undo"))
                .disabled(!session.canUndo)

                Button("Redo") {
                    if session.redo() {
                        session.statusMessage = "Redo"
                    }
                }
                .keyboardShortcut(shortcut("edit.redo"))
                .disabled(!session.canRedo)
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

            // SPK-1605 — a real Help menu (replaces the default). Safety is
            // always reachable from here; the scope/README links open the
            // repo docs (local files when present).
            CommandGroup(replacing: .help) {
                Button("Safety Notice") {
                    session.showSafetyDisclaimer = true
                }
                .help("Read the machine-safety notice before your first cut")

                Divider()

                Button("ShopPilot README") {
                    if let url = Bundle.main.url(forResource: "README", withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    } else if let repo = URL(string: "https://github.com/0xzgbot/ShopPilot") {
                        NSWorkspace.shared.open(repo)
                    }
                }

                Button("Lean CNC Scope") {
                    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    let scope = base.appendingPathComponent("docs/planning/LEAN_CNC_SCOPE.md")
                    if FileManager.default.fileExists(atPath: scope.path) {
                        NSWorkspace.shared.open(scope)
                    }
                }
            }

            CommandMenu("ShopPilot") {
                Button("Command Palette…") {
                    session.showCommandPalette = true
                }
                .keyboardShortcut(shortcut("palette"))

                // Opens the standard macOS Settings window (Settings scene
                // below) — NOT a sheet, so it keeps the native close button,
                // ⌘W, and Escape dismissal.
                SettingsLink {
                    Text("Preferences…")
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
