import Foundation

// MARK: - Combine Mode Teacher

/// Represents a lesson about a combine mode operation.
public struct CombineModeLesson: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// The combine mode this lesson explains
    public var mode: OperationMode
    
    /// Title of the lesson
    public var title: String
    
    /// Description of what this mode does
    public var description: String
    
    /// Visual hint for the UI (icon name or emoji)
    public var visualHint: String
    
    /// Example description
    public var example: String
    
    /// When to use this mode
    public var useCase: String
    
    /// When NOT to use this mode
    public var notUseCase: String
    
    /// Active
    public var active: Bool
    
    public init(
        id: UUID = UUID(),
        mode: OperationMode,
        title: String,
        description: String,
        visualHint: String = "info.circle",
        example: String = "",
        useCase: String = "",
        notUseCase: String = "",
        active: Bool = true
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.description = description
        self.visualHint = visualHint
        self.example = example
        self.useCase = useCase
        self.notUseCase = notUseCase
        self.active = active
    }
}

// MARK: - CombineModeTeacher

/// Provides guidance on which combine mode to use for a given operation.
public final class CombineModeTeacher {
    
    /// Returns all available combine mode lessons.
    public static func getAllLessons() -> [CombineModeLesson] {
        [
            CombineModeLesson(
                mode: .combineAdd,
                title: "Combine Add",
                description: "Adds the volume of one component to another. The result contains all geometry from both inputs.",
                visualHint: "plus.circle.fill",
                example: "Two separate blocks merged into one solid block.",
                useCase: "Use when you want to merge two components into a single combined shape.",
                notUseCase: "Do not use when you need to keep components separate for individual toolpaths."
            ),
            CombineModeLesson(
                mode: .combineSubtract,
                title: "Combine Subtract",
                description: "Removes the volume of one component from another. Like cutting a hole in a block.",
                visualHint: "minus.circle.fill",
                example: "A sphere subtracted from a cube creates a spherical cavity.",
                useCase: "Use when you want to carve out or remove material from a base component.",
                notUseCase: "Do not use when you need to add material rather than remove it."
            ),
            CombineModeLesson(
                mode: .combineMerge,
                title: "Combine Merge",
                description: "Merges all components into a single component while preserving internal boundaries.",
                visualHint: "arrow.triangle.merge",
                example: "Multiple overlapping shapes merged into one component with internal edges.",
                useCase: "Use when you want to combine multiple components but keep internal structure visible.",
                notUseCase: "Do not use when you need a single solid without internal boundaries."
            ),
            CombineModeLesson(
                mode: .combineLow,
                title: "Combine Low",
                description: "Keeps only the lowest (minimum) Z value at each point. Creates a terrain-like surface.",
                visualHint: "arrow.down.circle.fill",
                example: "Overlapping surfaces merged to keep only the bottom surface.",
                useCase: "Use when creating terrain or keeping the lowest surface from overlapping components.",
                notUseCase: "Do not use when you need to preserve the highest surface or all geometry."
            ),
            CombineModeLesson(
                mode: .combineMultiply,
                title: "Combine Multiply",
                description: "Keeps only the overlapping volume of all components. Like finding the intersection.",
                visualHint: "multiply.circle.fill",
                example: "Two intersecting cylinders produce only the overlapping cylindrical region.",
                useCase: "Use when you need only the common volume shared by all components.",
                notUseCase: "Do not use when you need the full extent of any component."
            ),
            CombineModeLesson(
                mode: .combineMax,
                title: "Combine Max",
                description: "Keeps only the highest (maximum) Z value at each point. Creates a terrain-like surface.",
                visualHint: "arrow.up.circle.fill",
                example: "Overlapping surfaces merged to keep only the top surface.",
                useCase: "Use when creating terrain or keeping the highest surface from overlapping components.",
                notUseCase: "Do not use when you need to preserve the lowest surface or all geometry."
            ),
            CombineModeLesson(
                mode: .combineMin,
                title: "Combine Min",
                description: "Keeps only the lowest (minimum) Z value at each point. Creates a terrain-like surface.",
                visualHint: "arrow.down.circle.fill",
                example: "Overlapping surfaces merged to keep only the bottom surface.",
                useCase: "Use when creating terrain or keeping the lowest surface from overlapping components.",
                notUseCase: "Do not use when you need to preserve the highest surface or all geometry."
            )
        ]
    }
    
    /// Returns the lesson for a specific combine mode.
    public static func getLesson(for mode: OperationMode) -> CombineModeLesson? {
        getAllLessons().first(where: { $0.mode == mode })
    }
    
    /// Returns the recommended combine mode for a given scenario.
    public static func recommendMode(for scenario: String) -> OperationMode? {
        let lower = scenario.lowercased()
        if lower.contains("merge") || lower.contains("join") || lower.contains("union") {
            return .combineAdd
        } else if lower.contains("cut") || lower.contains("carve") || lower.contains("remove") || lower.contains("subtract") {
            return .combineSubtract
        } else if lower.contains("overlap") || lower.contains("intersection") {
            return .combineMultiply
        } else if lower.contains("terrain") || lower.contains("bottom") || lower.contains("lowest") {
            return .combineLow
        } else if lower.contains("top") || lower.contains("highest") {
            return .combineMax
        }
        return nil
    }
    
    /// Returns all lessons sorted by mode.
    public static func getSortedLessons() -> [CombineModeLesson] {
        getAllLessons().sorted { $0.mode.rawValue < $1.mode.rawValue }
    }
}
