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
        // SPK-UI606: single main window (not WindowGroup) so relaunch doesn't
        // open a restored frame plus a brand-new default window.
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
                .keyboardShortcut("n", modifiers: .command)

                Button("Command Palette…") {
                    session.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandMenu("ShopPilot") {
                Button("Preferences…") {
                    session.showPreferences = true
                }
                .keyboardShortcut(",", modifiers: .command)

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
}
