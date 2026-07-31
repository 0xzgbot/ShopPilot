import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

// MARK: - Job Recipe Model

/// A predefined job template that users can select when creating a new project.
struct JobRecipe: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let stockWidth: Double  // mm
    let stockDepth: Double  // mm
    let stockHeight: Double // mm
    let recommendedStrategy: String
    
    var displayDimensions: String {
        String(format: "%.1f × %.1f × %.2f in", 
               stockWidth / 25.4, stockDepth / 25.4, stockHeight / 25.4)
    }
}

// MARK: - Recipe Picker View

/// Shows a grid of predefined job recipes for users to select from when creating a new project.
struct RecipePickerView: View {
    @State private var searchText = ""
    @State private var selectedRecipe: JobRecipe? = nil
    @State private var showConfirm = false
    
    let onConfirm: (JobRecipe) -> Void
    
    private var recipes: [JobRecipe] {
        if searchText.isEmpty {
            return JobRecipe.defaultRecipes
        }
        let lower = searchText.lowercased()
        return JobRecipe.defaultRecipes.filter { $0.name.localizedCaseInsensitiveContains(lower) || 
                                $0.description.localizedCaseInsensitiveContains(lower) }
    }
    
    private var filteredRecipes: [JobRecipe] { recipes }
    
    var body: some View {
        VStack(spacing: 16) {
            // Search bar
            searchField
            
            Divider()
            
            if filteredRecipes.isEmpty {
                noResultsView
            } else {
                recipeGrid
            }
            
            Divider()
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    selectedRecipe = nil
                }
                
                Button("Create Job") {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRecipe == nil)
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 400)
        .alert("Confirm Recipe", isPresented: $showConfirm) {
            if let recipe = selectedRecipe {
                Button("Create Job", role: .destructive) {
                    onConfirm(recipe)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let recipe = selectedRecipe {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creating job from \"\(recipe.name)\":")
                    InfoRow(label: "Stock Size", value: recipe.displayDimensions)
                    InfoRow(label: "Strategy", value: recipe.recommendedStrategy)
                }
            }
        }
    }
    
    // MARK: - Search
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search recipes...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
    
    // MARK: - Grid
    
    private var recipeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filteredRecipes) { recipe in
                RecipeCard(recipe: recipe, isSelected: selectedRecipe?.id == recipe.id)
                    .onTapGesture {
                        selectedRecipe = recipe
                    }
            }
        }
    }
    
    // MARK: - No Results
    
    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("No recipes found for \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Recipe Card

private struct RecipeCard: View {
    let recipe: JobRecipe
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: recipe.icon)
                .font(.title)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            
            Text(recipe.name)
                .font(.headline)
                .lineLimit(1)
            
            Text(recipe.displayDimensions)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(recipe.recommendedStrategy)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Info Row Helper (for alert message)

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Default Recipes

extension JobRecipe {
    static let defaultRecipes: [JobRecipe] = [
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

// MARK: - Preview (only in debug builds with SwiftUI available)

#if canImport(SwiftUI) && DEBUG
struct RecipePickerView_Previews: PreviewProvider {
    static var previews: some View {
        RecipePickerView(onConfirm: { _ in })
    }
}
#endif
