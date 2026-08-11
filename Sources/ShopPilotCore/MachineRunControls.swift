import Foundation

/// SPK-1302: Feed-rate override + spindle command models (pure string/math, no I/O).
/// The app wires these into the G-code streamer later; this file stays I/O-free so
/// the machine-control math is unit-verifiable without a serial port.
public struct FeedRateOverride: Equatable, Sendable {
    /// Override multiplier, clamped to [0.1, 2.0] (10%..200%).
    public var multiplier: Double

    /// Creates an override; clamps `multiplier` to [0.1, 2.0].
    public init(multiplier: Double = 1.0) {
        self.multiplier = min(2.0, max(0.1, multiplier))
    }

    /// Feed scaled by the override, never below 1.
    public func scaled(_ feed: Double) -> Double {
        max(1.0, feed * multiplier)
    }

    /// GRBL feed-override G-code: send a new F word (rounded, integer).
    /// Example: multiplier 1.25 over feed 400 → "F500".
    public func gcode(feed: Double) -> String {
        "F\(Int(scaled(feed).rounded()))"
    }
}

/// SPK-1302: Spindle M-code commands (GRBL dialect).
public enum SpindleCommand {
    /// Spindle on at `rpm` — "M3 S<rpm>" with rpm clamped to 1000...30000 and rounded.
    public static func on(rpm: Double) -> String {
        "M3 S\(Int(validRpm(rpm).rounded()))"
    }

    /// Spindle off — "M5".
    public static func off() -> String {
        "M5"
    }

    /// Set spindle rpm while running — "S<rpm>" with the same clamp + rounding.
    public static func setRpm(_ rpm: Double) -> String {
        "S\(Int(validRpm(rpm).rounded()))"
    }

    /// The clamped, valid rpm in [1000, 30000].
    public static func validRpm(_ rpm: Double) -> Double {
        min(30000.0, max(1000.0, rpm))
    }
}
