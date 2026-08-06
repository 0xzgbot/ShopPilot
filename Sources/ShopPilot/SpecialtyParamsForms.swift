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
