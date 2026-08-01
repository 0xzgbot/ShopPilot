import Foundation

// MARK: - Production Golden Jobs

// Golden job type.
public enum GoldenJobType: String, Codable, Sendable {
    case calibration
    case verification
    case certification
    case benchmark
    case regression
}

// Golden job status.
public enum GoldenJobStatus: String, Codable, Sendable {
    case pending
    case running
    case passed
    case failed
    case warning
}

// Production golden job configuration.
public struct ProductionGoldenJobConfig: Codable, Sendable {
    public var name: String
    public var description: String
    public var jobType: GoldenJobType
    public var material: String
    public var toolPath: String
    public var expectedDimensions: [String: Double]
    public var tolerance: Double
    public var maxTimeMinutes: Double
    public var requiredPasses: Int
    public var passCount: Int
    public var failCount: Int
    public var warningCount: Int
    public var status: GoldenJobStatus
    public var lastRunDate: Date?
    public var results: [ProductionGoldenJobResult]
    
    public init(
        name: String,
        description: String,
        jobType: GoldenJobType = .calibration,
        material: String = "18mm MDF",
        toolPath: String = "/default/toolpath",
        expectedDimensions: [String: Double] = [:],
        tolerance: Double = 0.1,
        maxTimeMinutes: Double = 30.0,
        requiredPasses: Int = 3,
        passCount: Int = 0,
        failCount: Int = 0,
        warningCount: Int = 0,
        status: GoldenJobStatus = .pending,
        lastRunDate: Date? = nil,
        results: [ProductionGoldenJobResult] = []
    ) {
        self.name = name
        self.description = description
        self.jobType = jobType
        self.material = material
        self.toolPath = toolPath
        self.expectedDimensions = expectedDimensions
        self.tolerance = max(0.0, tolerance)
        self.maxTimeMinutes = max(0.1, maxTimeMinutes)
        self.requiredPasses = max(1, requiredPasses)
        self.passCount = passCount
        self.failCount = failCount
        self.warningCount = warningCount
        self.status = status
        self.lastRunDate = lastRunDate
        self.results = results
    }
}

// Production golden job result.
public struct ProductionGoldenJobResult: Codable, Sendable {
    public let id: UUID
    public let runDate: Date
    public let status: GoldenJobStatus
    public let durationMinutes: Double
    public let actualDimensions: [String: Double]
    public let deviations: [String: Double]
    public let errors: [String]
    public let warnings: [String]
    public let notes: String
    
    public init(
        id: UUID = UUID(),
        runDate: Date = Date(),
        status: GoldenJobStatus = .pending,
        durationMinutes: Double = 0.0,
        actualDimensions: [String: Double] = [:],
        deviations: [String: Double] = [:],
        errors: [String] = [],
        warnings: [String] = [],
        notes: String = ""
    ) {
        self.id = id
        self.runDate = runDate
        self.status = status
        self.durationMinutes = max(0.0, durationMinutes)
        self.actualDimensions = actualDimensions
        self.deviations = deviations
        self.errors = errors
        self.warnings = warnings
        self.notes = notes
    }
}

// Production golden job manager.
public final class ProductionGoldenJobManager: ObservableObject {
    @Published public var jobs: [ProductionGoldenJobConfig]
    @Published public var activeJobID: UUID?
    
    public init() {
        self.jobs = []
        self.activeJobID = nil
    }
    
    // Creates a new golden job.
    @discardableResult
    public func addJob(
        name: String,
        description: String,
        jobType: GoldenJobType = .calibration,
        material: String = "18mm MDF",
        tolerance: Double = 0.1,
        maxTimeMinutes: Double = 30.0,
        requiredPasses: Int = 3
    ) -> ProductionGoldenJobConfig {
        let config = ProductionGoldenJobConfig(
            name: name,
            description: description,
            jobType: jobType,
            material: material,
            tolerance: tolerance,
            maxTimeMinutes: maxTimeMinutes,
            requiredPasses: requiredPasses
        )
        jobs.append(config)
        activeJobID = UUID()
        return config
    }
    
    // Removes a golden job.
    public func removeJob(at index: Int) {
        guard index < jobs.count else { return }
        jobs.remove(at: index)
    }
    
    // Runs a golden job (simulated).
    public func runJob(_ config: ProductionGoldenJobConfig) -> ProductionGoldenJobResult {
        let result = ProductionGoldenJobResult(
            status: .passed,
            durationMinutes: Double.random(in: 5...25),
            actualDimensions: config.expectedDimensions,
            deviations: [:],
            errors: [],
            warnings: [],
            notes: "Golden job completed successfully"
        )
        
        // Update job state
        var updatedConfig = config
        updatedConfig.status = .passed
        updatedConfig.passCount += 1
        updatedConfig.lastRunDate = Date()
        updatedConfig.results.append(result)
        
        // Replace in array
        if let index = jobs.firstIndex(where: { $0.name == config.name }) {
            jobs[index] = updatedConfig
        }
        
        return result
    }
    
    // Gets all jobs.
    public func getAllJobs() -> [ProductionGoldenJobConfig] {
        jobs
    }
    
    // Gets jobs by type.
    public func getJobs(by type: GoldenJobType) -> [ProductionGoldenJobConfig] {
        jobs.filter { $0.jobType == type }
    }
    
    // Gets jobs by status.
    public func getJobs(by status: GoldenJobStatus) -> [ProductionGoldenJobConfig] {
        jobs.filter { $0.status == status }
    }
    
    // Clears all jobs.
    public func clearAll() {
        jobs.removeAll()
        activeJobID = nil
    }
    
    // Validates a golden job config.
    public static func validate(_ config: ProductionGoldenJobConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.name.isEmpty { errors.append("Name is required") }
        if config.description.isEmpty { errors.append("Description is required") }
        if config.tolerance < 0 { errors.append("Tolerance must be non-negative") }
        if config.maxTimeMinutes <= 0 { errors.append("Max time must be positive") }
        if config.requiredPasses < 1 { errors.append("Required passes must be at least 1") }
        
        return (errors.isEmpty, errors)
    }
}
