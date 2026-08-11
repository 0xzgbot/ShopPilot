import SwiftUI
import ShopPilotCore
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Webcam overlay (SPK-1008)

/// A floating webcam overlay for the Preview stage: shows the live camera
/// feed (AVCaptureSession) in a small draggable corner card so the operator
/// can watch the stock while the sim runs. Degrades gracefully — when no
/// camera is available the card shows a clear "no camera" note instead of an
/// error. macOS-only app; the overlay is a compile-checked surface (hardware
/// capture can't be exercised by CLTs).
struct WebcamOverlayView: View {
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CAMERA")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isVisible = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #if canImport(AVFoundation)
                CameraPreview()
                    .frame(width: 200, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                #else
                noCameraNote
                #endif
            }
            .padding(10)
            .background(.bar)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 6)
        }
    }

    private var noCameraNote: some View {
        Text("Camera unavailable on this build")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 200, height: 150)
    }
}

#if canImport(AVFoundation)
/// NSViewRepresentable wrapping an AVCaptureVideoPreviewLayer. Starts the
/// session on appear (default camera); stops on disappear. Any failure just
/// leaves the preview black — never an alert.
struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var session: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?

        func attach(to view: PreviewNSView) {
            let session = AVCaptureSession()
            session.sessionPreset = .medium
            let device = AVCaptureDevice.default(for: .video)
            if let device,
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer = layer
            view.wantsLayer = true
            self.session = session
            self.previewLayer = layer
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        deinit {
            if session?.isRunning == true {
                session?.stopRunning()
            }
        }
    }

    final class PreviewNSView: NSView {
        override func layout() {
            super.layout()
            layer?.frame = bounds
        }
    }
}
#endif

// MARK: - View gizmo (SPK-1206)

/// Mini nav-cube overlay: three tappable faces (top / isometric / front)
/// that switch the preview's 2.5D orientation, matching Aspire's view
/// control pattern. The active face is highlighted; the cube is small so it
/// never blocks the canvas.
struct ViewGizmoView: View {
    @Binding var orientation: ViewOrientation

    var body: some View {
        VStack(spacing: 3) {
            gizmoFace(.isometric, icon: "cube.fill")
            HStack(spacing: 3) {
                gizmoFace(.top, icon: "square.grid.2x2")
                gizmoFace(.front, icon: "rectangle.portrait")
            }
        }
        .padding(6)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .help("View orientation — ⌘⌥1 top, ⌘⌥2 isometric, ⌘⌥3 front")
    }

    private func gizmoFace(_ face: ViewOrientation, icon: String) -> some View {
        let isActive = orientation == face
        return Button {
            orientation = face
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 22, height: 18)
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.10))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(face.title)
    }
}

// MARK: - Plugins panel (SPK-1006 loadable ABI)

/// Left-pane plugin strip: lists discovered plugins with their kind and a
/// Run action for toolpath strategies (injects the plugin's G-code as a
/// toolpath node). Discovery covers Application Support/ShopPilot/Plugins +
/// the bundled sample in fixtures/plugins (repo dev).
struct PluginsPanelView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PLUGINS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(session.pluginStore.plugins.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if session.pluginStore.plugins.isEmpty {
                Text("No plugins found — drop a plugin folder into Application Support/ShopPilot/Plugins.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(session.pluginStore.plugins) { plugin in
                            HStack(spacing: 4) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(plugin.manifest.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(plugin.manifest.kind.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 2)
                                if plugin.manifest.kind == .toolpathStrategy {
                                    Button("Run") {
                                        _ = session.runPluginStrategy(plugin)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Run this plugin and add its G-code to the tree")
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Multi-file job queue panel (SPK-1008)

/// Left-pane queue strip: shows the sequential multi-file run queue with
/// per-program status, advance (step) and clear. Programs enqueue from the
/// Cut toolbar ("Enqueue"); the machine stage streams the current program.
struct JobQueuePanelView: View {
    @ObservedObject var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RUN QUEUE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(session.jobQueue.completedCount)/\(session.jobQueue.programs.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if session.jobQueue.programs.isEmpty {
                Text("No programs queued — use Enqueue in the toolbar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(session.jobQueue.programs.enumerated()), id: \.element.id) { idx, program in
                            HStack(spacing: 4) {
                                Text("\(idx + 1).")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(program.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if program.completed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else if session.jobQueue.currentIndex == idx {
                                    Image(systemName: "play.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                Text("\(program.gcode.count)L")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(idx == session.jobQueue.currentIndex
                                        ? Color.accentColor.opacity(0.10)
                                        : Color.clear)
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 110)

                HStack(spacing: 6) {
                    Button("Next") { _ = session.jobQueue.advance() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(session.jobQueue.current == nil)
                        .help("Mark the current program done and move to the next")
                    Button("Clear") { session.jobQueue.clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Empty the queue")
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
