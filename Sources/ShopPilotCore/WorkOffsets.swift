import Foundation

// MARK: - Work offsets registry (SPK-1304)

/// A single work offset (G54…G59): the fixture name, the G-code selector,
/// and the X/Y/Z coordinate values in machine units.
public struct WorkOffset: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var gcode: String
    public var x: Double
    public var y: Double
    public var z: Double

    public init(id: UUID = UUID(), name: String, gcode: String, x: Double = 0, y: Double = 0, z: Double = 0) {
        self.id = id
        self.name = name
        self.gcode = gcode
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Registry of the six standard work offsets (G54…G59), plus the active
/// selection. Pure model + Codable so it can be persisted with the machine
/// profile; the offset list always holds exactly 6 entries.
public final class WorkOffsetRegistry: Codable, ObservableObject, @unchecked Sendable {

    /// Number of standard work offsets (G54…G59).
    public static let count = 6

    @Published public private(set) var offsets: [WorkOffset]
    @Published public private(set) var activeIndex: Int

    /// Seeds 6 offsets: names "Fixture 1"…"Fixture 6", gcodes "G54"…"G59",
    /// active index 0 (G54).
    public init() {
        var seeded: [WorkOffset] = []
        for i in 0..<Self.count {
            seeded.append(WorkOffset(
                name: "Fixture \(i + 1)",
                gcode: "G\(54 + i)"
            ))
        }
        self.offsets = seeded
        self.activeIndex = 0
    }

    /// The offset currently selected for the machine.
    public var active: WorkOffset { offsets[activeIndex] }

    /// G-code of the active offset, e.g. "G54".
    public var activeGcode: String { active.gcode }

    /// Select the active offset. Returns false (and leaves the selection
    /// unchanged) when `index` is outside 0..<6.
    @discardableResult
    public func setActive(_ index: Int) -> Bool {
        guard offsets.indices.contains(index) else { return false }
        activeIndex = index
        return true
    }

    /// Mutate the offset at `index`. Nil parameters are left untouched.
    /// Returns false (no-op) when `index` is outside 0..<6.
    @discardableResult
    public func update(name: String? = nil, x: Double? = nil, y: Double? = nil, z: Double? = nil, at index: Int) -> Bool {
        guard offsets.indices.contains(index) else { return false }
        var offset = offsets[index]
        if let name { offset.name = name }
        if let x { offset.x = x }
        if let y { offset.y = y }
        if let z { offset.z = z }
        offsets[index] = offset
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case offsets, activeIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.offsets = try c.decode([WorkOffset].self, forKey: .offsets)
        self.activeIndex = try c.decodeIfPresent(Int.self, forKey: .activeIndex) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(offsets, forKey: .offsets)
        try c.encode(activeIndex, forKey: .activeIndex)
    }
}
