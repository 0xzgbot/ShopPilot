import Foundation

// MARK: - Orientation

/// How the job is oriented on the stock.
public enum Orientation: String, Codable, Sendable, CaseIterable {
    case singleSided
    case doubleSided
    case rotary
}

// MARK: - Side

/// Which side of the stock is active.
public enum Side: String, Codable, Sendable, CaseIterable {
    case front
    case back
}

// MARK: - RegistrationMark

/// A fiducial mark placed on the stock for alignment between front and back sides.
public struct RegistrationMark: Identifiable, Codable, Sendable {
    public let id: UUID
    public var x: Double          // X position in mm
    public var y: Double          // Y position in mm
    public var diameter: Double   // Mark diameter in mm
    public var visible: Bool      // Visibility flag

    public init(id: UUID = UUID(), x: Double, y: Double, diameter: Double, visible: Bool = true) {
        self.id = id
        self.x = x
        self.y = y
        self.diameter = diameter
        self.visible = visible
    }
}

// MARK: - DoubleSidedJob

/// Wraps a `Job` with double-sided metadata: orientation, side flips, and registration marks.
public struct DoubleSidedJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public var job: Job
    public var orientation: Orientation
    public var backSideZOffset: Double   // Z offset for back side (mm)
    public var backSideMirrorX: Bool     // Whether to mirror X on back side
    public var backSideMirrorY: Bool     // Whether to mirror Y on back side
    public var registrationMarks: [RegistrationMark]
    public var activeSide: Side

    public init(
        id: UUID = UUID(),
        job: Job,
        orientation: Orientation = .doubleSided,
        backSideZOffset: Double = 0.0,
        backSideMirrorX: Bool = false,
        backSideMirrorY: Bool = false,
        registrationMarks: [RegistrationMark] = [],
        activeSide: Side = .front
    ) {
        self.id = id
        self.job = job
        self.orientation = orientation
        self.backSideZOffset = backSideZOffset
        self.backSideMirrorX = backSideMirrorX
        self.backSideMirrorY = backSideMirrorY
        self.registrationMarks = registrationMarks
        self.activeSide = activeSide
    }

    // MARK: - Registration Mark Management

    /// Add a registration mark; returns its UUID.
    @discardableResult
    public mutating func addRegistrationMark(x: Double, y: Double, diameter: Double) -> UUID {
        let mark = RegistrationMark(x: x, y: y, diameter: diameter)
        registrationMarks.append(mark)
        return mark.id
    }

    /// Remove a registration mark by ID. Returns `true` if found and removed.
    @discardableResult
    public mutating func removeRegistrationMark(_ id: UUID) -> Bool {
        guard let index = registrationMarks.firstIndex(where: { $0.id == id }) else { return false }
        registrationMarks.remove(at: index)
        return true
    }

    // MARK: - Sheet Accessors

    /// Returns the first sheet (front side).
    public func getFrontSheet() -> Sheet? {
        job.sheets.first
    }

    /// Returns the second sheet if present (back side).
    public func getBackSheet() -> Sheet? {
        job.sheets.count > 1 ? job.sheets[1] : nil
    }

    // MARK: - Side Flipping

    /// Flip the active side to back.
    public mutating func flipToBack() {
        activeSide = .back
    }

    /// Flip the active side to front.
    public mutating func flipToFront() {
        activeSide = .front
    }

    /// Returns the currently active sheet for the active side.
    public func activeSheet() -> Sheet? {
        activeSide == .back ? getBackSheet() : getFrontSheet()
    }

    /// Returns the current orientation.
    public func currentOrientation() -> Orientation {
        orientation
    }
}
