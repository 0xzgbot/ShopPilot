import SwiftUI
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

    var body: some View {
        VStack(spacing: 0) {
            opsBar
            Divider()
            if let hf = session.job.stlHeightfield {
                ReliefCanvasView(hf: hf, zoom: $zoom, panX: $panX, panY: $panY)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No 3D relief yet")
                .font(.title3.bold())
            Text("Import an STL model from Design → STL Relief…, then come back to view it and generate 3D toolpaths.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            Button("Go to Design") { session.selectedStage = .design }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Relief Canvas

/// Renders the heightfield as a grayscale heightmap (white = peak) with a
/// drag-to-pan / scroll-to-zoom camera (SPK-3D-UI basic camera).
private struct ReliefCanvasView: View {
    let hf: HeightfieldData
    @Binding var zoom: Double
    @Binding var panX: Double
    @Binding var panY: Double

    var body: some View {
        GeometryReader { geo in
            let render = HeightfieldVisualizer.heightmapGrayscale(hf, pixelSize: 1)
            let w = CGFloat(render.widthPx)
            let h = CGFloat(render.heightPx)
            let base = min(geo.size.width / w, geo.size.height / h)
            let scale = base * zoom

            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let image = makeImage(render.pixels, w: render.widthPx, h: render.heightPx) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: w * scale, height: h * scale)
                        .offset(
                            x: (geo.size.width - w * scale) / 2 + panX * scale,
                            y: (geo.size.height - h * scale) / 2 + panY * scale
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                panX += value.translation.width / scale
                panY += value.translation.height / scale
            })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                zoom = min(8.0, max(0.1, zoom * value))
            })
        }
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
