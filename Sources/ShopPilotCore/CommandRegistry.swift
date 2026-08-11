import Foundation

// MARK: - Command context registry (SPK-1204)

/// One source of truth for context-menu actions and their enabled state.
/// Toolbars and right-click menus share the same registry, so an action can
/// never be enabled in one place and disabled in the other (the classic
/// "the menu says I can, the button says I can't" mismatch).
public struct CommandAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// Enabled predicate evaluated against the context value.
    public let isEnabled: (CommandContextValue) -> Bool
    public let destructive: Bool

    public init(id: String, title: String, systemImage: String,
                destructive: Bool = false,
                isEnabled: @escaping (CommandContextValue) -> Bool = { _ in true }) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.destructive = destructive
    }
}

/// Context values the menus evaluate against (tagged unions — the registry
/// keys its predicates on the node kind so toolpath vs layer vs sheet menus
/// never cross-contaminate).
public enum CommandContextValue {
    case toolpathNode(id: UUID, isDirty: Bool, toolID: UUID?)
    case layer(id: UUID, visible: Bool, locked: Bool, componentCount: Int)
    case sheet(id: UUID, isActive: Bool)
    case canvas(hasSelection: Bool, hasVectors: Bool)
    case none
}

/// Registry: action catalog + lookup + enabled evaluation. Pure — CLT-verifiable.
public struct CommandRegistry: Sendable {

    /// The catalog. Keyed by a logical group so UI can render menus from it.
    public private(set) var actions: [String: [CommandAction]]

    public init(actions: [String: [CommandAction]] = [:]) {
        self.actions = actions
    }

    /// Actions for a group (e.g. "toolpath", "layer", "sheet", "canvas").
    public func actions(forGroup group: String) -> [CommandAction] {
        actions[group] ?? []
    }

    /// Resolve an action by id across all groups.
    public func action(id: String) -> CommandAction? {
        for list in actions.values {
            if let match = list.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    /// Enabled actions for a group given a context value.
    public func enabledActions(forGroup group: String, context: CommandContextValue) -> [CommandAction] {
        actions(forGroup: group).filter { $0.isEnabled(context) }
    }
}

/// The app's standard registry — the canonical catalog the UI builds its
/// right-click menus from (SPK-1204).
public enum AppCommandRegistry {
    public static func make() -> CommandRegistry {
        CommandRegistry(actions: [
            "toolpath": [
                CommandAction(id: "tp.recalc", title: "Recalculate", systemImage: "arrow.clockwise",
                              isEnabled: { ctx in
                                  if case .toolpathNode(_, let isDirty, _) = ctx { return isDirty }
                                  return false
                              }),
                CommandAction(id: "tp.selectSources", title: "Select Source Vectors", systemImage: "cursorarrow.click"),
                CommandAction(id: "tp.duplicate", title: "Duplicate", systemImage: "plus.square.on.square"),
                CommandAction(id: "tp.delete", title: "Delete", systemImage: "trash", destructive: true),
            ],
            "layer": [
                CommandAction(id: "layer.duplicate", title: "Duplicate Layer", systemImage: "plus.square.on.square"),
                CommandAction(id: "layer.hideEmpty", title: "Hide Empty Layers", systemImage: "eye.slash"),
                CommandAction(id: "layer.delete", title: "Delete Layer", systemImage: "trash", destructive: true,
                              isEnabled: { ctx in
                                  if case .layer(_, _, _, let count) = ctx { return count == 0 }
                                  return false
                              }),
            ],
            "sheet": [
                CommandAction(id: "sheet.duplicate", title: "Duplicate Sheet", systemImage: "doc.on.doc"),
                CommandAction(id: "sheet.activate", title: "Make Active", systemImage: "checkmark.circle",
                              isEnabled: { ctx in
                                  if case .sheet(_, let isActive) = ctx { return !isActive }
                                  return false
                              }),
            ],
            "canvas": [
                CommandAction(id: "cv.paste", title: "Paste", systemImage: "doc.on.clipboard"),
                CommandAction(id: "cv.selectAll", title: "Select All", systemImage: "selection.pin.in.out",
                              isEnabled: { ctx in
                                  if case .canvas(_, let hasVectors) = ctx { return hasVectors }
                                  return false
                              }),
            ],
        ])
    }
}
