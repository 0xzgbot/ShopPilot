import Foundation

// MARK: - Component

/// A 3D component in the ShopPilot component tree.
/// Represents a single sculpted or shaped element that can be combined,
/// transformed, and assigned to levels for toolpath generation.
public struct Component: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var parent: UUID?
    public var children: [UUID]
    public var visible: Bool
    public var locked: Bool
    public var opacity: Double
    public var color: String  // hex string, e.g. "FF5733"

    public init(
        id: UUID = UUID(),
        name: String = "Component",
        parent: UUID? = nil,
        children: [UUID] = [],
        visible: Bool = true,
        locked: Bool = false,
        opacity: Double = 1.0,
        color: String = "FFFFFF"
    ) {
        self.id = id
        self.name = name
        self.parent = parent
        self.children = children
        self.visible = visible
        self.locked = locked
        self.opacity = max(0.0, min(1.0, opacity))
        self.color = color
    }
}

// MARK: - Level

/// A level (layer) in the component tree.
/// Components are assigned to levels for compositing, visibility control,
/// and blend-mode rendering before toolpath generation.
public struct Level: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var components: [UUID]
    public var visible: Bool
    public var locked: Bool
    public var opacity: Double
    public var blendMode: String  // "normal", "multiply", "screen", etc.

    public init(
        id: UUID = UUID(),
        name: String = "Level",
        components: [UUID] = [],
        visible: Bool = true,
        locked: Bool = false,
        opacity: Double = 1.0,
        blendMode: String = "normal"
    ) {
        self.id = id
        self.name = name
        self.components = components
        self.visible = visible
        self.locked = locked
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
    }
}

// MARK: - ComponentTree

/// Manages the relationship between components and levels.
/// Provides CRUD, hierarchy navigation, and ordering operations.
public final class ComponentTree: Sendable {
    private var components: [UUID: Component]
    private var levels: [UUID: Level]
    private var rootComponents: [UUID]

    public init() {
        self.components = [:]
        self.levels = [:]
        self.rootComponents = []
    }

    // MARK: - Component CRUD

    /// Creates a new component and optionally attaches it under a parent.
    /// - Parameter name: Display name for the component.
    /// - Parameter parent: Parent component ID; nil means top-level (root).
    /// - Returns: The new component's UUID.
    @discardableResult
    public func addComponent(_ name: String, parent: UUID? = nil) -> UUID {
        let id = UUID()
        let comp = Component(id: id, name: name, parent: parent)

        components[id] = comp

        if let parentID = parent {
            // Ensure parent exists and add child reference
            if var parentComp = components[parentID] {
                parentComp.children.append(id)
                components[parentID] = parentComp
            }
        } else {
            rootComponents.append(id)
        }

        return id
    }

    /// Adds an existing component to a level.
    /// - Parameters:
    ///   - componentID: The component to add.
    ///   - levelID: The level to add it to.
    public func addComponentToLevel(_ componentID: UUID, levelID: UUID) {
        guard components[componentID] != nil else { return }
        guard var level = levels[levelID] else { return }
        if !level.components.contains(componentID) {
            level.components.append(componentID)
            levels[levelID] = level
        }
    }

    /// Removes a component and all of its descendants from the tree.
    /// - Parameter id: The component to remove.
    public func removeComponent(_ id: UUID) {
        guard let comp = components[id] else { return }

        // Collect all descendant IDs for removal
        let descendants = collectDescendants(of: id)
        var allToRemove: Set<UUID> = [id]
        allToRemove.formUnion(descendants)

        // Remove from parent's children list
        if let parentID = comp.parent {
            if var parentComp = components[parentID] {
                parentComp.children.removeAll { allToRemove.contains($0) }
                components[parentID] = parentComp
            }
        } else {
            rootComponents.removeAll { allToRemove.contains($0) }
        }

        // Remove from any levels
        for (levelID, var level) in levels {
            level.components.removeAll { allToRemove.contains($0) }
            levels[levelID] = level
        }

        // Remove component and all descendants
        for uid in allToRemove {
            components.removeValue(forKey: uid)
        }
    }

    /// Looks up a component by ID.
    /// - Parameter id: The component UUID.
    /// - Returns: The component, or nil if not found.
    public func getComponent(_ id: UUID) -> Component? {
        components[id]
    }

    /// Looks up a level by ID.
    /// - Parameter id: The level UUID.
    /// - Returns: The level, or nil if not found.
    public func getLevel(_ id: UUID) -> Level? {
        levels[id]
    }

    /// Moves a component up in its parent's children list (or root list).
    /// No-op if component is already first or has no parent.
    /// - Parameter id: The component UUID.
    public func moveComponentUp(_ id: UUID) {
        guard let idx = siblingIndex(of: id) else { return }
        guard idx > 0 else { return }

        let parentID = components[id]?.parent
        if let parentID = parentID {
            if var parentComp = components[parentID] {
                parentComp.children.swapAt(idx, idx - 1)
                components[parentID] = parentComp
            }
        } else {
            rootComponents.swapAt(idx, idx - 1)
        }
    }

    /// Moves a component down in its parent's children list (or root list).
    /// No-op if component is already last or has no parent.
    /// - Parameter id: The component UUID.
    public func moveComponentDown(_ id: UUID) {
        guard let idx = siblingIndex(of: id) else { return }

        let parentID = components[id]?.parent
        if let parentID = parentID {
            if var parentComp = components[parentID] {
                let maxIdx = parentComp.children.count - 1
                guard idx < maxIdx else { return }
                parentComp.children.swapAt(idx, idx + 1)
                components[parentID] = parentComp
            }
        } else {
            let maxIdx = rootComponents.count - 1
            guard idx < maxIdx else { return }
            rootComponents.swapAt(idx, idx + 1)
        }
    }

    // MARK: - Helpers

    /// Returns the index of a component among its siblings (children of its parent).
    /// - Parameter id: The component UUID.
    /// - Returns: The sibling index, or nil if not found.
    private func siblingIndex(of id: UUID) -> Int? {
        let parentID = components[id]?.parent
        if let parentID = parentID {
            return components[parentID]?.children.firstIndex(of: id)
        }
        return rootComponents.firstIndex(of: id)
    }

    /// Recursively collects all descendant IDs of a component.
    /// - Parameter id: The ancestor component UUID.
    /// - Returns: Set of all descendant UUIDs.
    private func collectDescendants(of id: UUID) -> Set<UUID> {
        guard let comp = components[id] else { return [] }
        var result: Set<UUID> = Set(comp.children)
        for childID in comp.children {
            result.formUnion(collectDescendants(of: childID))
        }
        return result
    }
}


