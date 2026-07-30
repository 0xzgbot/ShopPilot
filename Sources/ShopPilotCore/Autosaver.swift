import Foundation

// MARK: - Autosaver

/// Automatically saves a dirty document at regular intervals.
public final class Autosaver: @unchecked Sendable {
    
    /// The interval between autosaves. Default is 5 minutes.
    public static let defaultInterval: TimeInterval = 300
    
    private var timer: Timer?
    private var document: Job?
    private let saveURL: URL
    private let interval: TimeInterval
    private let saver: DocumentSaver
    private var lastSavedState: Date
    
    /// Whether autosaving is currently active.
    public var isActive: Bool { timer != nil }
    
    // MARK: - Init
    
    /// Create an Autosaver for the given document and save URL.
    /// - Parameters:
    ///   - document: The Job to monitor for changes (must conform to DirtyDocument).
    ///   - saveURL: The URL where the .shoppilot package should be saved.
    ///   - interval: Time between autosaves in seconds (default 300).
    public init(
        document: Job,
        saveURL: URL,
        interval: TimeInterval = Autosaver.defaultInterval
    ) {
        self.document = document
        self.saveURL = saveURL
        self.interval = interval
        self.saver = DocumentSaver()
        self.lastSavedState = .now
    }
    
    // MARK: - Lifecycle
    
    /// Start autosaving. If the document is already dirty, saves immediately.
    public func start() {
        stop()
        
        if let doc = document, doc.isDirty {
            saveIfNeeded()
        }
        
        timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.saveIfNeeded()
        }
    }
    
    /// Stop autosaving and invalidate the timer.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Internal
    
    private func saveIfNeeded() {
        guard let doc = document, doc.isDirty else { return }
        
        do {
            try saver.save(doc as! Job, to: saveURL)
            lastSavedState = .now
        } catch {
            // In a real app, log this error. For v0, silently skip.
            print("Autosave failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct Autosaver_Previews: PreviewProvider {
    static var previews: some View {
        Text("Autosaver is a non-visual component")
    }
}
#endif
