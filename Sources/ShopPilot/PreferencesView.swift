import SwiftUI

// MARK: - Preferences View (Settings entry point)

struct PreferencesView: View {

    @AppStorage("shop_pilot_units")       private(set) var units:       String = "mm"
    @AppStorage("shop_pilot_theme")        private(set) var theme:       String = "system"
    @AppStorage("shop_pilot_pro_skip")     private(set) var proSkip:     Bool   = false

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

            // Spacer so form doesn't stretch awkwardly.
            Spacer()
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 250)
    }
}

// Note: #Preview requires Xcode's PreviewsMacros plugin; not available in CLI builds.
