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
            VectorPoint(x: x, y: y),
        ]
    }

    private static func circlePoints(centerX: Double, centerY: Double, radius: Double, segments: Int = 32) -> [VectorPoint] {
        (0...segments).map { i in
            let angle = Double(i) / Double(segments) * 2 * .pi
            return VectorPoint(x: centerX + radius * cos(angle), y: centerY + radius * sin(angle))
        }
    }

    private static func ellipsePoints(centerX: Double, centerY: Double, rx: Double, ry: Double, segments: Int = 48) -> [VectorPoint] {
        (0...segments).map { i in
            let angle = Double(i) / Double(segments) * 2 * .pi
            return VectorPoint(x: centerX + rx * cos(angle), y: centerY + ry * sin(angle))
        }
    }

    private static func roundedRectPoints(x: Double, y: Double, width: Double, height: Double, radius: Double, perCorner: Int = 6) -> [VectorPoint] {
        let r = min(radius, width / 2, height / 2)
        let corners: [(Double, Double, Double, Double)] = [
            (x + width - r, y + r, -.pi / 2, 0),
            (x + width - r, y + height - r, 0, .pi / 2),
            (x + r, y + height - r, .pi / 2, .pi),
            (x + r, y + r, .pi, 3 * .pi / 2),
        ]
        var pts: [VectorPoint] = []
        for (cx, cy, a0, a1) in corners {
            for i in 0...perCorner {
                let t = Double(i) / Double(perCorner)
                let a = a0 + (a1 - a0) * t
                pts.append(VectorPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
            }
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    private static func starPoints(centerX: Double, centerY: Double, outerR: Double, innerR: Double, spikes: Int = 8) -> [VectorPoint] {
        var pts: [VectorPoint] = []
        let n = spikes * 2
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
            let r = i.isMultiple(of: 2) ? outerR : innerR
            pts.append(VectorPoint(x: centerX + r * cos(a), y: centerY + r * sin(a)))
        }
        return pts
    }

    private static func gearPoints(centerX: Double, centerY: Double, teeth: Int, innerR: Double, outerR: Double) -> [VectorPoint] {
        var pts: [VectorPoint] = []
        for t in 0..<teeth {
            let a0 = Double(t) / Double(teeth) * 2 * .pi
            let a1 = Double(t) / Double(teeth) * 2 * .pi + .pi / Double(teeth)
            let a2 = Double(t + 1) / Double(teeth) * 2 * .pi
            pts.append(VectorPoint(x: centerX + innerR * cos(a0), y: centerY + innerR * sin(a0)))
            pts.append(VectorPoint(x: centerX + outerR * cos(a0 + 0.08), y: centerY + outerR * sin(a0 + 0.08)))
            pts.append(VectorPoint(x: centerX + outerR * cos(a1), y: centerY + outerR * sin(a1)))
            pts.append(VectorPoint(x: centerX + innerR * cos(a2 - 0.08), y: centerY + innerR * sin(a2 - 0.08)))
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    /// Closed finger-joint silhouette: teeth along every edge of a rectangle.
    private static func fingerJointPanel(x: Double, y: Double, width: Double, height: Double, teeth: Int, tooth: Double) -> [VectorPoint] {
        var pts: [VectorPoint] = []
        func addEdge(from: (Double, Double), to: (Double, Double), count: Int, outward: (Double, Double)) {
            let dx = to.0 - from.0
            let dy = to.1 - from.1
            for i in 0..<count {
                let t0 = Double(i) / Double(count)
                let t1 = (Double(i) + 0.5) / Double(count)
                let t2 = Double(i + 1) / Double(count)
                let p0 = (from.0 + dx * t0, from.1 + dy * t0)
                let p1 = (from.0 + dx * t1 + outward.0, from.1 + dy * t1 + outward.1)
                let p2 = (from.0 + dx * t2, from.1 + dy * t2)
                pts.append(VectorPoint(x: p0.0, y: p0.1))
                pts.append(VectorPoint(x: p1.0, y: p1.1))
                pts.append(VectorPoint(x: p2.0, y: p2.1))
            }
        }
        addEdge(from: (x, y), to: (x + width, y), count: teeth, outward: (0, -tooth))
        addEdge(from: (x + width, y), to: (x + width, y + height), count: max(2, teeth / 2), outward: (tooth, 0))
        addEdge(from: (x + width, y + height), to: (x, y + height), count: teeth, outward: (0, tooth))
        addEdge(from: (x, y + height), to: (x, y), count: max(2, teeth / 2), outward: (-tooth, 0))
        if let first = pts.first { pts.append(first) }
        return pts
    }

    /// Block-letter polyline for a short word (HELLO / SHOP) — original geometry, not a font file.
    private static func letterHPoints(x: Double, y: Double, w: Double, h: Double) -> [VectorPoint] {
        let t = w * 0.22
        return [
            VectorPoint(x: x, y: y), VectorPoint(x: x + t, y: y),
            VectorPoint(x: x + t, y: y + h / 2 - t / 2), VectorPoint(x: x + w - t, y: y + h / 2 - t / 2),
            VectorPoint(x: x + w - t, y: y), VectorPoint(x: x + w, y: y),
            VectorPoint(x: x + w, y: y + h), VectorPoint(x: x + w - t, y: y + h),
            VectorPoint(x: x + w - t, y: y + h / 2 + t / 2), VectorPoint(x: x + t, y: y + h / 2 + t / 2),
            VectorPoint(x: x + t, y: y + h), VectorPoint(x: x, y: y + h), VectorPoint(x: x, y: y),
        ]
    }

    private static func makePayload(
        sampleID: UUID,
        jobName: String,
        sheetName: String,
        width: Double,
        depth: Double,
        height: Double,
        vectorSpecs: [(name: String, points: [VectorPoint], isClosed: Bool)],
        heightfield: HeightfieldData? = nil
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
        job.activeSheetID = sheetID
        job.stlHeightfield = heightfield
        return ShopPilotPackagePayload(job: job, toolpaths: [])
    }

    private static func makeSignPayload() -> ShopPilotPackagePayload {
        var specs: [(name: String, points: [VectorPoint], isClosed: Bool)] = [
            ("Outer Outline", roundedRectPoints(x: 12, y: 12, width: 576, height: 376, radius: 28), true),
            ("Inner Border", roundedRectPoints(x: 36, y: 36, width: 528, height: 328, radius: 18), true),
            ("Accent Ring", circlePoints(centerX: 300, centerY: 200, radius: 118), true),
            ("Hub", circlePoints(centerX: 300, centerY: 200, radius: 28), true),
            ("Medallion", gearPoints(centerX: 300, centerY: 200, teeth: 16, innerR: 72, outerR: 98), true),
            ("Star", starPoints(centerX: 300, centerY: 200, outerR: 48, innerR: 22, spikes: 8), true),
        ]
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi
            specs.append((
                "Satellite \(i + 1)",
                circlePoints(centerX: 300 + 155 * cos(a), centerY: 200 + 110 * sin(a), radius: 14, segments: 20),
                true
            ))
        }
        let letterW = 52.0
        let letterH = 70.0
        let startX = 148.0
        let ly = 292.0
        let gap = 14.0
        specs.append(("Letter H1", letterHPoints(x: startX, y: ly, w: letterW, h: letterH), true))
        specs.append(("Letter E", roundedRectPoints(x: startX + letterW + gap, y: ly, width: letterW, height: letterH, radius: 6), true))
        specs.append(("Letter L1", rectanglePoints(x: startX + 2 * (letterW + gap), y: ly, width: letterW * 0.7, height: letterH), true))
        specs.append(("Letter L2", rectanglePoints(x: startX + 2 * (letterW + gap) + letterW, y: ly, width: letterW * 0.7, height: letterH), true))
        specs.append(("Letter O", ellipsePoints(centerX: startX + 5.1 * (letterW + gap), centerY: ly + letterH / 2, rx: letterW / 2, ry: letterH / 2), true))
        specs.append(("Banner", roundedRectPoints(x: 90, y: 58, width: 420, height: 54, radius: 10), true))

        // SPK-DOGFOOD-01 — the authored art is laid out on a 600×400 board,
        // which exceeds the default simulator/MachineProfile travel envelope
        // of 500mm: Run Job instantly hit ALARM:Soft limit at X585. Uniformly
        // scale the whole layout by 0.75 onto a 450×300 sheet — same design,
        // same proportions, max posted move ≈ 453mm < 500 envelope.
        let k = 0.75
        let scaled = specs.map { spec -> (name: String, points: [VectorPoint], isClosed: Bool) in
            (spec.name, spec.points.map { VectorPoint(x: $0.x * k, y: $0.y * k) }, spec.isClosed)
        }
        return makePayload(
            sampleID: signID,
            jobName: "Sign — V-Carve Greeting",
            sheetName: "Sign Board",
            width: 600 * k,
            depth: 400 * k,
            height: 18,
            vectorSpecs: scaled
        )
    }

    private static func makeBoxPayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: boxID,
            jobName: "Box — Finger Joints",
            sheetName: "Box Panels",
            width: 420,
            depth: 280,
            height: 18,
            vectorSpecs: [
                ("Front Panel", fingerJointPanel(x: 18, y: 18, width: 180, height: 110, teeth: 8, tooth: 8), true),
                ("Back Panel", fingerJointPanel(x: 220, y: 18, width: 180, height: 110, teeth: 8, tooth: 8), true),
                ("Left Panel", fingerJointPanel(x: 18, y: 150, width: 110, height: 110, teeth: 6, tooth: 7), true),
                ("Right Panel", fingerJointPanel(x: 150, y: 150, width: 110, height: 110, teeth: 6, tooth: 7), true),
                ("Lid", roundedRectPoints(x: 280, y: 150, width: 120, height: 110, radius: 8), true),
                ("Lid Pocket", roundedRectPoints(x: 298, y: 168, width: 84, height: 74, radius: 6), true),
                ("Handle Hole", circlePoints(centerX: 340, centerY: 205, radius: 10), true),
            ]
        )
    }

    private static func makeKeychainPayload() -> ShopPilotPackagePayload {
        makePayload(
            sampleID: keychainID,
            jobName: "Keychain — Dogbone",
            sheetName: "Keychain Blank",
            width: 90,
            depth: 48,
            height: 6,
            vectorSpecs: [
                ("Fob Outline", roundedRectPoints(x: 6, y: 8, width: 78, height: 32, radius: 16), true),
                ("Inner Pocket", roundedRectPoints(x: 22, y: 14, width: 50, height: 20, radius: 8), true),
                ("Hole", circlePoints(centerX: 16, centerY: 24, radius: 4.2, segments: 24), true),
                ("Dogbone Left", circlePoints(centerX: 24, centerY: 16, radius: 2.2, segments: 16), true),
                ("Dogbone Right", circlePoints(centerX: 70, centerY: 16, radius: 2.2, segments: 16), true),
                ("Dogbone BL", circlePoints(centerX: 24, centerY: 32, radius: 2.2, segments: 16), true),
                ("Dogbone BR", circlePoints(centerX: 70, centerY: 32, radius: 2.2, segments: 16), true),
            ]
        )
    }

    private static func makeCameoHeightfield(widthMm: Double, depthMm: Double, stockMm: Double) -> HeightfieldData {
        let cell = 2.0
        let gw = max(8, Int(widthMm / cell))
        let gh = max(8, Int(depthMm / cell))
        var heights = [Double](repeating: stockMm * 0.35, count: gw * gh)
        let cx = Double(gw) / 2
        let cy = Double(gh) / 2
        for y in 0..<gh {
            for x in 0..<gw {
                let dx = (Double(x) - cx) / cx
                let dy = (Double(y) - cy) / cy
                let r2 = dx * dx + dy * dy
                let mound = max(0, 1 - r2) * stockMm * 0.45
                let ripple = 2.2 * sin(Double(x) * 0.35) * cos(Double(y) * 0.28)
                heights[y * gw + x] = min(stockMm * 0.92, stockMm * 0.28 + mound + ripple)
            }
        }
        return HeightfieldData(width: gw, height: gh, cellSizeMm: cell, minX: 0, minY: 0, heights: heights)
    }

    private static func makePlaquePayload() -> ShopPilotPackagePayload {
        var specs: [(name: String, points: [VectorPoint], isClosed: Bool)] = [
            ("Outer Border", roundedRectPoints(x: 10, y: 10, width: 280, height: 180, radius: 22), true),
            ("Cameo", ellipsePoints(centerX: 150, centerY: 100, rx: 92, ry: 68), true),
            ("Inner Cameo", ellipsePoints(centerX: 150, centerY: 100, rx: 62, ry: 44), true),
            ("Hub Ring", circlePoints(centerX: 150, centerY: 100, radius: 22), true),
        ]
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            specs.append((
                "Scallop \(i + 1)",
                circlePoints(centerX: 150 + 108 * cos(a), centerY: 100 + 72 * sin(a), radius: 9, segments: 16),
                true
            ))
        }
        return makePayload(
            sampleID: plaqueID,
            jobName: "Plaque — Text Relief",
            sheetName: "Plaque Blank",
            width: 300,
            depth: 200,
            height: 25,
            vectorSpecs: specs,
            heightfield: makeCameoHeightfield(widthMm: 300, depthMm: 200, stockMm: 25)
        )
    }
}
