import Foundation

// MARK: - Sample Project Descriptor

/// A bundled, ready-made project offered by the Welcome sheet's
/// "Open sample" action. Samples are built entirely in code as
/// `ShopPilotPackagePayload` values — the app ships no binary project files.
public struct SampleProject: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tagline: String
    public let category: String

    public init(id: UUID, name: String, tagline: String, category: String) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.category = category
    }
}

// MARK: - Store

/// SPK-1313 — programmatic sample-project store.
///
/// Four ready-made projects (sign, box, keychain, plaque) built on demand as
/// `ShopPilotPackagePayload` values, so the Welcome sheet can offer
/// "Open sample" without shipping binary files.
public enum SampleProjectsStore {
    // Stable hardcoded ids — "Open sample" lookups must be deterministic
    // across launches and repeated calls.
    private static let signID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let boxID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let keychainID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let plaqueID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    /// The four bundled samples, in display order.
    public static var samples: [SampleProject] {
        [
            SampleProject(
                id: signID,
                name: "Sign — V-Carve Greeting",
                tagline: "A classic v-carved welcome sign with a decorative border.",
                category: "Sign"
            ),
            SampleProject(
                id: boxID,
                name: "Box — Finger Joints",
                tagline: "Finger-jointed box with a snug press-fit lid.",
                category: "Box"
            ),
            SampleProject(
                id: keychainID,
                name: "Keychain — Dogbone",
                tagline: "Pocket-sized keychain fob with dogbone-friendly corners.",
                category: "Keychain"
            ),
            SampleProject(
                id: plaqueID,
                name: "Plaque — Text Relief",
                tagline: "A routed text-relief plaque with a decorative border.",
                category: "Plaque"
            ),
        ]
    }

    /// Build the payload for the sample with the given stable id.
    /// Returns nil for unknown ids.
    public static func payload(for id: UUID) -> ShopPilotPackagePayload? {
        switch id {
        case signID: return makeSignPayload()
        case boxID: return makeBoxPayload()
        case keychainID: return makeKeychainPayload()
        case plaqueID: return makePlaquePayload()
        default: return nil
        }
    }

    /// Build the payload for the sample at `index` into `samples`.
    /// Returns nil when the index is out of range.
    public static func payload(for index: Int) -> ShopPilotPackagePayload? {
        guard samples.indices.contains(index) else { return nil }
        return payload(for: samples[index].id)
    }

    // MARK: - Payload construction

    /// Derive a deterministic child id (job/sheet/layer) from a sample id.
    private static func childID(of sampleID: UUID, salt: UInt8) -> UUID {
        var bytes = sampleID.uuid
        bytes.0 = bytes.0 &+ salt
        return UUID(uuid: bytes)
    }

    private static func rectanglePoints(x: Double, y: Double, width: Double, height: Double) -> [VectorPoint] {
        [
            VectorPoint(x: x, y: y),
            VectorPoint(x: x + width, y: y),
            VectorPoint(x: x + width, y: y + height),
            VectorPoint(x: x, y: y + height),
            VectorPoint(x: x, y: y), // closed loop
        ]
    }

    private static func circlePoints(centerX: Double, centerY: Double, radius: Double, segments: Int = 16) -> [VectorPoint] {
        (0..<segments).map { i in
            let angle = Double(i) / Double(segments) * 2 * .pi
            return VectorPoint(x: centerX + radius * cos(angle), y: centerY + radius * sin(angle))
        }
    }

    private static func makePayload(
        sampleID: UUID,
        jobName: String,
        sheetName: String,
        width: Double,
        depth: Double,
        height: Double,
        vectorSpecs: [(name: String, points: [VectorPoint], isClosed: Bool)]
    ) -> ShopPilotPackagePayload {
        let layerID = childID(of: sampleID, salt: 3)
        let vectors: [VectorPath] = vectorSpecs.map { spec in
            VectorPath(name: spec.name, points: spec.points, isClosed: spec.isClosed, layerId: layerID)
        }
        let layer = Layer(id: layerID, name: "Layer 1", vectors: vectors)
        let sheetID = childID(of: sampleID, salt: 2)
        let sheet = Sheet(
            id: sheetID,
            name: sheetName,
            width: width,
            depth: depth,
            height: height,
            layers: [layer]
        )
        var job = Job(id: childID(of: sampleID, salt: 1), name: jobName, sheets: [sheet])
        // Reopen on the (only) sheet.
        job.activeSheetID = sheetID
        return ShopPilotPackagePayload(job: job, toolpaths: [])
    }

    private static func makeSignPayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: signID,
            jobName: "Sign — V-Carve Greeting",
            sheetName: "Sign Board",
            width: 600,
            depth: 400,
            height: 18,
            vectorSpecs: [
                ("Outer Outline", rectanglePoints(x: 10, y: 10, width: 580, height: 380), true),
                ("Inner Border", rectanglePoints(x: 30, y: 30, width: 540, height: 340), true),
                ("Greeting Line 1", rectanglePoints(x: 80, y: 240, width: 440, height: 60), true),
                ("Greeting Line 2", rectanglePoints(x: 120, y: 160, width: 360, height: 50), true),
            ]
        )
    }

    private static func makeBoxPayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: boxID,
            jobName: "Box — Finger Joints",
            sheetName: "Box Panels",
            width: 200,
            depth: 120,
            height: 18,
            vectorSpecs: [
                ("Front Panel", rectanglePoints(x: 10, y: 10, width: 180, height: 100), true),
                ("Side Panel", rectanglePoints(x: 10, y: 10, width: 100, height: 100), true),
                ("Panel Center", rectanglePoints(x: 30, y: 30, width: 140, height: 60), true),
            ]
        )
    }

    private static func makeKeychainPayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: keychainID,
            jobName: "Keychain — Dogbone",
            sheetName: "Keychain Blank",
            width: 80,
            depth: 40,
            height: 6,
            vectorSpecs: [
                ("Fob Outline", rectanglePoints(x: 8, y: 8, width: 64, height: 24), true),
                ("Hole", circlePoints(centerX: 40, centerY: 20, radius: 4), true),
                ("Keyring Slot", rectanglePoints(x: 8, y: 17, width: 14, height: 6), true),
            ]
        )
    }

    private static func makePlaquePayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: plaqueID,
            jobName: "Plaque — Text Relief",
            sheetName: "Plaque Blank",
            width: 300,
            depth: 200,
            height: 25,
            vectorSpecs: [
                ("Outer Border", rectanglePoints(x: 15, y: 15, width: 270, height: 170), true),
                ("Text Relief Area", rectanglePoints(x: 40, y: 40, width: 220, height: 120), true),
                ("Center Rule", rectanglePoints(x: 60, y: 95, width: 180, height: 4), true),
            ]
        )
    }
}
