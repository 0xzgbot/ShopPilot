import SwiftUI
import ShopPilotCore
import ShopPilotGeometry

// MARK: - New Job View

/// Entry point for creating a new ShopPilot job from a recipe.
/// Presents a recipe picker and handles job creation.
public struct NewJobView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var showRecipePicker = false
    @State private var jobCreated: Bool = false
    @State private var errorMessage: String?
    
    /// The current document's variables, used to customize sign dimensions.
    @ObservedObject private var docVars: DocumentVariablesModel
    
    public init(docVars: DocumentVariablesModel = DocumentVariablesModel()) {
        self.docVars = docVars
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                
                Text("Create New Job")
                    .font(.title2.bold())
                
                Text("Select a recipe to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Recipe picker button
            Button(action: { showRecipePicker = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a Recipe")
                            .font(.headline)
                        Text("Portrait Relief • Signage • Decorative Panel • Custom")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Status message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if jobCreated {
                Text("Job created successfully")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .alert("Select Recipe", isPresented: $showRecipePicker) {
            ForEach(JobRecipe.defaultRecipes) { recipe in
                Button(recipe.name) {
                    createJob(from: recipe)
                }
            }
        } message: {
            Text("Choose a recipe to create a new job.")
        }
    }
    
    // MARK: - Actions
    
    private func createJob(from recipe: JobRecipe) {
        // If sign recipe, use SignRecipeManager with doc variables
        if recipe.name == "Signage" {
            let job = createSignJobFromRecipe(recipe)
            jobCreated = true
            errorMessage = nil
            dismiss()
            return
        }
        
        // For other recipes, create a basic job with sheet
        var job = Job(name: "\(recipe.name) Job")
        var sheet = Sheet(
            name: recipe.name,
            width: recipe.stockWidth,
            depth: recipe.stockDepth,
            height: recipe.stockHeight
        )
        sheet.material = MaterialDatabase.shared.lookup(byName: "MDF")
        job.addSheet(sheet)
        
        // Store doc variables in job
        job.documentVariables = docVars.variables
        
        jobCreated = true
        errorMessage = nil
        dismiss()
    }
    
    private func createSignJobFromRecipe(_ recipe: JobRecipe) -> Job {
        // Read doc variables for custom dimensions
        let widthVar = docVars.variables.first { $0.key.lowercased() == "width" }?.value
        let depthVar = docVars.variables.first { $0.key.lowercased() == "depth" }?.value
        let heightVar = docVars.variables.first { $0.key.lowercased() == "height" }?.value
        
        let stockWidth: Double = {
            if let w = widthVar, let val = Double(w) { return val }
            return recipe.stockWidth
        }()
        
        let stockDepth: Double = {
            if let d = depthVar, let val = Double(d) { return val }
            return recipe.stockDepth
        }()
        
        let stockHeight: Double = {
            if let h = heightVar, let val = Double(h) { return val }
            return recipe.stockHeight
        }()
        
        // Create sign job using SignRecipeManager
        var job = SignRecipeManager.createSignJob(
            jobName: "Signage Job",
            text: "SHOP",
            font: "Helvetica Neue",
            fontSize: 48.0,
            scale: 1.0,
            vBitAngle: 90.0,
            vCarveDepth: 0.5,
            feedRate: 1000.0
        )
        
        // Override dimensions from doc variables
        if job.sheets.count > 0 {
            job.sheets[0].width = stockWidth
            job.sheets[0].depth = stockDepth
            job.sheets[0].height = stockHeight
        }
        
        // Store doc variables
        job.documentVariables = docVars.variables
        
        return job
    }
}

// MARK: - Preview (Xcode only)

#if canImport(SwiftUI) && DEBUG
struct NewJobView_Previews: PreviewProvider {
    static var previews: some View {
        NewJobView()
            .frame(width: 400, height: 300)
    }
}
#endif
