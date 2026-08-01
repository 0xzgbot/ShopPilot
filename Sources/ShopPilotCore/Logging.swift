import Foundation

/// Logging level enum.
///
/// `Log.targetLevel` controls the minimum severity that actually prints.
public enum LogLevel: String, CaseIterable {
    case debug
    case info
    case warning
    case error
}

/// Lightweight structured logger for ShopPilot.
///
/// Usage:
/// ```swift
/// Log.info("Connected to port \(port)")
/// Log.error("Failed to open transport: \(error)")
/// ```
public struct Log {

    // MARK: - Static configuration

    /// Minimum log level to emit. Messages below this level are silently dropped.
    public static var targetLevel: LogLevel = .info

    /// Whether to include a `[HH:MM:SS]` timestamp in each message.
    public static var enableTimestamps: Bool = true

    // MARK: - Public API

    public static func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        emit(level: .debug, message, file: file, function: function, line: line)
    }

    public static func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        emit(level: .info, message, file: file, function: function, line: line)
    }

    public static func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        emit(level: .warning, message, file: file, function: function, line: line)
    }

    public static func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        emit(level: .error, message, file: file, function: function, line: line)
    }

    // MARK: - Internal

    private static func emit(
        level: LogLevel,
        _ message: String,
        file: String,
        function: String,
        line: Int
    ) {
        // Respect target level: only emit if level >= targetLevel
        guard level.rawValue >= Log.targetLevel.rawValue else { return }

        var output = ""

        // Level tag
        output += "[\(level.rawValue.uppercased())] "

        // Timestamp
        if Log.enableTimestamps {
            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            output += "[\(formatter.string(from: now))] "
        }

        // Source location (strip the project root for readability)
        let fileName = (file as NSString).lastPathComponent
        output += "[\(fileName):\(line)] "

        // Message
        output += message

        print(output)
    }
}
