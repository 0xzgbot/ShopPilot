import SwiftUI

/// Horizontal stage rail with 6 selectable stages.
/// Renders as a toolbar-style button row; tapping a stage selects it and
/// triggers the onSelection closure so the parent can switch content.
struct StageRailView: View {
    /// The currently selected stage (binding for two-way sync).
    @Binding var selectedStage: Stage

    /// Called when the user taps a different stage.
    let onStageChange: (Stage) -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Stage.allCases) { stage in
                StageButton(stage: stage, isSelected: selectedStage == stage) {
                    selectedStage = stage
                    onStageChange(stage)
                }

                // Divider between buttons (not after the last one).
                if stage != Stage.allCases.last {
                    Divider()
                        .frame(height: 32)
                        .padding(.vertical, 4)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Stage Button (internal helper)

private struct StageButton: View {
    let stage: Stage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: stage.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                Text(stage.title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Stage Content View (placeholder — switches based on selected stage)

/// Placeholder content view that displays a message for the active stage.
/// Real stage-specific views will be wired in as each stage is implemented.
struct StageContentView: View {
    let stage: Stage

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: stage.icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text(stage.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(stage.title) stage — coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// Note: #Preview requires Xcode's PreviewsMacros plugin; not available in CLI builds.
