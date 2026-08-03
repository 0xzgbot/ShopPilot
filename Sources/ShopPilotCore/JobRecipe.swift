import Foundation

// MARK: - Job Recipe Model

/// A predefined job template that users can select when creating a new project.
public struct JobRecipe: Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let icon: String
    public let stockWidth: Double  // mm
    public let stockDepth: Double  // mm
    public let stockHeight: Double // mm
    public let recommendedStrategy: String

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String,
        stockWidth: Double,
        stockDepth: Double,
        stockHeight: Double,
        recommendedStrategy: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.stockWidth = stockWidth
        self.stockDepth = stockDepth
        self.stockHeight = stockHeight
        self.recommendedStrategy = recommendedStrategy
    }

    public var displayDimensions: String {
        String(format: "%.1f × %.1f × %.2f in",
               stockWidth / 25.4, stockDepth / 25.4, stockHeight / 25.4)
    }
}

// MARK: - Default Recipes

extension JobRecipe {
    /// The built-in recipe templates shown in the new-job picker.
    public static let defaultRecipes: [JobRecipe] = [
        JobRecipe(
            name: "Portrait Relief",
            description: "Portrait-style relief carving with fine detail in the face area and simpler background.",
            icon: "person.crop.circle",
            stockWidth: 304.8,   // 12 inches
            stockDepth: 457.2,   // 18 inches
            stockHeight: 19.05,  // 0.75 inches
            recommendedStrategy: "Adaptive Z-level roughing + parallel finishing"
        ),
        JobRecipe(
            name: "Decorative Panel",
            description: "Symmetrical decorative panel for furniture or wall mounting.",
            icon: "square.grid.2x2",
            stockWidth: 609.6,   // 24 inches
            stockDepth: 609.6,   // 24 inches
            stockHeight: 19.05,  // 0.75 inches
            recommendedStrategy: "Z-level contouring with radial finishing"
        ),
        JobRecipe(
            name: "Signage",
            description: "Single-face sign with lettering and decorative graphics.",
            icon: "textformat.abc",
            stockWidth: 457.2,   // 18 inches
            stockDepth: 609.6,   // 24 inches
            stockHeight: 19.05,  // 0.75 inches
            recommendedStrategy: "Profile + V-Carve lettering"
        ),
        JobRecipe(
            name: "Custom",
            description: "Blank canvas — define your own dimensions and start from scratch.",
            icon: "plus.circle",
            stockWidth: 304.8,   // 12 inches (default)
            stockDepth: 304.8,   // 12 inches (default)
            stockHeight: 25.4,   // 1 inch (default)
            recommendedStrategy: "User-defined"
        )
    ]
}
