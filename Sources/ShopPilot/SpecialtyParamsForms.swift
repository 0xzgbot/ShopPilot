import SwiftUI
import ShopPilotCore

// MARK: - Specialty strategy forms (SPK-0900 + SPK-0802 + F07 lean slices)

/// Numeric row helper shared by the specialty forms.
private struct SpecialtyNumRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        GridRow {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

struct PrismParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (PrismToolpathParams) -> Void

    @State private var params: PrismToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (PrismToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.prismParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Grooves") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Spacing (mm)", value: $params.spacingMm)
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Max depth (0 = auto)", value: $params.maxDepthMm)
                    SpecialtyNumRow(label: "Start depth (mm)", value: $params.startDepthMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct FlutingParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (FlutingToolpathParams) -> Void

    @State private var params: FlutingToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (FlutingToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.flutingParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Flute") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Start depth (mm)", value: $params.startDepthMm)
                    SpecialtyNumRow(label: "Cut depth (mm)", value: $params.cutDepthMm)
                    SpecialtyNumRow(label: "Pass depth (0 = single)", value: $params.passDepthMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                    SpecialtyNumRow(label: "Tool Ø (mm)", value: $params.toolDiameterMm)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct ChamferParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (ChamferToolpathParams) -> Void

    @State private var params: ChamferToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (ChamferToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.chamferParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Bevel") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Chamfer width (mm)", value: $params.chamferWidthMm)
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct InlayParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (InlayToolpathParams) -> Void

    @State private var params: InlayToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (InlayToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.inlayParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("V-Carve Inlay Recipe") {
                Picker("Preset", selection: $recipeIndex) {
                    Text("Custom").tag(Int?.none)
                    ForEach(Array(VCarveInlayRecipe.presets.enumerated()), id: \.offset) { index, recipe in
                        Text(recipe.name).tag(Int?.some(index))
                    }
                }
                .onChange(of: recipeIndex) { newValue in
                    if let index = newValue, VCarveInlayRecipe.presets.indices.contains(index) {
                        VCarveInlayRecipe.presets[index].apply(to: &params)
                    }
                }
                .help("Load a classic angle/depth preset (30/45/60/90°)")
            }
            GroupBox("Inlay") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    Picker("Half", selection: $params.variant) {
                        Text("Pocket (female)").tag(InlayToolpathParams.Variant.pocket)
                        Text("Plug (male)").tag(InlayToolpathParams.Variant.plug)
                    }
                    SpecialtyNumRow(label: "Inlay depth (mm)", value: $params.inlayDepthMm)
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    /// Preset index currently matching the params (nil = custom). The getter
    /// round-trips loaded presets so the picker shows the active recipe.
    @State private var recipeIndex: Int?
}

struct QuickEngraveParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (QuickEngraveToolpathParams) -> Void

    @State private var params: QuickEngraveToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (QuickEngraveToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.quickEngraveParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Engrave") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Cut depth (mm)", value: $params.cutDepthMm)
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                    SpecialtyNumRow(label: "Tool Ø (mm)", value: $params.toolDiameterMm)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct PhotoVCarveParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (PhotoVCarveToolpathParams) -> Void

    @State private var params: PhotoVCarveToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (PhotoVCarveToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.photoVCarveParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Photo V-Carve") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Max depth (mm)", value: $params.maxDepthMm)
                    SpecialtyNumRow(label: "Step-over (mm)", value: $params.stepOverMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct DragKnifeParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (DragKnifeToolpathParams) -> Void

    @State private var params: DragKnifeToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (DragKnifeToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.dragKnifeParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Drag Knife") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Blade offset (mm)", value: $params.bladeOffsetMm)
                    SpecialtyNumRow(label: "Cut depth (mm)", value: $params.cutDepthMm)
                    SpecialtyNumRow(label: "Pivot threshold (°)", value: $params.pivotThresholdDegrees)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct TextureParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (TextureToolpathParams) -> Void

    @State private var params: TextureToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (TextureToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.textureParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Texture") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    Picker("Pattern", selection: $params.pattern) {
                        Text("Parallel").tag(TextureToolpathParams.Pattern.parallel)
                        Text("Crosshatch").tag(TextureToolpathParams.Pattern.crosshatch)
                    }
                    .pickerStyle(.segmented)
                    .gridCellColumns(2)
                    SpecialtyNumRow(label: "Spacing (mm)", value: $params.spacingMm)
                    SpecialtyNumRow(label: "Angle (°)", value: $params.angleDegrees)
                    Picker("Cut style", selection: $params.cutStyle) {
                        Text("V-groove").tag(TextureToolpathParams.TextureCutStyle.vGroove)
                        Text("Flat").tag(TextureToolpathParams.TextureCutStyle.flat)
                    }
                    .pickerStyle(.segmented)
                    .gridCellColumns(2)
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Flat depth (mm)", value: $params.flatDepthMm)
                    SpecialtyNumRow(label: "Max depth (0 = auto)", value: $params.maxDepthMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct RotaryWrapParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (RotaryWrapToolpathParams) -> Void

    @State private var params: RotaryWrapToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (RotaryWrapToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.rotaryWrapParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Rotary Wrap") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Stock Ø (mm)", value: $params.diameterMm)
                    SpecialtyNumRow(label: "Cut depth (mm)", value: $params.cutDepthMm)
                    Picker("Direction", selection: $params.direction) {
                        Text("Clockwise").tag(RotaryDirection.clockwise)
                        Text("Counter-clockwise").tag(RotaryDirection.counterClockwise)
                    }
                    .pickerStyle(.segmented)
                    .gridCellColumns(2)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

struct SketchCarveParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (SketchCarveToolpathParams) -> Void

    @State private var params: SketchCarveToolpathParams

    init(node: ToolpathTreeNode, onApply: @escaping (SketchCarveToolpathParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.sketchCarveParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Sketch Carve") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "V-bit angle (°)", value: $params.vBitAngleDegrees)
                    SpecialtyNumRow(label: "Max depth (mm)", value: $params.maxDepthMm)
                    SpecialtyNumRow(label: "Edge threshold (0–1)", value: $params.edgeThreshold)
                    SpecialtyNumRow(label: "Step-over (mm)", value: $params.stepOverMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

// MARK: - Thread Mill form (SPK-0902)

struct ThreadMillParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (ThreadMillParams) -> Void

    @State private var params: ThreadMillParams

    init(node: ToolpathTreeNode, onApply: @escaping (ThreadMillParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.threadMillParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Thread") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Hole Ø (mm)", value: $params.holeDiameterMm)
                    SpecialtyNumRow(label: "Pitch (mm)", value: $params.pitchMm)
                    SpecialtyNumRow(label: "Thread length (mm)", value: $params.threadLengthMm)
                    SpecialtyNumRow(label: "Tool Ø (mm)", value: $params.toolDiameterMm)
                    Picker("Thread", selection: $params.isInternal) {
                        Text("Internal").tag(true)
                        Text("External").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .gridCellColumns(2)
                }
            }
            GroupBox("Passes") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Passes", value: Binding(
                        get: { Double(params.passes) },
                        set: { params.passes = max(1, Int($0)) }
                    ))
                    SpecialtyNumRow(label: "Pass step (mm)", value: $params.passStepMm)
                }
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeRateMmPerMin)
                    SpecialtyNumRow(label: "Spindle (RPM)", value: $params.spindleRpm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safeZHeightMm)
                }
            }
            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}

// MARK: - Trochoid Slot strategy form (SPK-1910c)

/// Editable form for the SPK-1910 trochoidal slotting field set. Editing is
/// local; "Apply" stores the params on the operation and regenerates its
/// G-code with the real engine (same contract as Pocket/Thread Mill forms).
struct TrochoidSlotParamsForm: View {
    let node: ToolpathTreeNode
    let onApply: (TrochoidSlotParams) -> Void

    @State private var params: TrochoidSlotParams

    init(node: ToolpathTreeNode, onApply: @escaping (TrochoidSlotParams) -> Void) {
        self.node = node
        self.onApply = onApply
        _params = State(initialValue: node.trochoidSlotParams())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("Tool & depth") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Tool Ø (mm)", value: $params.toolDiameterMm)
                    SpecialtyNumRow(label: "Cut depth (mm)", value: $params.cutDepthMm)
                    SpecialtyNumRow(label: "Start depth (mm)", value: $params.startDepthMm)
                    SpecialtyNumRow(label: "Depth/pass (mm)", value: $params.maxDepthOfCutMm)
                    SpecialtyNumRow(label: "Safe Z (mm)", value: $params.safetyHeightMm)
                }
            }
            GroupBox("Engagement") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    // The whole point of trochoidal slotting — keep this small.
                    SpecialtyNumRow(label: "Max WOC (mm)", value: $params.maxWocMm)
                    SpecialtyNumRow(label: "Loop pitch (mm)", value: $params.loopPitchMm)
                }
                Text("WOC = radial engagement per loop. Smaller = safer on hobby routers, more loops.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GroupBox("Feeds") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    SpecialtyNumRow(label: "Feed (mm/min)", value: $params.feedRateMmPerMin)
                    SpecialtyNumRow(label: "Plunge (mm/min)", value: $params.plungeFeedRateMmPerMin)
                    SpecialtyNumRow(label: "Spindle (RPM, 0 = off)", value: $params.spindleRpm)
                }
            }
            GroupBox("Options") {
                Picker("Direction", selection: $params.cutDirection) {
                    ForEach([CutDirection.climb, .conventional], id: \.self) { d in
                        Text(d.displayName).tag(d)
                    }
                }
                .labelsHidden()
                Toggle("Ramp entry (no dead plunge)", isOn: $params.rampEntry)
            }

            Button("Apply Params — Regenerate") {
                onApply(params)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }
}
