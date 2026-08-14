import SwiftUI
import UniformTypeIdentifiers
import ShopPilotCore

// MARK: - Model Stage (SPK-3D-UI)

/// The Model stage: view the imported STL relief as a heightmap with a basic
/// zoom/pan camera, and generate Rough 3D / Finish 3D toolpaths into the Cut
/// tree. Replaces the locked placeholder.
struct ModelStageView: View {
    @ObservedObject var session: AppSession
    @State private var zoom: Double = 1.0
    @State private var panX: Double = 0
    @State private var panY: Double = 0
    /// Fit scale reported by the canvas (one grid cell at zoom 1). Used to
    /// compute the 1:1 preset (one cell = one screen point).
    @State private var fitBase: Double = 1.0
    @State private var sculptMode: Bool = false
    @State private var sculptTool: SculptTool = .brush
    @State private var brushRadiusMm: Double = 5.0
    @State private var brushStrength: Double = 0.5
    @State private var brushShape: BrushShape = .sphere
    @State private var brushFalloff: BrushFalloff = .smooth
    /// SPK-0702 — id of the component whose dynamic-props popover is open.
    @State private var propsTarget: UUID?
    /// SPK-0712 — split-plane height dialog.
    @State private var showSplitDialog = false
    @State private var splitPlaneText = "5.0"
    /// SPK-0704 — combine-mode teacher sheet.
    @State private var showTeacher = false
    /// SPK-0708 — composite render configuration sheet.
    @State private var showCompositeRender = false
    @State private var showLaserToolpath = false
    // SPK-1800h: orbit toggle state (Model-stage level).
    @State private var orbitMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            opsBar
            if !session.reliefComponents.isEmpty {
                Divider()
                componentBar
            }
            if sculptMode {
                Divider()
                sculptBar
            }
            Divider()
            if let hf = session.job.stlHeightfield {
                ReliefCanvasView(
                    hf: hf,
                    zoom: $zoom, panX: $panX, panY: $panY,
                    fitBase: $fitBase,
                    sculptMode: sculptMode,
                    orbitMode: orbitMode,
                    strokeParams: SculptStrokeParams(
                        tool: sculptTool,
                        radiusMm: brushRadiusMm,
                        strength: brushStrength,
                        brushShape: brushShape,
                        brushFalloff: brushFalloff
                    ),
                    onStroke: { center, recordUndo in
                        var stroke = SculptStrokeParams(
                            tool: sculptTool,
                            centerX: center.x,
                            centerY: center.y,
                            radiusMm: brushRadiusMm,
                            strength: brushStrength,
                            brushShape: brushShape,
                            brushFalloff: brushFalloff
                        )
                        _ = session.applySculptStroke(stroke, recordUndo: recordUndo)
                    },
                    handles: session.handleManager.handles,
                    onHandleDrag: { handleID, dx, dy, dz, recordUndo in
                        _ = session.applyHandleDrag(handleID: handleID, deltaX: dx, deltaY: dy, deltaZ: dz, recordUndo: recordUndo)
                    }
                )
                Divider()
                infoBar(hf)
            } else {
                emptyState
            }
        }
        .alert("Split Relief", isPresented: $showSplitDialog) {
            TextField("Plane height (mm)", text: $splitPlaneText)
            Button("Split") {
                let normalized = splitPlaneText.replacingOccurrences(of: ",", with: ".")
                if let plane = Double(normalized) {
                    _ = session.splitRelief(planeHeight: plane)
                } else {
                    session.statusMessage = "Split: enter a number"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cuts the relief at a horizontal plane — the part above the plane becomes the new relief (re-based to 0).")
        }
        // SPK-0707 — STL orientation wizard sheet.
        .sheet(isPresented: Binding(
            get: { session.showSTLOrientationWizard },
            set: { session.showSTLOrientationWizard = $0 }
        )) {
            if let stlURL = session.stlImportURL {
                STLOrientationWizardSheet(stlURL: stlURL, config: session.stlConfig) { result in
                    session.showSTLOrientationWizard = false
                    if let hf = result.heightfield {
                        session.job.stlHeightfield = hf
                        session.markDirty()
                        session.statusMessage = "STL relief: \(result.triangleCount) triangles → \(hf.width)×\(hf.height) grid, max \(String(format: "%.1f", hf.maxHeight))mm"
                        session.selectedStage = .model
                    } else {
                        session.statusMessage = "STL import failed: \(result.errorMessage ?? "unknown error")"
                    }
                }
            }
        }
        // SPK-0708 — composite render configuration sheet.
        .sheet(isPresented: $showCompositeRender) {
            CompositeRenderSheet { config in
                _ = session.renderCompositeComponent(config)
            }
        }
        // SPK-0906 — laser toolpath configuration sheet.
        .sheet(isPresented: $showLaserToolpath) {
            LaserToolpathSheet { mode, power, speed in
                _ = session.generateLaserToolpath(mode: mode, powerPercent: power, speedMmPerMin: speed)
            }
        }
    }

    /// SPK-0700/0701 — component stack browser: each captured relief with its
    /// combine mode (Add/Subtract/Merge/Low/Max/Min/Multiply), visibility
    /// toggle, and remove. The compositor folds them into the active relief.
    private var componentBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Components (\(session.reliefComponents.count)) — combine modes fold into the active relief")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(session.reliefComponents) { component in
                HStack(spacing: 6) {
                    Button {
                        _ = session.toggleComponentVisibility(component.id)
                    } label: {
                        Image(systemName: component.visible ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(component.visible ? "Hide component" : "Show component")
                    Text(component.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { component.combineMode },
                        set: { _ = session.updateComponentMode(component.id, mode: $0) }
                    )) {
                        Text("Add").tag(OperationMode.combineAdd)
                        Text("Subtract").tag(OperationMode.combineSubtract)
                        Text("Merge High").tag(OperationMode.combineMerge)
                        Text("Low").tag(OperationMode.combineLow)
                        Text("Max").tag(OperationMode.combineMax)
                        Text("Min").tag(OperationMode.combineMin)
                        Text("Multiply").tag(OperationMode.combineMultiply)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .controlSize(.small)
                    Text("\(component.heightfield.width)×\(component.heightfield.height) · \(String(format: "%.1f", component.heightfield.maxHeight))mm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // SPK-0702 — dynamic props (height/tilt/fade) popover.
                    Button {
                        propsTarget = component.id
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .help("Dynamic props: height scale, tilt, fade")
                    .popover(isPresented: Binding(
                        get: { propsTarget == component.id },
                        set: { if !$0 { propsTarget = nil } }
                    )) {
                        ComponentPropsPopover(
                            component: component,
                            onUpdate: { heightScale, tilt, fadeAmount, fadeDirection in
                                _ = session.updateComponentModifiers(
                                    component.id,
                                    heightScale: heightScale,
                                    tiltAngleDegrees: tilt,
                                    fadeAmount: fadeAmount,
                                    fadeDirection: fadeDirection
                                )
                            }
                        )
                    }
                    // SPK-0712 — per-component operations (smooth / emboss).
                    Menu {
                        Button("Smooth…") {
                            _ = session.smoothComponent(
                                component.id,
                                params: SmoothParams(iterations: 5, smoothingFactor: 0.5)
                            )
                        }
                        Button("Emboss Raised…") {
                            _ = session.embossComponent(
                                component.id,
                                params: EmbossParams(embossType: .raised, depth: 2.0)
                            )
                        }
                        Button("Emboss Recessed…") {
                            _ = session.embossComponent(
                                component.id,
                                params: EmbossParams(embossType: .recessed, depth: 2.0)
                            )
                        }
                        // SPK-E22 — offset model: grow (dilate) or shrink (erode)
                        // the component's solid form.
                        Menu("Offset Model…") {
                            Button("Expand +1 mm") {
                                _ = session.offsetComponent(component.id, offsetMm: 1.0)
                            }
                            Button("Expand +2 mm") {
                                _ = session.offsetComponent(component.id, offsetMm: 2.0)
                            }
                            Button("Inset −1 mm") {
                                _ = session.offsetComponent(component.id, offsetMm: -1.0)
                            }
                            Button("Inset −2 mm") {
                                _ = session.offsetComponent(component.id, offsetMm: -2.0)
                            }
                        }
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .help("Component operations: smooth, emboss, or offset the relief")
                    Button {
                        _ = session.removeComponent(component.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove component")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var opsBar: some View {
        HStack(spacing: 8) {
            Text("Model:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Image Relief…") { session.importBitmapHeightfieldFromPanel() }
                .help("Import a black & white image as a heightmap (brightness → height)")
            Divider().frame(height: 14)
            Button("Zoom +") { zoom = min(8.0, zoom * 1.25) }
                .disabled(session.job.stlHeightfield == nil)
                .help("Zoom in on the relief")
            Button("Zoom −") { zoom = max(0.1, zoom / 1.25) }
                .disabled(session.job.stlHeightfield == nil)
                .help("Zoom out")
            Button("Reset View") {
                zoom = 1.0; panX = 0; panY = 0
            }
            .disabled(session.job.stlHeightfield == nil)
            .help("Reset camera to fit")
            // UI-polish cluster: view presets (reference "view cube / presets").
            Picker("View", selection: Binding(
                get: { currentViewPreset },
                set: { applyViewPreset($0) }
            )) {
                Text("Fit").tag(HeightfieldCamera.ViewPreset.fit)
                Text("1:1").tag(HeightfieldCamera.ViewPreset.oneToOne)
                Text("Top").tag(HeightfieldCamera.ViewPreset.top)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .disabled(session.job.stlHeightfield == nil)
            .help("View presets: Fit the whole relief, 1:1 pixels, or a 2× top view")
            Divider().frame(height: 14)
            Button("Rough 3D") { session.generateRough3DToolpath() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Z-level rough the relief into the Cut tree")
            Button("Finish 3D") { session.generateFinish3DToolpath() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Surface-following finish into the Cut tree")
            // SPK-0711 — zero plane + boundary from components.
            Button("Work Area") { _ = session.computeWorkAreaFromComponents() }
                .disabled(session.job.stlHeightfield == nil && (session.reliefComponents ?? []).isEmpty)
                .help("Compute the zero plane and boundary from the component stack")
            // SPK-0908 — level mirror modes (X / Y / both).
            Menu {
                Button("Mirror X") { _ = session.mirrorActiveRelief(axis: .horizontal) }
                Button("Mirror Y") { _ = session.mirrorActiveRelief(axis: .vertical) }
                Button("Mirror X + Y") { _ = session.mirrorActiveRelief(axis: .both) }
            } label: {
                Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .disabled(session.job.stlHeightfield == nil)
            .help("SPK-0908: flip the relief along X, Y, or both axes (3D ops marked dirty)")
            // SPK-0906 — laser cut/engrave G-code from the design vectors.
            Button("Laser…") { showLaserToolpath = true }
                .help("Generate laser cut or engrave G-code from the design vectors")
            Button("Export STL…") { exportSTL() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Export the relief as an ASCII STL mesh")
            // SPK-0708 — composite render: material/finish/lighting preview.
            Button("Composite Render…") { showCompositeRender = true }
                .disabled(session.job.stlHeightfield == nil)
                .help("Render the relief with a material, surface finish and lighting")
            Divider().frame(height: 14)
            // SPK-0700/0701 lean slice: component stack — capture the active
            // relief as a component, then combine multiple reliefs.
            Button("Add as Component") { session.addComponentFromActiveRelief(named: "Relief") }
                .disabled(session.job.stlHeightfield == nil)
                .help("Capture the current relief into the component stack (combine modes compose them)")
            // SPK-0703 — parametric shape tools: generate a shape relief
            // directly into the component stack (no import needed).
            Menu {
                Button("Angled") { session.addShapeComponent(shapeType: .angled, params: ShapeParameters()) }
                Button("Round") { session.addShapeComponent(shapeType: .round, params: ShapeParameters(radius: 4.0)) }
                Button("Smooth") { session.addShapeComponent(shapeType: .smooth, params: ShapeParameters(smoothness: 0.6)) }
                Button("Flat") { session.addShapeComponent(shapeType: .flat, params: ShapeParameters(flatHeight: 2.0)) }
            } label: {
                Label("Add Shape", systemImage: "square.stack.3d.up")
            }
            .help("Generate a parametric shape relief into the component stack (angled ramp / round dome / smooth bell / flat plane)")
            // SPK-0704 — combine-mode teacher.
            Button { showTeacher = true } label: {
                Label("Combine Help", systemImage: "lightbulb.fill")
            }
            .help("Learn what each combine mode does and when to use it")
            .sheet(isPresented: $showTeacher) {
                CombineModeTeacherSheet()
            }

            // SPK-1800h: orbit toggle — drag to rotate yaw/pitch around the relief.
            Divider().frame(height: 14)
            Toggle("Orbit", isOn: $orbitMode)
                .toggleStyle(.button)
                .accessibilityLabel("Orbit mode")
                .help("Orbit: drag to rotate the relief (yaw/pitch)")
            if !session.reliefComponents.isEmpty {
                Button("Recomposite") { session.recompositeRelief() }
                    .help("Re-run the combine modes over the component stack")
                Button("Bake") { session.bakeComponents() }
                    .help("Fold the visible component stack into the ACTIVE relief and clear the stack")
            }
            // SPK-0714 — two-rail sweep from the first two selected vectors.
            Menu {
                Button("Rectangle Profile") { _ = session.addSweepComponent(profile: .rectangle, height: 5.0) }
                Button("Circle Profile") { _ = session.addSweepComponent(profile: .circle, height: 5.0) }
            } label: {
                Label("Sweep from Vectors", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .help("Sweep a profile between the first two vectors (rails) into a component")
            Button("Split…") { showSplitDialog = true }
                .disabled(session.job.stlHeightfield == nil)
                .help("Split the active relief at a horizontal plane — keep the upper part")
            Divider().frame(height: 14)
            // SPK-0705 — interactive shape handles toggle.
            Button {
                if session.handleManager.handles.isEmpty {
                    session.createHandlesForComponent(session.reliefComponents.first?.id ?? UUID())
                } else {
                    session.clearHandles()
                }
            } label: {
                Label(session.handleManager.handles.isEmpty ? "Show Handles" : "Hide Handles",
                      systemImage: "circle.dashed")
            }
            .help("Toggle interactive handles for manipulating components")
            Toggle(isOn: $sculptMode) {
                Label("Sculpt", systemImage: "paintbrush.pointed.fill")
            }
            .toggleStyle(.button)
            .disabled(session.job.stlHeightfield == nil)
            .help("Sculpt the relief directly: drag on the canvas to apply the selected brush")
            Spacer()
            if let hf = session.job.stlHeightfield {
                Text("\(hf.width)×\(hf.height) @ \(String(format: "%.1f", hf.cellSizeMm))mm · peak \(String(format: "%.1f", hf.maxHeight))mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .controlSize(.small)
    }

    /// Sculpt tool strip: tool picker + brush size / strength sliders.
    /// Only shown while Sculpt mode is on (SPK-0713 lean slice).
    private var sculptBar: some View {
        HStack(spacing: 10) {
            Text("Brush:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Tool", selection: $sculptTool) {
                Text("Raise").tag(SculptTool.brush)
                Text("Lower").tag(SculptTool.deflate)
                Text("Smooth").tag(SculptTool.smooth)
                Text("Flatten").tag(SculptTool.flatten)
                Text("Inflate").tag(SculptTool.inflate)
                Text("Pinch").tag(SculptTool.pinch)
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .help("Sculpt tool: Raise/Lower push the surface, Smooth blends, Flatten levels toward the brush mean, Inflate/Pinch deform locally")

            Divider().frame(height: 14)

            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $brushRadiusMm, in: 1...30, step: 0.5)
                .frame(width: 120)
                .help("Brush radius in mm")
            Text(String(format: "%.1f mm", brushRadiusMm))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)

            Divider().frame(height: 14)

            Text("Strength")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $brushStrength, in: 0...1, step: 0.05)
                .frame(width: 120)
                .help("How strongly each stroke displaces the surface")
            Text(String(format: "%.0f%%", brushStrength * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Spacer()

            Button("Reset Relief") { resetRelief() }
                .help("Restore the relief to its pre-sculpt state")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .controlSize(.small)
    }

    /// The preset the current camera most closely matches (for the picker).
    /// Custom zoom/pan falls back to Fit so the segmented control stays sane.
    private var currentViewPreset: HeightfieldCamera.ViewPreset {
        if fitBase > 0, abs(zoom * fitBase - 1.0) < 0.05, abs(panX) < 0.01, abs(panY) < 0.01 {
            return .oneToOne
        }
        if abs(zoom - 2.0) < 0.05, abs(panX) < 0.01, abs(panY) < 0.01 {
            return .top
        }
        return .fit
    }

    private func applyViewPreset(_ preset: HeightfieldCamera.ViewPreset) {
        switch preset {
        case .fit:
            zoom = 1.0; panX = 0; panY = 0
        case .oneToOne:
            zoom = fitBase > 0 ? min(8.0, max(0.1, 1.0 / fitBase)) : 1.0
            panX = 0; panY = 0
        case .top:
            zoom = 2.0; panX = 0; panY = 0
        }
    }

    private func resetRelief() {
        // Undo collapses all sculpt strokes back to the import (single undo
        // chain per stroke); repeated undos walk back stroke by stroke.
        while session.undo() { }
    }

    private func infoBar(_ hf: HeightfieldData) -> some View {
        let contours = HeightfieldVisualizer.contourCounts(hf, levels: 5)
        return HStack {
            Text("Contours: \(contours.map(String.init).joined(separator: " · "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Drag to pan · scroll to zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func exportSTL() {
        let panel = NSSavePanel()
        panel.title = "Export STL"
        if let stlType = UTType(filenameExtension: "stl") {
            panel.allowedContentTypes = [stlType]
        }
        panel.nameFieldStringValue = "relief.stl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = session.exportSTL(to: url)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No 3D relief yet")
                .font(.title3.bold())
            Text("Import an STL model (Design → STL Relief…, ⌘K) or a black & white image (Image Relief…, ⌘K — brightness becomes height), then come back to view it and generate 3D toolpaths.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            HStack(spacing: 10) {
                Button("Go to Design") { session.selectedStage = .design }
                    .buttonStyle(.borderedProminent)
                Button("Import Image Relief…") { session.importBitmapHeightfieldFromPanel() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Relief Canvas

/// Renders the heightfield as a grayscale heightmap (white = peak) with a
/// drag-to-pan / scroll-to-zoom camera (SPK-3D-UI basic camera). In sculpt
/// mode the drag applies a brush stroke at the cursor instead of panning:
/// view point → world mm (inverse of the image layout transform) → stroke.
/// SPK-1800h: in Orbit mode, dragging rotates yaw/pitch around the relief.
private struct ReliefCanvasView: View {
    let hf: HeightfieldData
    @Binding var zoom: Double
    @Binding var panX: Double
    @Binding var panY: Double
    @Binding var fitBase: Double
    var sculptMode: Bool = false
    // SPK-1800h: orbit — drag to rotate yaw/pitch.
    var orbitMode: Bool = false
    var strokeParams: SculptStrokeParams = SculptStrokeParams()
    var onStroke: ((CGPoint, Bool) -> Void)? = nil
    var handles: [ShapeHandle] = []
    var onHandleDrag: ((UUID, Double, Double, Double, Bool) -> Void)? = nil
    @State private var strokeLocation: CGPoint?
    @State private var dragIsLive: Bool = false
    @State private var activeHandleID: UUID?
    @State private var handleDragStart: CGPoint?
    @State private var lastDragTranslation: CGSize?
    @State private var handleDragLive: Bool = false
    // SPK-1800h: 2.5D orbit state.
    @State private var orbitYaw: Double = 0
    @State private var orbitPitch: Double = 0

    var body: some View {
        GeometryReader { geo in
            let render = HeightfieldVisualizer.heightmapGrayscale(hf, pixelSize: 1)
            let w = CGFloat(render.widthPx)
            let h = CGFloat(render.heightPx)
            let base = min(geo.size.width / w, geo.size.height / h)
            let scale = base * zoom
            let offsetX = (geo.size.width - w * scale) / 2 + panX * scale
            let offsetY = (geo.size.height - h * scale) / 2 + panY * scale

            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let image = makeImage(render.pixels, w: render.widthPx, h: render.heightPx) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: w * scale, height: h * scale)
                        .offset(x: offsetX, y: offsetY)
                }
                if sculptMode, let strokeLocation {
                    // Brush cursor ring: world-space radius at current zoom.
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: CGFloat(strokeParams.radiusMm) * scale * 2,
                               height: CGFloat(strokeParams.radiusMm) * scale * 2)
                        .position(strokeLocation)
                        .allowsHitTesting(false)
                }
                // SPK-0705 — interactive shape handles rendered as colored dots.
                // Tap a handle to activate it (the drag path reads activeHandleID).
                if !handles.isEmpty {
                    ForEach(handles) { handle in
                        let cellX = Int(handle.position.x)
                        let cellY = Int(handle.position.y)
                        let cellZ = Int(handle.position.z)
                        // Map handle position (in grid coords) to screen position.
                        let screenX = offsetX + CGFloat(cellX) * scale + (w * scale) / 2
                        let screenY = offsetY + CGFloat(cellY) * scale + (h * scale) / 2
                        Circle()
                            .fill(handle.handleType == .scale ? Color.green :
                                  handle.handleType == .rotate ? Color.blue :
                                  cellX == 1 ? Color.red :
                                  cellY == 1 ? Color.green :
                                  cellZ == 1 ? Color.blue : Color.orange)
                            .frame(width: 8, height: 8)
                            .position(x: screenX, y: screenY)
                            .contentShape(Circle())
                            .onTapGesture {
                                activeHandleID = handle.id
                                handleDragLive = false
                                lastDragTranslation = nil
                            }
                    }
                }
            }
            .onAppear { fitBase = Double(base) }
            .onChange(of: geo.size) { _, _ in fitBase = Double(base) }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: sculptMode ? 0 : 1)
                    .onChanged { value in
                        if sculptMode {
                            let p = value.location
                            strokeLocation = p
                            onStroke?(worldPoint(from: p, offsetX: offsetX, offsetY: offsetY, scale: scale), !dragIsLive)
                            dragIsLive = true
                        } else if orbitMode {
                            // SPK-1800h: orbit — drag rotates yaw/pitch.
                            let last = lastDragTranslation ?? value.translation
                            orbitYaw += (value.translation.width - last.width) * 0.5
                            orbitPitch += (value.translation.height - last.height) * 0.5
                            orbitPitch = max(-89, min(89, orbitPitch))
                            lastDragTranslation = value.translation
                        } else if let activeHandleID {
                            let last = lastDragTranslation ?? value.translation
                            let dx = (value.translation.width - last.width) / scale
                            let dy = (value.translation.height - last.height) / scale
                            lastDragTranslation = value.translation
                            onHandleDrag?(activeHandleID, dx, dy, 0, !handleDragLive)
                            handleDragLive = true
                        } else {
                            let last = lastDragTranslation ?? value.translation
                            panX += (value.translation.width - last.width) / scale
                            panY += (value.translation.height - last.height) / scale
                            lastDragTranslation = value.translation
                        }
                    }
                    .onEnded { _ in
                        if sculptMode {
                            strokeLocation = nil
                            dragIsLive = false
                        } else if activeHandleID != nil {
                            activeHandleID = nil
                            handleDragStart = nil
                            handleDragLive = false
                        }
                        lastDragTranslation = nil
                    }
            )
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                zoom = min(8.0, max(0.1, zoom * value))
            })
        }
    }

    /// View point → world mm. The image is laid out at (offsetX, offsetY)
    /// with `scale` pixels per cell; each cell is cellSizeMm wide, so world
    /// x = minX + cellX · cellSizeMm where cellX = (p − offsetX) / scale.
    private func worldPoint(from p: CGPoint, offsetX: CGFloat, offsetY: CGFloat, scale: CGFloat) -> CGPoint {
        let cellX = (p.x - offsetX) / scale
        let cellY = (p.y - offsetY) / scale
        return CGPoint(
            x: hf.minX + Double(cellX) * hf.cellSizeMm,
            y: hf.minY + Double(cellY) * hf.cellSizeMm
        )
    }

    private func makeImage(_ pixels: [UInt8], w: Int, h: Int) -> NSImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
        ) else { return nil }
        pixels.withUnsafeBufferPointer { buf in
            if let dst = rep.bitmapData {
                memcpy(dst, buf.baseAddress, w * h * 4)
            }
        }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - Component Props Popover (SPK-0702)

/// Dynamic-props editor for one relief component: height scale, tilt angle,
/// and directional fade. Every change calls back to the session
/// (`updateComponentModifiers`) which recomposites live — the Model view and
/// the 3D toolpaths reflect the modified surface immediately.
private struct ComponentPropsPopover: View {
    let component: ReliefComponent
    var onUpdate: (Double?, Double?, Double?, FadeDirection?) -> Void

    @State private var heightScale: Double
    @State private var tilt: Double
    @State private var fadeAmount: Double
    @State private var fadeDirection: FadeDirection

    init(component: ReliefComponent, onUpdate: @escaping (Double?, Double?, Double?, FadeDirection?) -> Void) {
        self.component = component
        self.onUpdate = onUpdate
        _heightScale = State(initialValue: component.heightScale ?? 1.0)
        _tilt = State(initialValue: component.tiltAngleDegrees ?? 0.0)
        _fadeAmount = State(initialValue: component.fadeAmount ?? 0.0)
        _fadeDirection = State(initialValue: component.fadeDirection ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dynamic Props — \(component.name)")
                .font(.headline)

            // Height scale
            HStack {
                Text("Height")
                    .font(.caption)
                    .frame(width: 52, alignment: .leading)
                Slider(value: $heightScale, in: 0.1...3.0)
                    .frame(width: 140)
                Text(String(format: "%.2f×", heightScale))
                    .font(.caption2)
                    .frame(width: 44, alignment: .trailing)
            }
            .onChange(of: heightScale) { _, v in
                onUpdate(v, nil, nil, nil)
            }

            // Tilt
            HStack {
                Text("Tilt")
                    .font(.caption)
                    .frame(width: 52, alignment: .leading)
                Slider(value: $tilt, in: -45...45)
                    .frame(width: 140)
                Text(String(format: "%.0f°", tilt))
                    .font(.caption2)
                    .frame(width: 44, alignment: .trailing)
            }
            .onChange(of: tilt) { _, v in
                onUpdate(nil, v, nil, nil)
            }

            // Fade
            HStack {
                Text("Fade")
                    .font(.caption)
                    .frame(width: 52, alignment: .leading)
                Slider(value: $fadeAmount, in: 0...1)
                    .frame(width: 140)
                Text(String(format: "%.0f%%", fadeAmount * 100))
                    .font(.caption2)
                    .frame(width: 44, alignment: .trailing)
            }
            .onChange(of: fadeAmount) { _, v in
                onUpdate(nil, nil, v, nil)
            }

            Picker("Direction", selection: $fadeDirection) {
                Text("None").tag(FadeDirection.none)
                Text("Left → Right").tag(FadeDirection.leftToRight)
                Text("Right → Left").tag(FadeDirection.rightToLeft)
                Text("Top → Bottom").tag(FadeDirection.topToBottom)
                Text("Bottom → Top").tag(FadeDirection.bottomToTop)
                Text("Center Out").tag(FadeDirection.centerOut)
                Text("Radial").tag(FadeDirection.radial)
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .onChange(of: fadeDirection) { _, v in
                onUpdate(nil, nil, nil, v)
            }

            Text("Applied live — the Model view and 3D toolpaths use the modified surface. The stored grid is untouched (props are reversible).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}
