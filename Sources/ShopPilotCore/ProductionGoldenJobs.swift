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
    /// Run a golden job against the REAL toolpath engines (SPK-0808 — the
    /// legacy `Double.random` stub did not close this card).
    ///
    /// Semantics: computes a real Profile toolpath on a FIXED 50×50mm
    /// calibration fixture (independent of the expectations — so a wrong
    /// expectation genuinely fails), then measures the actual G-code:
    ///   - "width"  — X extent of cut moves (on-cut profile follows the
    ///                vector, so the nominal span equals the fixture width).
    ///   - "depth"  — Y extent of cut moves.
    ///   - "gcodeLines" — actual G-code line count.
    /// Each expected dimension must land within `tolerance` mm (or count
    /// tolerance for line counts) or the run FAILS with the deviation.
    /// Duration is measured, not random.
    public func runJob(_ config: ProductionGoldenJobConfig) -> ProductionGoldenJobResult {
        let started = Date()
        let width = 50.0
        let depth = 50.0
        let expectedLines = config.expectedDimensions["gcodeLines"]

        // Real engine run: Profile on the fixed closed-square calibration
        // fixture (on-cut → cut span equals the fixture dimensions).
        let rect = VectorPath(
            points: [
                VectorPoint(x: 0, y: 0), VectorPoint(x: width, y: 0),
                VectorPoint(x: width, y: depth), VectorPoint(x: 0, y: depth),
                VectorPoint(x: 0, y: 0),
            ],
            isClosed: true
        )
        var params = ProfileToolpathParams()
        params.cutMode = .onCut
        params.toolDiameterMm = 6.0
        params.feedRateMmPerMin = 1500
        let engineResult = ProfileToolpathEngine.compute(
            vectors: [rect], params: params, material: nil, stockHeightMm: 12.0
        )
        let gcode = engineResult.gcodeLines
        let lineCount = gcode.count
        let duration = Date().timeIntervalSince(started) / 60.0

        // Measure actual X/Y extents of CUT moves (G1) from the real output.
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for line in gcode where line.hasPrefix("G1") {
            var x: Double? = nil
            var y: Double? = nil
            for token in line.split(whereSeparator: { $0 == " " }) {
                let word = String(token)
                if word.hasPrefix("X"), let v = Double(word.dropFirst()) { x = v }
                else if word.hasPrefix("Y"), let v = Double(word.dropFirst()) { y = v }
            }
            if let x { minX = min(minX, x); maxX = max(maxX, x) }
            if let y { minY = min(minY, y); maxY = max(maxY, y) }
        }
        let measuredWidth = maxX - minX
        let measuredDepth = maxY - minY

        var actual: [String: Double] = [:]
        var deviations: [String: Double] = [:]
        var errors: [String] = []
        var warnings: [String] = []

        // Width check: the config's expected width is compared against the
        // MEASURED cut span of the fixed 50×50 fixture. A config expecting
        // 50mm passes; expecting anything else fails with the deviation.
        let expectedSpanW = config.expectedDimensions["width"] ?? width
        let wDev = abs(measuredWidth - expectedSpanW)
        actual["width"] = measuredWidth
        deviations["width"] = wDev
        if wDev > config.tolerance {
            errors.append("width: measured \(String(format: "%.2f", measuredWidth))mm, expected \(String(format: "%.2f", expectedSpanW))mm ± \(config.tolerance)mm")
        }

        let expectedSpanD = config.expectedDimensions["depth"] ?? depth
        let dDev = abs(measuredDepth - expectedSpanD)
        actual["depth"] = measuredDepth
        deviations["depth"] = dDev
        if dDev > config.tolerance {
            errors.append("depth: measured \(String(format: "%.2f", measuredDepth))mm, expected \(String(format: "%.2f", expectedSpanD))mm ± \(config.tolerance)mm")
        }

        if let expectedLines {
            actual["gcodeLines"] = Double(lineCount)
            let lineDev = abs(Double(lineCount) - expectedLines)
            deviations["gcodeLines"] = lineDev
            if lineDev > max(config.tolerance, 1.0) {
                errors.append("gcodeLines: engine emitted \(lineCount), expected \(Int(expectedLines))")
            }
        }

        if lineCount == 0 {
            errors.append("engine produced no G-code")
        }
        if duration > config.maxTimeMinutes {
            warnings.append("run took \(String(format: "%.1f", duration))min over \(config.maxTimeMinutes)min budget")
        }

        let status: GoldenJobStatus = errors.isEmpty ? (warnings.isEmpty ? .passed : .warning) : .failed
        let result = ProductionGoldenJobResult(
            status: status,
            durationMinutes: duration,
            actualDimensions: actual,
            deviations: deviations,
            errors: errors,
            warnings: warnings,
            notes: errors.isEmpty
                ? "Golden job passed — \(lineCount) G-code lines, \(String(format: "%.2f", measuredWidth))×\(String(format: "%.2f", measuredDepth))mm cut span"
                : "Golden job failed — \(errors.joined(separator: "; "))"
        )

        // Update job state.
        var updatedConfig = config
        updatedConfig.status = status
        if status == .passed {
            updatedConfig.passCount += 1
        } else if status == .failed {
            updatedConfig.failCount += 1
        } else {
            updatedConfig.warningCount += 1
        }
        updatedConfig.lastRunDate = result.runDate
        updatedConfig.results.append(result)

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
