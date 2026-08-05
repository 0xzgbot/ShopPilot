import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

// MARK: - Recipe Picker View

/// Shows a grid of predefined job recipes for users to select from when creating a new project.
struct RecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRecipe: JobRecipe? = nil
    @State private var showConfirm = false
    
    let onConfirm: (JobRecipe) -> Void
    /// SPK-UI602: Cancel must dismiss the sheet, not only clear selection.
    var onCancel: (() -> Void)? = nil
    
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
                    onCancel?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
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
                Button("Create Job") {
                    onConfirm(recipe)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let recipe = selectedRecipe {
                Text("Create a job from \"\(recipe.name)\" (\(recipe.displayDimensions)). Strategy: \(recipe.recommendedStrategy)")
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

// MARK: - Preview (only in debug builds with SwiftUI available)

#if canImport(SwiftUI) && DEBUG
struct RecipePickerView_Previews: PreviewProvider {
    static var previews: some View {
        RecipePickerView(onConfirm: { _ in })
    }
}
#endif
