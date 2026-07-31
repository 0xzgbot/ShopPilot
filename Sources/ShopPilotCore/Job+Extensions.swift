import Foundation

// MARK: - Job Convenience Helpers

extension Job {

    /// Create a new sheet with a default name ("Sheet N") and standard dimensions.
    /// - Parameter name: Optional explicit name. Defaults to "Sheet 1".
    /// - Returns: The newly created Sheet (not yet added to the job).
    public static func makeDefaultSheet(named name: String? = nil) -> Sheet {
        let sheetName = name ?? "Sheet 1"
        return Sheet(
            name: sheetName,
            width: 600,
            depth: 400,
            height: 25
        )
    }

    /// Add a new sheet with default name and dimensions to this job.
    public mutating func addDefaultSheet() {
        let newSheet = Self.makeDefaultSheet()
        addSheet(newSheet)
    }
}
