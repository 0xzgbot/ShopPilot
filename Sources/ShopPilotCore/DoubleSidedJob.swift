import Foundation

// MARK: - Double-Sided Job

// Side of a double-sided job.
public enum JobSide: String, Codable, Sendable {
    case front
    case back
}

// Double-sided job configuration.
public struct DoubleSidedJobConfig: Codable, Sendable {
    public var frontSheetID: UUID
    public var backSheetID: UUID
    public var alignmentMethod: AlignmentMethod
    public var registrationMarks: [RegistrationMark]
    public var backSideZOffset: Double
    public var backSideRotation: Double
    public var backSideFlipX: Bool
    public var backSideFlipY: Bool
    
    public init(
        frontSheetID: UUID,
        backSheetID: UUID,
        alignmentMethod: AlignmentMethod = .registrationMarks,
        registrationMarks: [RegistrationMark] = [],
        backSideZOffset: Double = 0.0,
        backSideRotation: Double = 0.0,
        backSideFlipX: Bool = false,
        backSideFlipY: Bool = false
    ) {
        self.frontSheetID = frontSheetID
        self.backSheetID = backSheetID
        self.alignmentMethod = alignmentMethod
        self.registrationMarks = registrationMarks
        self.backSideZOffset = backSideZOffset
        self.backSideRotation = backSideRotation
        self.backSideFlipX = backSideFlipX
        self.backSideFlipY = backSideFlipY
    }
}

// Alignment method for double-sided jobs.
public enum AlignmentMethod: String, Codable, Sendable {
    case registrationMarks
    case edgeAlignment
    case gridAlignment
    case manualOffset
}

// Registration mark for alignment.
public struct RegistrationMark: Identifiable, Codable, Sendable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var side: JobSide
    public var detected: Bool
    
    public init(
        id: UUID = UUID(),
        x: Double = 0.0,
        y: Double = 0.0,
        side: JobSide = .front,
        detected: Bool = false
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.side = side
        self.detected = detected
    }
}

// Alignment offset for double-sided jobs.
public struct AlignmentOffset: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    
    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// Double-sided job result.
public struct DoubleSidedJobResult: Codable, Sendable {
    public var config: DoubleSidedJobConfig
    public var frontJobID: UUID
    public var backJobID: UUID
    public var alignmentOffset: AlignmentOffset
    public var totalToolpathLength: Double
    public var estimatedTimeMinutes: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: DoubleSidedJobConfig,
        frontJobID: UUID,
        backJobID: UUID,
        alignmentOffset: AlignmentOffset,
        totalToolpathLength: Double,
        estimatedTimeMinutes: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.frontJobID = frontJobID
        self.backJobID = backJobID
        self.alignmentOffset = alignmentOffset
        self.totalToolpathLength = totalToolpathLength
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - DoubleSidedJobManager

// Manages double-sided job creation and execution.
public final class DoubleSidedJobManager: ObservableObject {
    @Published public var jobs: [DoubleSidedJobResult]
    @Published public var activeJobID: UUID?
    
    public init() {
        self.jobs = []
        self.activeJobID = nil
    }
    
    // Creates a new double-sided job from two sheets.
    @discardableResult
    public func createJob(
        frontSheetID: UUID,
        backSheetID: UUID,
        alignmentMethod: AlignmentMethod = .registrationMarks,
        backSideZOffset: Double = 0.0,
        backSideRotation: Double = 0.0,
        backSideFlipX: Bool = false,
        backSideFlipY: Bool = false
    ) -> DoubleSidedJobResult {
        let config = DoubleSidedJobConfig(
            frontSheetID: frontSheetID,
            backSheetID: backSheetID,
            alignmentMethod: alignmentMethod,
            backSideZOffset: backSideZOffset,
            backSideRotation: backSideRotation,
            backSideFlipX: backSideFlipX,
            backSideFlipY: backSideFlipY
        )
        
        let frontJobID = UUID()
        let backJobID = UUID()
        let alignmentOffset = AlignmentOffset(x: 0.0, y: 0.0, z: backSideZOffset)
        
        // Estimate toolpath length (simplified)
        let frontLength = Double.random(in: 5000...20000)
        let backLength = Double.random(in: 5000...20000)
        let totalLength = frontLength + backLength
        
        // Estimate time (simplified)
        let avgFeedRate = 1000.0 // mm/min
        let totalTime = totalLength / avgFeedRate * 60.0 + 10.0 // 10 min setup
        
        let result = DoubleSidedJobResult(
            config: config,
            frontJobID: frontJobID,
            backJobID: backJobID,
            alignmentOffset: alignmentOffset,
            totalToolpathLength: totalLength,
            estimatedTimeMinutes: totalTime,
            success: true
        )
        
        jobs.append(result)
        activeJobID = result.config.frontSheetID
        
        return result
    }
    
    // Gets the active job.
    public func getActiveJob() -> DoubleSidedJobResult? {
        guard let id = activeJobID else { return nil }
        return jobs.first(where: { $0.config.frontSheetID == id })
    }
    
    // Gets a job by front sheet ID.
    public func getJob(forFrontSheetID id: UUID) -> DoubleSidedJobResult? {
        jobs.first(where: { $0.config.frontSheetID == id })
    }
    
    // Removes a job by front sheet ID.
    public func removeJob(forFrontSheetID id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.config.frontSheetID == id }) else { return }
        jobs.remove(at: idx)
        if activeJobID == id {
            activeJobID = jobs.first?.config.frontSheetID
        }
    }
    
    // Updates alignment marks for a job.
    public func updateAlignmentMarks(
        forFrontSheetID frontSheetID: UUID,
        marks: [RegistrationMark]
    ) {
        guard let idx = jobs.firstIndex(where: { $0.config.frontSheetID == frontSheetID }) else { return }
        var config = jobs[idx].config
        config.registrationMarks = marks
        jobs[idx].config = config
    }
    
    // Gets all jobs.
    public func getAllJobs() -> [DoubleSidedJobResult] {
        jobs
    }
    
    // Clears all jobs.
    public func clearAll() {
        jobs.removeAll()
        activeJobID = nil
    }
}
