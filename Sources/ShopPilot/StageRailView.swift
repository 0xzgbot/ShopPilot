import SwiftUI

/// The signature navigation object: a single segmented control carrying the
/// six stages of a job. The selection is one continuous shape that travels
/// between segments rather than six independently highlighted buttons, so a
/// stage change reads as movement along the job, not as a button press.
struct StageRailView: View {
    /// The currently selected stage (binding for two-way sync).
    @Binding var selectedStage: Stage

    /// Called when the user taps a different stage.
    let onStageChange: (Stage) -> Void

    @Namespace private var selectionNamespace
    @State private var hoveredStage: Stage?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Stage.allCases) { stage in
                StageSegment(
                    stage: stage,
                    isSelected: selectedStage == stage,
                    isHovered: hoveredStage == stage,
                    namespace: selectionNamespace
                ) {
                    guard selectedStage != stage else { return }
                    withAnimation(SP.Motion.stage) {
                        selectedStage = stage
                    }
                    onStageChange(stage)
                }
                .onHover { hovering in
                    hoveredStage = hovering ? stage : (hoveredStage == stage ? nil : hoveredStage)
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: SP.Radius.panel + 3, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SP.Radius.panel + 3, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Job stages")
    }
}

// MARK: - Segment

private struct StageSegment: View {
    let stage: Stage
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: stage.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .frame(width: 15)

                Text(stage.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
            .padding(.horizontal, SP.Space.m)
            .frame(height: 26)
            .contentShape(RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "stageSelection", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: SP.Radius.control, style: .continuous)
                        .fill(.primary.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(stage.title) — \(stage.intent) (⌘\(String(stage.shortcutCharacter)))")
        .accessibilityLabel(stage.title)
        .accessibilityHint(stage.intent)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// Note: #Preview requires Xcode's PreviewsMacros plugin; not available in CLI builds.
