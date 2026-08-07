import Foundation

// MARK: - Canvas overlay options (UI-polish cluster: visibility chips)

/// Which overlays the Design/Preview canvas renders. Drives the visibility
/// chips row (Vec / Keep-outs / Toolpaths). Persisted in UserDefaults so the
/// choice survives relaunch; the option-set math lives in Core so a CLT can
/// prove the round-trip.
public struct CanvasOverlayOptions: OptionSet, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let vectors     = CanvasOverlayOptions(rawValue: 1 << 0)
    public static let keepOuts    = CanvasOverlayOptions(rawValue: 1 << 1)
    public static let toolpaths   = CanvasOverlayOptions(rawValue: 1 << 2)
    public static let bitmaps     = CanvasOverlayOptions(rawValue: 1 << 3)

    /// Everything on (the default first-run state).
    public static let all: CanvasOverlayOptions = [.vectors, .keepOuts, .toolpaths, .bitmaps]

    /// Chip labels in a stable order (for the UI row).
    public static let chips: [(option: CanvasOverlayOptions, label: String, symbol: String)] = [
        (.vectors, "Vec", "square.on.square"),
        (.keepOuts, "Keep-outs", "hand.raised"),
        (.toolpaths, "Toolpaths", "point.topleft.down.curvedto.point.bottomright.up"),
        (.bitmaps, "Bitmaps", "photo"),
    ]

    /// The option matching a given chip index (stable ordering).
    public static func option(at index: Int) -> CanvasOverlayOptions? {
        guard chips.indices.contains(index) else { return nil }
        return chips[index].option
    }
}

/// UserDefaults-backed persistence for the canvas overlay flags.
public enum CanvasOverlayStore {
    private static let key = "shop_pilot_canvas_overlays"

    public static func load() -> CanvasOverlayOptions {
        let raw = UserDefaults.standard.integer(forKey: key)
        return raw == 0 ? .all : CanvasOverlayOptions(rawValue: raw)
    }

    public static func save(_ options: CanvasOverlayOptions) {
        UserDefaults.standard.set(options.rawValue, forKey: key)
    }
}
