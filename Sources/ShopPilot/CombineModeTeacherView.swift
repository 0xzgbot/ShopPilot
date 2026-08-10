import SwiftUI
import ShopPilotCore

// MARK: - Combine Mode Teacher View

/// SPK-0704 — Visual combine-mode teacher.
/// Shows a lesson explaining the selected component's combine mode:
/// what it does, when to use it, and when NOT to use it.
/// Presented as a small info popover next to the combine-mode picker.
struct CombineModeTeacherView: View {
    let lesson: CombineModeLesson
    let componentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + icon
            HStack(spacing: 6) {
                Image(systemName: lesson.visualHint)
                    .font(.title3)
                    .accentColor(Color.accentColor)
                Text(lesson.title)
                    .font(.headline)
            }

            // Description
            Text(lesson.description)
                .font(.subheadline)

            Divider()

            // Example
            if !lesson.example.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Example").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(lesson.example)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Divider()

            // Use case
            VStack(alignment: .leading, spacing: 4) {
                Text("Use when").font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                Text(lesson.useCase)
                    .font(.caption)
            }

            Divider()

            // Anti-pattern
            VStack(alignment: .leading, spacing: 4) {
                Text("Do not use when").font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                Text(lesson.notUseCase)
                    .font(.caption)
            }

            Spacer()

            // Context hint
            if componentCount > 1 {
                Text("Tip: Change the mode using the picker in the component list above.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

// MARK: - Combine Mode Teacher Sheet

/// SPK-0704 — Full-screen teacher panel showing all 7 combine mode lessons
/// with a scenario recommender. Accessible from the Model stage ops bar.
struct CombineModeTeacherSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: OperationMode = .combineAdd
    @State private var scenarioText: String = ""
    @State private var recommendation: OperationMode? = nil

    private let allLessons = CombineModeTeacher.getAllLessons()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Combine Mode Teacher")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Two-column layout
            HStack(spacing: 20) {
                // Left: lesson detail for selected mode
                VStack(alignment: .leading, spacing: 12) {
                    if let lesson = CombineModeTeacher.getLesson(for: selectedMode) {
                        CombineModeTeacherView(
                            lesson: lesson,
                            componentCount: 0
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right: mode selector + recommender
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select a mode").font(.headline)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(allLessons) { lesson in
                                Button {
                                    selectedMode = lesson.mode
                                    recommendation = nil
                                } label: {
                                    HStack {
                                        Image(systemName: lesson.visualHint)
                                            .foregroundStyle(Color.accentColor)
                                        Text(lesson.title)
                                            .font(.subheadline)
                                        Spacer()
                                        if lesson.mode == selectedMode {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(lesson.mode == selectedMode
                                                ? Color.accentColor.opacity(0.15)
                                                : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Scenario recommender
                    Text("Scenario recommender").font(.headline)
                    TextField("Describe what you want to do (e.g. 'merge two blocks')",
                              text: $scenarioText)
                        .textFieldStyle(.roundedBorder)
                    Button("Recommend") {
                        recommendation = CombineModeTeacher.recommendMode(for: scenarioText)
                    }
                    .disabled(scenarioText.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let rec = recommendation {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text("Try \(rec.displayLabel)")
                                .font(.subheadline)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color.yellow.opacity(0.15)))
                    }
                }
                .frame(width: 260)
            }
        }
    }
}
