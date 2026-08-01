// MARK: - App-wide constants
public struct AppConstants {

    // MARK: App identity
    public static let appName = "ShopPilot"
    public static let appVersion = "1.0.0"
    public static let documentExtension = ".shoppilot"

    // MARK: Default sheet dimensions
    public static let defaultSheetName = "Sheet 1"
    public static let defaultSheetWidth: Double = 600.0
    public static let defaultSheetDepth: Double = 400.0
    public static let defaultSheetHeight: Double = 25.0

    // MARK: Sheet dimension limits (mm)
    public static let minSheetWidth: Double = 1.0
    public static let maxSheetWidth: Double = 10000.0
    public static let minSheetDepth: Double = 1.0
    public static let maxSheetDepth: Double = 10000.0
    public static let minSheetHeight: Double = 0.1
    public static let maxSheetHeight: Double = 1000.0

    // MARK: Default tool & material names
    public static let defaultToolName = "Tool 1"
    public static let defaultMaterialName = "No Material"

    // MARK: Default machining parameters
    public static let defaultFeedRate: Double = 1000.0
    public static let defaultSpindleSpeed: Double = 12000.0
    public static let safeZHeight: Double = 5.0

    // MARK: Home position
    public static let homePositionX: Double = 0.0
    public static let homePositionY: Double = 0.0

    // MARK: Tab defaults
    public static let defaultTabWidth: Double = 5.0
    public static let defaultTabCount = 4
}
