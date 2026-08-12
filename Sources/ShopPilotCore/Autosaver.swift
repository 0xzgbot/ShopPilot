import Foundation

// MARK: - Autosaver

/// Automatically saves a dirty document at regular intervals.
public final class Autosaver: @unchecked Sendable {
    
    /// The interval between autosaves. Default is 5 minutes.
    public static let defaultInterval: TimeInterval = 300
    
    private var timer: Timer?
    private var document: Job?
    /// Optional live-document provider (SPK-1402a). When set, autosave reads
    /// the CURRENT job through this closure on every tick instead of the
    /// init-time value, so a value-type `Job` replaced by the session (open /
    /// sample / recipe) is still saved fresh.
    private let documentProvider: (() -> Job?)?
    /// Optional live dirty-flag provider (SPK-1402a). When set it wins over
    /// `document.isDirty` — the app's dirty state lives on the session, and
    /// `Job` is a value type whose `isDirty` is always `false`.
    private let isDocumentDirty: (() -> Bool)?
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
    ///   - documentProvider: Optional live-document closure — autosave writes
    ///     whatever it returns each tick (default: the init-time `document`).
    ///   - isDocumentDirty: Optional dirty-flag closure — autosave writes only
    ///     while it returns true (default: `document.isDirty`).
    public init(
        document: Job,
        saveURL: URL,
        interval: TimeInterval = Autosaver.defaultInterval,
        documentProvider: (() -> Job?)? = nil,
        isDocumentDirty: (() -> Bool)? = nil
    ) {
        self.document = document
        self.saveURL = saveURL
        self.interval = interval
        self.saver = DocumentSaver()
        self.lastSavedState = .now
        self.documentProvider = documentProvider
        self.isDocumentDirty = isDocumentDirty
    }
    
    // MARK: - Lifecycle
    
    /// Start autosaving. If the document is already dirty, saves immediately.
    public func start() {
        stop()
        
        if isDirtyNow {
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
    
    /// The document to save: the live provider result when available,
    /// otherwise the init-time value.
    private var currentDocument: Job? {
        if let provider = documentProvider { return provider() }
        return document
    }
    
    /// Whether the document currently needs saving.
    private var isDirtyNow: Bool {
        if let check = isDocumentDirty { return check() }
        return currentDocument?.isDirty ?? false
    }
    
    private func saveIfNeeded() {
        guard let doc = currentDocument, isDirtyNow else { return }
        
        do {
            try saver.save(doc, to: saveURL)
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
