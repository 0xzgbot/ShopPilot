import SwiftUI

// MARK: - Icon Count Limit Constant

/// Maximum number of SF Symbols / icons allowed on any single screen/stage.
/// Enforces the ≤12 icons rule defined in the UX plan (progressive disclosure).
let MAX_ICONS_PER_SCREEN = 12

// MARK: - Validation Result

/// Structured result from icon-count validation.
struct ValidationResult {
    /// Whether all stages and command categories pass the limit check.
    let isPass: Bool

    /// List of violations — each entry identifies a stage/category, its icon count,
    /// and the specific SF Symbol names that contribute to the count.
    let violations: [(stage: Stage, count: Int, icons: [String])]

    /// Command-category violations (separate from per-stage checks).
    let commandCategoryViolations: [(category: String, count: Int, commands: [String])]

    /// Convenience: human-readable summary of all issues.
    var summary: String {
        var parts = [String]()
        if !violations.isEmpty {
            for v in violations {
                parts.append(
                    "Stage '\(v.stage.title)': \(v.count) icons (limit \(MAX_ICONS_PER_SCREEN)) — \(v.icons.joined(separator: ", "))"
                )
            }
        }
        if !commandCategoryViolations.isEmpty {
            for v in commandCategoryViolations {
                parts.append(
                    "Command category '\(v.category)': \(v.count) commands (limit \(MAX_ICONS_PER_SCREEN)) — \(v.commands.joined(separator: ", "))"
                )
            }
        }
        return parts.isEmpty ? "All checks passed." : parts.joined(separator: "\n")
    }
}

// MARK: - Icon Rule Validator

/// Static validator that enforces the ≤12 icons rule across all stages and
/// command-palette category groups.
struct IconRuleValidator {

    // MARK: - Public API

    /// Validate icon counts for every stage in the provided list.
    /// Also validates command-palette categories against the same limit.
    static func validateIcons(for stages: [Stage]) -> ValidationResult {
        var violations: [(stage: Stage, count: Int, icons: [String])] = []
        var commandViolations: [(category: String, count: Int, commands: [String])] = []

        // Per-stage icon counts.
        for stage in stages {
            let result = validateStage(stage)
            if result.count > MAX_ICONS_PER_SCREEN {
                violations.append(result)
            }
        }

        // Command-palette category checks.
        commandViolations = validateCommandPalette()

        return ValidationResult(
            isPass: violations.isEmpty && commandViolations.isEmpty,
            violations: violations,
            commandCategoryViolations: commandViolations
        )
    }

    /// Convenience: validate using all stages from StageEnum.
    static func validateAllStages() -> ValidationResult {
        validateIcons(for: Stage.allCases)
    }

    // MARK: - Per-Stage Validation

    /// Count icons for a single stage by examining its icon definition and the
    /// hardcoded SF Symbol usage in views that render that stage.
    static func validateStage(_ stage: Stage) -> (stage: Stage, count: Int, icons: [String]) {
        var icons = [String]()

        // 1. Stage rail button — each button shows one icon via Image(systemName:)
        icons.append(stage.icon)

        // 2. Stage content view — large hero icon for the active stage
        icons.append(stage.icon) // same symbol, but a second usage on screen

        // 3. StageRailView dividers are not SF Symbols (they're Divider()), so they don't count.

        // 4. CommandPaletteView icons that appear regardless of selected stage:
        //    - magnifyingglass (search field)
        //    - xmark.circle.fill (clear button, conditional)
        //    - arrow.up.arrow.down (footer help)
        //    - return (footer help)
        //    - escape (footer help)
        icons.append("magnifyingglass")
        icons.append("xmark.circle.fill")
        icons.append("arrow.up.arrow.down")
        icons.append("return")
        icons.append("escape")

        // 5. App-level toolbar chrome — unified toolbar style adds standard macOS
        //    window controls (close, minimize, zoom) which are system-rendered and
        //    not SF Symbols; they do NOT count toward the limit.

        // Deduplicate for reporting but keep duplicates in count since each usage
        // is a separate icon render on screen.
        let uniqueIcons = Array(Set(icons))

        return (stage: stage, count: icons.count, icons: uniqueIcons)
    }

    // MARK: - Command Palette Category Validation

    /// Validate that no command-palette category group exceeds the limit.
    private static func validateCommandPalette() -> [(category: String, count: Int, commands: [String])] {
        var violations = [(category: String, count: Int, commands: [String])]()

        for category in CommandCategory.allCases {
            let commandsInCategory = CommandID.allCases.filter { $0.category == category }
            let commandNames = commandsInCategory.map(\.name)

            if commandsInCategory.count > MAX_ICONS_PER_SCREEN {
                violations.append((
                    category: category.rawValue,
                    count: commandsInCategory.count,
                    commands: commandNames
                ))
            }
        }

        return violations
    }
}

// MARK: - Icon Audit View (Debug / Development)

/// SwiftUI view for development and debugging that shows all stages with their
/// icon counts. Violations are highlighted in red; passing stages in green.
struct IconAuditView: View {
    let validationResult: ValidationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            Divider()

            // Stage violations (if any)
            if !validationResult.violations.isEmpty {
                Text("Stage Violations")
                    .font(.headline)
                    .foregroundStyle(.red)

                ForEach(validationResult.violations, id: \.stage) { violation in
                    violationRow(stage: violation.stage, count: violation.count, icons: violation.icons, isViolation: true)
                }
            }

            // Passing stages
            let passingStages = Stage.allCases.filter { stage in
                !validationResult.violations.contains(where: { $0.stage == stage })
            }
            if !passingStages.isEmpty {
                Text("Passing Stages")
                    .font(.headline)
                    .foregroundStyle(.green)

                ForEach(passingStages, id: \.self) { stage in
                    let result = IconRuleValidator.validateStage(stage)
                    violationRow(stage: stage, count: result.count, icons: result.icons, isViolation: false)
                }
            }

            // Command category violations (if any)
            if !validationResult.commandCategoryViolations.isEmpty {
                Divider()
                Text("Command Category Violations")
                    .font(.headline)
                    .foregroundStyle(.red)

                ForEach(validationResult.commandCategoryViolations, id: \.category) { violation in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Category '\(violation.category)': \(violation.count)/\(MAX_ICONS_PER_SCREEN)")
                                .fontWeight(.semibold)
                        }
                        ForEach(violation.commands, id: \.self) { cmd in
                            Text("  • \(cmd)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Passing command categories
            let passingCategories = CommandCategory.allCases.filter { cat in
                !validationResult.commandCategoryViolations.contains(where: { $0.category == cat.rawValue })
            }
            if !passingCategories.isEmpty {
                Divider()
                Text("Passing Command Categories")
                    .font(.headline)
                    .foregroundStyle(.green)

                ForEach(passingCategories, id: \.self) { category in
                    let count = CommandID.allCases.filter { $0.category == category }.count
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Category '\(category.rawValue)': \(count)/\(MAX_ICONS_PER_SCREEN)")
                    }
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Icon Audit")
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            Image(systemName: validationResult.isPass ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(validationResult.isPass ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Icon Count Audit")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(validationResult.isPass ? "All checks passed" : "\(validationResult.violations.count + validationResult.commandCategoryViolations.count) violation(s) found")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Limit badge
            Image(systemName: "gauge.medium")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .center, spacing: 2) {
                Text("Limit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(MAX_ICONS_PER_SCREEN)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }
        }
    }

    private func violationRow(stage: Stage, count: Int, icons: [String], isViolation: Bool) -> some View {
        let statusColor = isViolation ? Color.red : Color.green
        let iconSymbol = isViolation ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconSymbol)
                    .foregroundStyle(statusColor)
                Text("\(stage.title)")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(count)/\(MAX_ICONS_PER_SCREEN)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.15))
                    )
            }

            if !icons.isEmpty {
                Text("Icons: \(icons.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - App Launch Runtime Check

/// Call this function from your @main app's .onAppear to log warnings at runtime.
/// Example usage in ShopPilotApp:
///
///     .onAppear {
///         let result = IconRuleValidator.validateAllStages()
///         if !result.isPass {
///             print("⚠️ Icon count violations detected:")
///             print(result.summary)
///         } else {
///             print("✅ All stages within \(MAX_ICONS_PER_SCREEN) icon limit.")
///         }
///     }
