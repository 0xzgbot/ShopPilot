import Foundation

// MARK: - Thread Milling (SPK-0902)

/// Parameters for thread milling: cut a thread inside (or outside) a hole
/// with a single helical pass per tooth — the tool climbs the pitch over one
/// revolution, so the G-code is a G2/G3 helix.
public struct ThreadMillParams: Codable, Sendable {
    /// Hole (minor) diameter in mm — the thread's root for internal threads.
    public var holeDiameterMm: Double
    /// Thread pitch in mm (lead per revolution).
    public var pitchMm: Double
    /// Thread length in mm (how deep the thread runs).
    public var threadLengthMm: Double
    /// Internal (default) or external thread milling.
    public var isInternal: Bool
    /// Tool diameter in mm.
    public var toolDiameterMm: Double
    /// Feed rate for the helical pass.
    public var feedRateMmPerMin: Double
    /// Plunge rate for the initial plunge.
    public var plungeRateMmPerMin: Double
    /// Safe Z height.
    public var safeZHeightMm: Double
    /// Spindle RPM (emits M3 S when > 0).
    public var spindleRpm: Double
    /// Start depth (0 = top of stock).
    public var startDepthMm: Double
    /// Number of threading passes (default 1 = single climb pass).
    public var passes: Int
    /// Radial clearance step (mm) for multiple passes (rough → finish).
    public var passStepMm: Double

    public init(
        holeDiameterMm: Double = 8.0,
        pitchMm: Double = 1.25,
        threadLengthMm: Double = 12.0,
        isInternal: Bool = true,
        toolDiameterMm: Double = 4.0,
        feedRateMmPerMin: Double = 400,
        plungeRateMmPerMin: Double = 200,
        safeZHeightMm: Double = 5.0,
        spindleRpm: Double = 0,
        startDepthMm: Double = 0.0,
        passes: Int = 1,
        passStepMm: Double = 0.2
    ) {
        self.holeDiameterMm = max(0.5, holeDiameterMm)
        self.pitchMm = max(0.05, pitchMm)
        self.threadLengthMm = max(0.1, threadLengthMm)
        self.isInternal = isInternal
        self.toolDiameterMm = max(0.1, toolDiameterMm)
        self.feedRateMmPerMin = max(1, feedRateMmPerMin)
        self.plungeRateMmPerMin = max(1, plungeRateMmPerMin)
        self.safeZHeightMm = safeZHeightMm
        self.spindleRpm = max(0, spindleRpm)
        self.startDepthMm = startDepthMm
        self.passes = max(1, passes)
        self.passStepMm = max(0, passStepMm)
    }
}

/// Result of a thread milling operation.
public struct ThreadMillResult: Codable, Sendable {
    public let gcodeLines: [String]
    public let estimatedTimeSeconds: Double
    public let helixCount: Int          // number of helical passes emitted
    public let threadPitchMm: Double

    public init(gcodeLines: [String], estimatedTimeSeconds: Double, helixCount: Int, threadPitchMm: Double) {
        self.gcodeLines = gcodeLines
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.helixCount = helixCount
        self.threadPitchMm = threadPitchMm
    }
}

/// Real thread-milling engine (SPK-0902): a thread is one helical climb of
/// `pitch` mm per revolution. The tool spirals from the top of the thread to
/// its full length using G2/G3 arcs with a Z feed per revolution, so the
/// cutter's pitch exactly matches the requested thread pitch.
public enum ThreadMillingToolpathEngine {

    /// Compute the thread-mill G-code for a hole centered at (centerX, centerY).
    /// The helix radius = (holeØ − toolØ)/2 for internal threads (cutter
    /// orbits inside the hole); for external threads the cutter orbits
    /// outside: radius = (holeØ + toolØ)/2.
    public static func compute(
        centerX: Double = 0,
        centerY: Double = 0,
        params: ThreadMillParams
    ) -> ThreadMillResult {
        var gcode: [String] = ["%", "O=THREAD_MILL_TOOLPATH"]
        gcode.append("(Thread Mill: Ø\(String(format: "%.2f", params.holeDiameterMm))mm hole, M\(String(format: "%.2f", params.pitchMm)) pitch, \(params.isInternal ? "internal" : "external"))")
        if params.spindleRpm > 0 {
            gcode.append("M3 S\(Int(params.spindleRpm))")
        }
        gcode.append("G21 G90")
        gcode.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")

        let helixRadius: Double = params.isInternal
            ? (params.holeDiameterMm - params.toolDiameterMm) / 2
            : (params.holeDiameterMm + params.toolDiameterMm) / 2
        guard helixRadius > 0.05 else {
            return ThreadMillResult(
                gcodeLines: gcode + ["(thread mill: tool does not fit the hole)"],
                estimatedTimeSeconds: 0,
                helixCount: 0,
                threadPitchMm: params.pitchMm
            )
        }

        // The helix: one full revolution advances Z by `pitch` (cutting DOWN
        // into the material). We generate `segments` arc steps per
        // revolution; each step advances −pitch/segments in Z. Arc center is
        // the hole center; radius = helix.
        let segments = 24
        let zPerSegment = params.pitchMm / Double(segments)
        let topZ = -(params.startDepthMm + params.pitchMm) // one pitch above the thread start (ramp-in)
        let bottomZ = -(params.startDepthMm + params.threadLengthMm)
        let helixDepth = params.threadLengthMm
        let revolutions = max(1, helixDepth / params.pitchMm)

        var helixCount = 0
        var totalLength = 0.0
        let cutFeed = params.feedRateMmPerMin
        let plungeFeed = params.plungeRateMmPerMin

        for pass in 0..<params.passes {
            // Each pass moves the cutter radially by passStep (rough → finish).
            let radialStep = Double(pass) * params.passStepMm
            let effectiveRadius = helixRadius + radialStep

            gcode.append("")
            gcode.append("(pass \(pass + 1)/\(params.passes) · radius \(String(format: "%.3f", effectiveRadius))mm)")

            // Rapid to the start point on the circle at safe Z, then plunge.
            let startAngle = -90.0 * .pi / 180.0 // 6 o'clock
            let sx = centerX + cos(startAngle) * effectiveRadius
            let sy = centerY + sin(startAngle) * effectiveRadius
            gcode.append("G0 X\(String(format: "%.3f", sx)) Y\(String(format: "%.3f", sy))")
            gcode.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")
            gcode.append("G1 Z\(String(format: "%.3f", topZ)) F\(String(format: "%.0f", plungeFeed))")

            // Helical climb: G2 arcs (CW when viewed from above; internal
            // threads conventionally climb-cut CW) descending Z per segment.
            var z = topZ
            let totalSegments = Int(ceil(revolutions * Double(segments)))
            for step in 0..<totalSegments {
                let angle0 = startAngle + Double(step) * 2.0 * .pi / Double(segments)
                let angle1 = angle0 + 2.0 * .pi / Double(segments)
                let ex = centerX + cos(angle1) * effectiveRadius
                let ey = centerY + sin(angle1) * effectiveRadius
                z -= zPerSegment
                if z < bottomZ { z = bottomZ }
                gcode.append("G2 X\(String(format: "%.3f", ex)) Y\(String(format: "%.3f", ey)) I\(String(format: "%.3f", -cos(angle0) * effectiveRadius)) J\(String(format: "%.3f", -sin(angle0) * effectiveRadius)) Z\(String(format: "%.3f", z)) F\(String(format: "%.0f", cutFeed))")
                totalLength += 2.0 * .pi * effectiveRadius / Double(segments)
                if z <= bottomZ { break }
            }
            helixCount += 1

            // Retract to safe Z.
            gcode.append("G0 Z\(String(format: "%.3f", params.safeZHeightMm))")
        }

        gcode.append("M2")

        // Time: plunge + helical cut at the cut feed (mm/min).
        let helicalMinutes = totalLength / cutFeed
        let plungeMinutes = (abs(topZ - params.safeZHeightMm) + abs(bottomZ - topZ)) / plungeFeed
        let timeSeconds = (helicalMinutes + plungeMinutes * Double(params.passes)) * 60.0

        return ThreadMillResult(
            gcodeLines: gcode,
            estimatedTimeSeconds: timeSeconds,
            helixCount: helixCount,
            threadPitchMm: params.pitchMm
        )
    }
}
