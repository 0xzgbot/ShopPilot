import Foundation

// MARK: - Sculpt Mode v1

// Sculpt tool type.
public enum SculptTool: String, Codable, Sendable {
    case brush
    case pinch
    case smooth
    case inflate
    case deflate
    case grab
    case flatten
}

// Sculpt brush shape.
public enum BrushShape: String, Codable, Sendable {
    case sphere
    case cylinder
    case flat
    case custom
}

// Sculpt brush falloff.
public enum BrushFalloff: String, Codable, Sendable {
    case linear
    case smooth
    case constant
    case root
}

// Sculpt mode parameters.
public struct SculptParams: Codable, Sendable {
    public var tool: SculptTool
    public var brushSize: Double
    public var brushStrength: Double
    public var brushShape: BrushShape
    public var brushFalloff: BrushFalloff
    public var autoSmooth: Bool
    public var preserveVolume: Bool
    public var minResolution: Int
    
    public init(
        tool: SculptTool = .brush,
        brushSize: Double = 20.0,
        brushStrength: Double = 0.5,
        brushShape: BrushShape = .sphere,
        brushFalloff: BrushFalloff = .smooth,
        autoSmooth: Bool = false,
        preserveVolume: Bool = false,
        minResolution: Int = 32
    ) {
        self.tool = tool
        self.brushSize = max(1.0, brushSize)
        self.brushStrength = max(0.0, min(1.0, brushStrength))
        self.brushShape = brushShape
        self.brushFalloff = brushFalloff
        self.autoSmooth = autoSmooth
        self.preserveVolume = preserveVolume
        self.minResolution = max(8, min(1024, minResolution))
    }
}

// Sculpt history entry.
public struct SculptHistoryEntry: Codable, Sendable {
    public var id: UUID
    public var tool: SculptTool
    public var timestamp: Date
    public var description: String
    public var undoable: Bool
    
    public init(
        id: UUID = UUID(),
        tool: SculptTool,
        timestamp: Date = Date(),
        description: String,
        undoable: Bool = true
    ) {
        self.id = id
        self.tool = tool
        self.timestamp = timestamp
        self.description = description
        self.undoable = undoable
    }
}

// Sculpt state.
public struct SculptState: Codable, Sendable {
    public var componentID: UUID
    public var params: SculptParams
    public var history: [SculptHistoryEntry]
    public var isDirty: Bool
    public var lastModified: Date
    
    public init(
        componentID: UUID,
        params: SculptParams,
        history: [SculptHistoryEntry] = [],
        isDirty: Bool = false,
        lastModified: Date = Date()
    ) {
        self.componentID = componentID
        self.params = params
        self.history = history
        self.isDirty = isDirty
        self.lastModified = lastModified
    }
}

// MARK: - SculptModeManager

// Manages sculpt mode state and operations.
public final class SculptModeManager: ObservableObject {
    @Published public var states: [UUID: SculptState]
    @Published public var activeComponentID: UUID?
    @Published public var undoStack: [SculptHistoryEntry]
    @Published public var redoStack: [SculptHistoryEntry]
    
    public init() {
        self.states = [:]
        self.activeComponentID = nil
        self.undoStack = []
        self.redoStack = []
    }
    
    // Creates a new sculpt state for a component.
    @discardableResult
    public func createState(
        componentID: UUID,
        params: SculptParams = SculptParams()
    ) -> SculptState {
        let state = SculptState(componentID: componentID, params: params)
        states[componentID] = state
        activeComponentID = componentID
        return state
    }
    
    // Gets the active sculpt state.
    public func getActiveState() -> SculptState? {
        guard let id = activeComponentID else { return nil }
        return states[id]
    }
    
    // Gets the sculpt state for a component.
    public func getState(for componentID: UUID) -> SculptState? {
        states[componentID]
    }
    
    // Removes the sculpt state for a component.
    public func removeState(for componentID: UUID) {
        states.removeValue(forKey: componentID)
        if activeComponentID == componentID {
            activeComponentID = states.first?.key
        }
    }
    
    // Applies a sculpt operation.
    public func applySculpt(
        tool: SculptTool,
        description: String,
        componentID: UUID? = nil
    ) {
        let targetID = componentID ?? activeComponentID
        guard let id = targetID, var state = states[id] else { return }
        
        state.params.tool = tool
        state.isDirty = true
        state.lastModified = Date()
        
        let entry = SculptHistoryEntry(tool: tool, description: description)
        state.history.append(entry)
        undoStack.append(entry)
        redoStack.removeAll()
        
        states[id] = state
    }
    
    // Updates sculpt parameters.
    public func updateParams(
        brushSize: Double? = nil,
        brushStrength: Double? = nil,
        tool: SculptTool? = nil,
        componentID: UUID? = nil
    ) {
        let targetID = componentID ?? activeComponentID
        guard let id = targetID, var state = states[id] else { return }
        
        if let brushSize = brushSize {
            state.params.brushSize = max(1.0, brushSize)
        }
        if let brushStrength = brushStrength {
            state.params.brushStrength = max(0.0, min(1.0, brushStrength))
        }
        if let tool = tool {
            state.params.tool = tool
        }
        
        state.isDirty = true
        state.lastModified = Date()
        states[id] = state
    }
    
    // Undoes the last sculpt operation.
    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(last)
        
        if let id = activeComponentID, var state = states[id] {
            if state.history.count > 0 {
                state.history.removeLast()
                state.isDirty = true
                state.lastModified = Date()
                states[id] = state
            }
        }
    }
    
    // Redoes the last undone operation.
    public func redo() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(last)
        
        if let id = activeComponentID, var state = states[id] {
            state.history.append(last)
            state.isDirty = true
            state.lastModified = Date()
            states[id] = state
        }
    }
    
    // Clears all sculpt history.
    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        
        if let id = activeComponentID, var state = states[id] {
            state.history.removeAll()
            state.isDirty = false
            states[id] = state
        }
    }
    
    // Marks component as clean.
    public func markClean(componentID: UUID) {
        guard var state = states[componentID] else { return }
        state.isDirty = false
        states[componentID] = state
    }
    
    // Checks if component is dirty.
    public func isDirty(componentID: UUID) -> Bool {
        states[componentID]?.isDirty ?? false
    }
    
    // Gets all component IDs with sculpt states.
    public func componentIDs() -> [UUID] {
        Array(states.keys)
    }
}
