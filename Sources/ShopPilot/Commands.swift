import Foundation
import ShopPilotCore

// MARK: - Command ID

public enum CommandID: String, CaseIterable {
    case newJob = "new_job"
    case openJob = "open_job"
    case saveJob = "save_job"
    case exportGcode = "export_gcode"
    case importSVG = "import_svg"
    case importSTLRelief = "import_stl_relief"
    
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
        case .importSVG: return "Import SVG…"
        case .importSTLRelief: return "Import STL Relief…"
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
        case .newJob, .openJob, .saveJob, .exportGcode, .importSVG, .importSTLRelief:
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
        case .importSVG: return nil
        case .importSTLRelief: return nil
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

    // MARK: - Backing action (Track 1 exit: "⌘K routes to session actions, not stubs")

    /// Whether selecting this command from the ⌘K palette performs a REAL
    /// session action in `AppSession.handleCommand`.
    ///
    /// Commands with no backing action are filtered out of every palette
    /// listing (`CommandRegistry.flatCommands` / `allCommands` / `search`)
    /// instead of silently no-oping when selected. They remain in the enum
    /// (so tier checks, icon audits and `CommandID.allCases` consumers keep
    /// compiling) and should be re-enabled as soon as a real session action
    /// exists.
    ///
    /// Currently removed from the palette as "coming soon":
    /// - Edit: Cut / Copy / Paste / Delete Vector — no clipboard or shape-delete
    ///   routing in `AppSession.handleCommand` (clipboard ops need the canvas
    ///   selection + pasteboard, which the session does not own yet).
    /// - View: Zoom to Fit / Zoom In / Zoom Out / Reset View — the session has
    ///   no zoom state; canvas zoom lives in `DesignCanvasView` local state.
    /// - Toolpaths: Pocket / V-Carve / 3D Rough / 3D Finish — only Profile has a
    ///   real engine call. `vcCarveTP` currently falls back to profile
    ///   generation, which would silently produce the wrong toolpath, so it is
    ///   hidden until a real V-carve engine routing exists.
    /// - Machine: Disconnect / Jog to Home / Zero All Axes — live-serial ops
    ///   that belong to the Machine stage's connection layer, not the session.
    var isComingSoon: Bool {
        switch self {
        case .newJob, .openJob, .saveJob, .exportGcode, .importSVG, .importSTLRelief,
             .undo, .redo,
             .profileTP,
             .connectMachine, .airCut:
            return false
        default:
            return true
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
    
    /// Commands that actually route to a real session action
    /// (`CommandID.isComingSoon == false`). Every palette listing is built
    /// from this so the ⌘K palette never shows a stub command.
    private static var routableCommands: [CommandID] {
        CommandID.allCases.filter { !$0.isComingSoon }
    }
    
    /// Filter commands available for the given product tier.
    /// Core tier: no 3D toolpath commands. Studio3D: all commands available.
    public static func availableCommands(for tier: ProductTier) -> [CommandID] {
        routableCommands.filter { cmd in
            switch cmd {
            case .rough3DTP, .finish3DTP:
                return tier.has3D
            default:
                return true
            }
        }
    }
    
    /// All available commands, grouped by category.
    public static var allCommands: [CommandCategory: [CommandID]] {
        Dictionary(
            grouping: routableCommands,
            by: { $0.category }
        ).sorted { $0.key.displayOrder < $1.key.displayOrder }.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value
        }
    }
    
    /// Flat list of all commands (for search).
    public static var flatCommands: [(category: CommandCategory, command: CommandID)] {
        CommandCategory.allCases.flatMap { category in
            routableCommands.filter { $0.category == category }.map { (category, $0) }
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
    
    /// Legacy entry point — prefer `AppSession.handleCommand` from the palette.
    public static func perform(_ id: CommandID) {
        NotificationCenter.default.post(name: .shopPilotCommand, object: nil, userInfo: ["id": id.rawValue])
    }
}

extension Notification.Name {
    static let shopPilotCommand = Notification.Name("shopPilotCommand")
}
