import SwiftUI

// MARK: - Inspector Shell

/// Stage-specific inspector panel that switches its content based on the current stage.
struct InspectorShell: View {
    @Binding var currentStage: Stage
    
    var body: some View {
        VStack(spacing: 0) {
            Text("PROPERTIES")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    switch currentStage {
                    case .setup:
                        setupInspector
                    case .design:
                        designInspector
                    case .model:
                        modelInspector
                    case .cut:
                        cutInspector
                    case .preview:
                        previewInspector
                    case .machine:
                        machineInspector
                    }
                }
            }
        }
    }
    
    // MARK: - Setup Stage
    
    private var setupInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STOCK DIMENSIONS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                dimensionField(label: "Width", value: "")
                dimensionField(label: "Depth", value: "")
                dimensionField(label: "Height", value: "")
            }
            
            Text("MATERIAL")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            
            Picker("Material Type", selection: .constant(0)) {
                Text("Hardwood").tag(0)
                Text("Softwood").tag(1)
                Text("Plywood").tag(2)
                Text("MDF").tag(3)
                Text("Plastic").tag(4)
            }
            .pickerStyle(.menu)
            
            Text("ORIGIN POINT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            
            Picker("Origin", selection: .constant(0)) {
                Text("Center").tag(0)
                Text("Front-Left Corner").tag(1)
                Text("Back-Right Corner").tag(2)
            }
            .pickerStyle(.segmented)
        }
    }
    
    private func dimensionField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            TextField("", text: .constant(value))
                .textFieldStyle(.roundedBorder)
        }
    }
    
    // MARK: - Design Stage
    
    private var designInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAYERS")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            ForEach(0..<3, id: \.self) { idx in
                HStack {
                    Image(systemName: "layers.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    
                    Text("Layer \(idx + 1)")
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                }
            }
            
            Button(action: {}) {
                Label("Add Layer", systemImage: "plus.circle.fill")
            }
        }
    }
    
    // MARK: - Model Stage
    
    private var modelInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3D MODEL")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                InfoCard(label: "Triangles", value: "---")
                InfoCard(label: "Vertices", value: "---")
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Bounding Box")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    InfoCard(label: "W", value: "--- mm")
                    InfoCard(label: "D", value: "--- mm")
                    InfoCard(label: "H", value: "--- mm")
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Simplification")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Slider(value: .constant(0.5))
            }
        }
    }
    
    private func InfoCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Cut Stage
    
    private var cutInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOOLPATH STRATEGY")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Picker("Strategy", selection: .constant(0)) {
                Text("Profile").tag(0)
                Text("Pocket").tag(1)
                Text("Drill").tag(2)
                Text("V-Carve").tag(3)
                Text("Quick Engrave").tag(4)
            }
            .pickerStyle(.menu)
            
            Divider()
            
            Text("TOOL")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Picker("Bit Type", selection: .constant(0)) {
                    Text("End Mill").tag(0)
                    Text("V-Bit 90°").tag(1)
                    Text("V-Bit 60°").tag(2)
                    Text("V-Bit 30°").tag(3)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                
                TextField("D", text: .constant("6.0"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
            
            Divider()
            
            Text("DEPTH & FEED")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Depth")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", text: .constant("0.5"))
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 80)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Feed Rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", text: .constant("1000"))
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 80)
            }
            
            Divider()
            
            Text("SIGN RECIPE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: "textformat.abc")
                    .foregroundStyle(.secondary)
                Text("V-Carve: 2 passes, 0.5mm depth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                Text("Est. time: 4.2 min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Preview Stage
    
    private var previewInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                }
                
                Button(action: {}) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Speed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Slider(value: .constant(1.0))
            }
            
            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "step.backward.fill")
                }
                
                Spacer()
                
                Text("Progress: ---%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "step.forward.fill")
                }
            }
        }
    }
    
    // MARK: - Machine Stage
    
    private var machineInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                
                Text("Connected")
                    .font(.system(size: 14, weight: .medium))
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "arrow.up")
                        .font(.title2)
                }
                .frame(width: 60, height: 40)
                
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                    }
                    .frame(width: 60, height: 40)
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.down")
                            .font(.title2)
                    }
                    .frame(width: 60, height: 40)
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.right")
                            .font(.title2)
                    }
                    .frame(width: 60, height: 40)
                }
            }
            
            Divider()
            
            Button(action: {}) {
                Label("Emergency Stop", systemImage: "exclamationmark.triangle.fill")
                    .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

// MARK: - Preview (only in debug builds with SwiftUI available)

#if canImport(SwiftUI) && DEBUG
struct InspectorShell_Previews: PreviewProvider {
    static var previews: some View {
        InspectorShell(currentStage: .constant(.setup))
            .frame(width: 280)
    }
}
#endif
