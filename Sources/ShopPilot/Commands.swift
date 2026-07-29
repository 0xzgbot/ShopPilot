import Foundation

// MARK: - Command ID

public enum CommandID: String, CaseIterable {
    case newJob = "new_job"
    case openJob = "open_job"
    case saveJob = "save_job"
    case exportGcode = "export_gcode"
    
    case undo = "undo"
    case redo = "redo"
    case cut = "cut"
    case copy = "copy"
    case paste = "paste"
    case deleteVector = "delete_vector"
    
    case zoomFit = "zoom_fit"
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case resetView = "reset_view"
    
    case profileTP = "profile_tp"
    case pocketTP = "pocket_tp"
    case drillTP = "drill_tp"
    case vcCarveTP = "vc_carve_tp"
    case rough3DTP = "rough_3d_tp"
    case finish3DTP = "finish_3d_tp"
    
    case connectMachine = "connect_machine"
    case disconnectMachine = "disconnect_machine"
    case jogHome = "jog_home"
    case zeroAxes = "zero_axes"
    case airCut = "air_cut"
    
    var name: String {
        switch self {
        case .newJob: return "New Job"
        case .openJob: return "Open Job…"
        case .saveJob: return "Save Job"
        case .exportGcode: return "Export G-code"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .deleteVector: return "Delete Vector"
        case .zoomFit: return "Zoom to Fit"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .resetView: return "Reset View"
        case .profileTP: return "Profile Toolpath"
        case .pocketTP: return "Pocket Toolpath"
        case .drillTP: return "Drill Toolpath"
        case .vcCarveTP: return "V-Carve Toolpath"
        case .rough3DTP: return "3D Rough Toolpath"
        case .finish3DTP: return "3D Finish Toolpath"
        case .connectMachine: return "Connect Machine"
        case .disconnectMachine: return "Disconnect Machine"
        case .jogHome: return "Jog to Home"
        case .zeroAxes: return "Zero All Axes"
        case .airCut: return "Air Cut (Simulate)"
        }
    }
    
    var category: CommandCategory {
        switch self {
        case .newJob, .openJob, .saveJob, .exportGcode:
            return .file
        case .undo, .redo, .cut, .copy, .paste, .deleteVector:
            return .edit
        case .zoomFit, .zoomIn, .zoomOut, .resetView:
            return .view
        case .profileTP, .pocketTP, .drillTP, .vcCarveTP, .rough3DTP, .finish3DTP:
            return .toolpaths
        case .connectMachine, .disconnectMachine, .jogHome, .zeroAxes, .airCut:
            return .machine
        }
    }
    
    var keyboardShortcut: String? {
        switch self {
        case .newJob: return "n"
        case .openJob: return "o"
        case .saveJob: return "s"
        case .exportGcode: return nil
        case .undo: return "z"
        case .redo: return "shift+z"
        case .cut: return "x"
        case .copy: return "c"
        case .paste: return "v"
        case .deleteVector: return "delete"
        case .zoomFit: return "f"
        case .zoomIn: return "="
        case .zoomOut: return "-"
        case .resetView: return "r"
        case .profileTP, .pocketTP, .drillTP, .vcCarveTP, .rough3DTP, .finish3DTP:
            return nil
        case .connectMachine: return nil
        case .disconnectMachine: return nil
        case .jogHome: return nil
        case .zeroAxes: return nil
        case .airCut: return nil
        }
    }
}

// MARK: - Command Category

public enum CommandCategory: String, CaseIterable {
    case file = "File"
    case edit = "Edit"
    case view = "View"
    case toolpaths = "Toolpaths"
    case machine = "Machine"
    
    var displayOrder: Int {
        switch self {
        case .file: return 0
        case .edit: return 1
        case .view: return 2
        case .toolpaths: return 3
        case .machine: return 4
        }
    }
}

// MARK: - Command Registry

public struct CommandRegistry {
    
    /// All available commands, grouped by category.
    public static var allCommands: [CommandCategory: [CommandID]] {
        Dictionary(
            grouping: CommandID.allCases,
            by: { $0.category }
        ).sorted { $0.key.displayOrder < $1.key.displayOrder }.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value
        }
    }
    
    /// Flat list of all commands (for search).
    public static var flatCommands: [(category: CommandCategory, command: CommandID)] {
        CommandCategory.allCases.flatMap { category in
            CommandID.allCases.filter { $0.category == category }.map { (category, $0) }
        }
    }
    
    /// Search commands by text. Returns matching (category, command) pairs.
    public static func search(_ query: String) -> [(category: CommandCategory, command: CommandID)] {
        let lowerQuery = query.lowercased()
        return flatCommands.filter { _, cmd in
            cmd.name.localizedCaseInsensitiveContains(lowerQuery) ||
            cmd.rawValue.localizedCaseInsensitiveContains(lowerQuery)
        }
    }
    
    /// Execute a command. Stub — delegates to stage-specific handlers.
    public static func perform(_ id: CommandID) {
        print("⌘K Command executed: \(id.name)")
        // TODO: Route to stage-specific handler based on current stage
    }
}
