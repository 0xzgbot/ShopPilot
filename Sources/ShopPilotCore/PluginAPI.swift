import Foundation

// MARK: - Plugin ABI (SPK-1006 → loadable)

/// Plugin kinds a manifest can declare.
public enum PluginKind: String, Codable, Sendable {
    case toolpathStrategy = "toolpath-strategy"
    case importer
    case postTemplate = "post-template"
    case gadget
}

/// A declared parameter for a plugin (rendered generically in the UI).
public struct PluginParamDecl: Codable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let type: String       // "number" | "string" | "bool"
    public let defaultValue: String

    public init(key: String, type: String, defaultValue: String) {
        self.key = key
        self.type = type
        self.defaultValue = defaultValue
    }
}

/// A plugin manifest (`manifest.json` in a plugin directory). The ABI
/// contract from the SPK-1006 draft:
///   - apiVersion: 1
///   - id/name/kind/entry required; capabilities + params optional.
public struct PluginManifest: Codable, Sendable, Identifiable {
    public let apiVersion: Int
    public let id: String
    public let name: String
    public let kind: PluginKind
    public let entry: String
    public let capabilities: [String]
    public let params: [PluginParamDecl]

    public init(
        apiVersion: Int = 1,
        id: String,
        name: String,
        kind: PluginKind,
        entry: String,
        capabilities: [String] = [],
        params: [PluginParamDecl] = []
    ) {
        self.apiVersion = apiVersion
        self.id = id
        self.name = name
        self.kind = kind
        self.entry = entry
        self.capabilities = capabilities
        self.params = params
    }

    /// Validate a decoded manifest (the discovery pass). Returns the reason
    /// a plugin is rejected, or nil when it's loadable.
    public var rejectionReason: String? {
        if apiVersion != 1 { return "unsupported apiVersion \(apiVersion)" }
        if id.isEmpty { return "missing id" }
        if name.isEmpty { return "missing name" }
        if entry.isEmpty { return "missing entry" }
        return nil
    }
}

/// The JSON document written to a plugin's stdin. Follows the draft: sheets,
/// vectors (path point arrays), material, tool, and the plugin's params.
public struct PluginJobDocument: Codable, Sendable {
    public var jobName: String
    public var stockWidthMm: Double
    public var stockDepthMm: Double
    public var stockHeightMm: Double
    public var vectors: [PluginVectorPath]
    public var params: [String: String]

    public init(
        jobName: String,
        stockWidthMm: Double,
        stockDepthMm: Double,
        stockHeightMm: Double,
        vectors: [PluginVectorPath],
        params: [String: String]
    ) {
        self.jobName = jobName
        self.stockWidthMm = stockWidthMm
        self.stockDepthMm = stockDepthMm
        self.stockHeightMm = stockHeightMm
        self.vectors = vectors
        self.params = params
    }
}

/// Vector path shape in the plugin document (point list + closure flag).
public struct PluginVectorPath: Codable, Sendable {
    public var points: [PluginVectorPoint]
    public var isClosed: Bool

    public init(points: [PluginVectorPoint], isClosed: Bool) {
        self.points = points
        self.isClosed = isClosed
    }
}

public struct PluginVectorPoint: Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The JSON document a plugin writes to stdout.
public struct PluginOutput: Codable, Sendable {
    public var gcodeLines: [String]
    public var estimatedTimeSeconds: Double
    public var params: [String: String]

    public init(gcodeLines: [String], estimatedTimeSeconds: Double, params: [String: String] = [:]) {
        self.gcodeLines = gcodeLines
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.params = params
    }
}

/// Runs a plugin as a child process with a timeout (the draft's sandbox
/// contract): job JSON on stdin, output JSON on stdout, kill on timeout.
/// Entry resolution: `entry` is relative to the plugin directory; `.swift`
/// runs via `swift` (interpreter), everything else is executed directly
/// (a compiled binary or a script with a shebang).
public enum PluginRunner {

    public static let defaultTimeoutSeconds = 30.0

    public static func run(
        manifest: PluginManifest,
        pluginDirectory: URL,
        document: PluginJobDocument,
        timeoutSeconds: Double = defaultTimeoutSeconds
    ) -> PluginOutput? {
        let entryURL = pluginDirectory.appendingPathComponent(manifest.entry)
        guard FileManager.default.fileExists(atPath: entryURL.path) else { return nil }

        let process = Process()
        process.currentDirectoryURL = pluginDirectory
        if entryURL.pathExtension.lowercased() == "swift" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swift", entryURL.path]
        } else {
            process.executableURL = entryURL
            process.arguments = []
        }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        // Write the job document, then close stdin so the plugin sees EOF.
        if let data = try? JSONEncoder().encode(document) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        // Wait with timeout: terminate + reap a hung plugin.
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return nil
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = try? JSONDecoder().decode(PluginOutput.self, from: outData) else {
            return nil
        }
        return output
    }
}

/// Discovers plugins from directories containing a `manifest.json` (the app
/// plugin dir + any extra search roots for tests). A broken manifest is
/// skipped, never fatal.
public final class PluginStore: ObservableObject {

    @Published public private(set) var plugins: [LoadedPlugin] = []

    public struct LoadedPlugin: Identifiable {
        public let manifest: PluginManifest
        public let directory: URL
        public var id: String { manifest.id }
    }

    public init(searchDirectories: [URL]) {
        reload(searchDirectories: searchDirectories)
    }

    public func reload(searchDirectories: [URL]) {
        var found: [LoadedPlugin] = []
        for dir in searchDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                let manifestURL = entry.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data),
                      manifest.rejectionReason == nil else { continue }
                found.append(LoadedPlugin(manifest: manifest, directory: entry))
            }
        }
        // Deterministic order: by id.
        plugins = found.sorted { $0.manifest.id < $1.manifest.id }
    }

    /// The app's plugin search roots: the Application Support Plugins dir
    /// (created on demand) + bundled fixtures (for the sample plugin).
    public static func appSearchDirectories() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let plugins = support.appendingPathComponent("ShopPilot/Plugins")
            try? fm.createDirectory(at: plugins, withIntermediateDirectories: true)
            dirs.append(plugins)
        }
        if let bundlePlugins = Bundle.main.resourceURL?.appendingPathComponent("Plugins") {
            dirs.append(bundlePlugins)
        }
        return dirs
    }
}
