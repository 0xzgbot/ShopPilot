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
