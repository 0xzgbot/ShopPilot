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
    @State private var sculptMode: Bool = false
    @State private var sculptTool: SculptTool = .brush
    @State private var brushRadiusMm: Double = 5.0
    @State private var brushStrength: Double = 0.5
    @State private var brushShape: BrushShape = .sphere
    @State private var brushFalloff: BrushFalloff = .smooth

    var body: some View {
        VStack(spacing: 0) {
            opsBar
            if sculptMode {
                Divider()
                sculptBar
            }
            Divider()
            if let hf = session.job.stlHeightfield {
                ReliefCanvasView(
                    hf: hf,
                    zoom: $zoom, panX: $panX, panY: $panY,
                    sculptMode: sculptMode,
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
                    }
                )
                Divider()
                infoBar(hf)
            } else {
                emptyState
            }
        }
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
            Divider().frame(height: 14)
            Button("Rough 3D") { session.generateRough3DToolpath() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Z-level rough the relief into the Cut tree")
            Button("Finish 3D") { session.generateFinish3DToolpath() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Surface-following finish into the Cut tree")
            Button("Export STL…") { exportSTL() }
                .disabled(session.job.stlHeightfield == nil)
                .help("Export the relief as an ASCII STL mesh")
            Divider().frame(height: 14)
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
private struct ReliefCanvasView: View {
    let hf: HeightfieldData
    @Binding var zoom: Double
    @Binding var panX: Double
    @Binding var panY: Double
    var sculptMode: Bool = false
    var strokeParams: SculptStrokeParams = SculptStrokeParams()
    var onStroke: ((CGPoint, Bool) -> Void)? = nil
    @State private var strokeLocation: CGPoint?
    @State private var dragIsLive: Bool = false

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
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: sculptMode ? 0 : 1)
                    .onChanged { value in
                        if sculptMode {
                            let p = value.location
                            strokeLocation = p
                            // First stroke of a drag records the undo point;
                            // subsequent ones apply without re-snapshotting so
                            // one gesture = one undo entry (grid snapshots are
                            // MB-sized on big reliefs).
                            onStroke?(worldPoint(from: p, offsetX: offsetX, offsetY: offsetY, scale: scale), !dragIsLive)
                            dragIsLive = true
                        } else {
                            panX += value.translation.width / scale
                            panY += value.translation.height / scale
                        }
                    }
                    .onEnded { _ in
                        if sculptMode {
                            strokeLocation = nil
                            dragIsLive = false
                        }
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
