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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 1100, minHeight: 700)
        }
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
