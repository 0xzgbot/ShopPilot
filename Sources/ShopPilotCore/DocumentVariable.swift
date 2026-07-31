import Foundation

// MARK: - Document Variable

/// A user-defined key-value pair attached to a ShopPilot document.
/// Examples: material, stock size, project name, toolpath template.
public struct DocumentVariable: Identifiable, Codable, Hashable {
    public let id: UUID
    public var key: String
    public var value: String
    public var category: String
    
    /// Default category used when none is specified.
    public static let defaultCategory = "General"
    
    public init(id: UUID = UUID(), key: String, value: String, category: String = DocumentVariable.defaultCategory) {
        self.id = id
        self.key = key
        self.value = value
        self.category = category
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: DocumentVariable, rhs: DocumentVariable) -> Bool {
        lhs.id == rhs.id
    }
}
