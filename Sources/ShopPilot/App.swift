import SwiftUI

@main
struct ShopPilotApp: App {
    @State private var selectedStage: Stage = .setup

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        StageRailView(selectedStage: $selectedStage) { stage in
                            // Switch main content area based on selected stage.
                            // Real stage-specific views will be wired here as each stage is implemented.
                            print("Switched to stage: \(stage.title)")
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
