import Foundation

// MARK: - Merged Toolpath

/// A toolpath created by merging multiple source toolpaths into one.
public struct MergedToolpath: Codable, Sendable {

    public let id: UUID
    public var name: String
    public var sourceToolpathIDs: [UUID]
    public var toolID: UUID?
    public var feedRate: Double
    public var spindleSpeed: Double
    public var cutDepth: Double
    public var safeZ: Double
    public var orderStrategy: MergeOrderStrategy
    public var completed: Bool
    public var generatedPaths: [GeneratedPath]

    public init(
        id: UUID = UUID(),
        name: String,
        sourceToolpathIDs: [UUID] = [],
        toolID: UUID? = nil,
        feedRate: Double = 1000,
        spindleSpeed: Double = 12000,
        cutDepth: Double = 1.0,
        safeZ: Double = 5.0,
        orderStrategy: MergeOrderStrategy = .selectionOrder,
        completed: Bool = false,
        generatedPaths: [GeneratedPath] = []
    ) {
        self.id = id
        self.name = name
        self.sourceToolpathIDs = sourceToolpathIDs
        self.toolID = toolID
        self.feedRate = feedRate
        self.spindleSpeed = spindleSpeed
        self.cutDepth = cutDepth
        self.safeZ = safeZ
        self.orderStrategy = orderStrategy
        self.completed = completed
        self.generatedPaths = generatedPaths
    }
}

// MARK: - Merge Order Strategy

/// Strategy for ordering toolpaths when merging.
public enum MergeOrderStrategy: String, Codable, Sendable {

    case selectionOrder
    case leftToRight
    case bottomToTop
    case grid
    case shortestPath

    public var displayName: String {
        switch self {
        case .selectionOrder: return "Selection Order"
        case .leftToRight: return "Left to Right"
        case .bottomToTop: return "Bottom to Top"
        case .grid: return "Grid"
        case .shortestPath: return "Shortest Path"
        }
    }
}

// MARK: - Preview (Xcode only)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct MergedToolpath_Previews: PreviewProvider {
    static var previews: some View {
        Text("Merged toolpath is a non-visual component")
    }
}
#endif
