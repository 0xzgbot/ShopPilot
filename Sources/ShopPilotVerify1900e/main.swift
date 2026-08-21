import Foundation
#if canImport(ShopPilotCore)
import ShopPilotCore
#endif

// SPK-1900e — verify CLT for ImageToReliefEngine.
// Covers: autoLevels stretch, gaussian smoothing (roughness down, envelope
// preserved), detailBoost contrast ordering + plain-pipeline equivalence,
// invert direction flip, adversarial inputs, aspect/grid geometry, Codable
// round-trip, determinism.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func approxEqual(_ a: [Double], _ b: [Double], tol: Double = 1e-12) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a, b).allSatisfy { abs($0 - $1) <= tol }
}

/// Mean absolute neighbor difference (local contrast proxy).
func localContrast(_ hf: HeightfieldData) -> Double {
    var total = 0.0
    var n = 0
    for y in 0..<hf.height {
        for x in 0..<(hf.width - 1) {
            total += abs(hf.heights[y * hf.width + x] - hf.heights[y * hf.width + x + 1])
            n += 1
        }
    }
    for y in 0..<(hf.height - 1) {
        for x in 0..<hf.width {
            total += abs(hf.heights[y * hf.width + x] - hf.heights[(y + 1) * hf.width + x])
            n += 1
        }
    }
    return n > 0 ? total / Double(n) : 0
}

func stdDev(_ v: [Double]) -> Double {
    let n = Double(v.count)
    guard n > 0 else { return 0 }
    let mean = v.reduce(0, +) / n
    let sq = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
    return (sq / n).squareRoot()
}

func makeImage(width: Int, height: Int, _ f: (Int, Int) -> Double) -> [[Double]] {
    (0..<height).map { y in (0..<width).map { x in f(x, y) } }
}

func run() throws {
    // (1) autoLevels stretches a flat-ish 0.45..0.55 ramp to span full range.
    do {
        let img = makeImage(width: 60, height: 40) { x, _ in 0.45 + 0.10 * Double(x) / 59.0 }
        let params = ImageToReliefParams(autoLevels: true, gaussianSigmaCells: 0,
                                         maxHeightMm: 5.0, maxWidthMm: 60.0,
                                         gridResolution: 60)
        let hf = ImageToReliefEngine.generateHeightfield(luminance: img, params: params)
        try expect(hf.heights.min()! < 0.05 * 5.0, "autoLevels: stretched min below 5% of max height (got \(hf.heights.min()!))")
        try expect(hf.heights.max()! > 0.95 * 5.0, "autoLevels: stretched max reaches ~full depth")
    }

    // (2) Gaussian smoothing reduces peak-to-peak variance but preserves the
    // global envelope.
    do {
        let img = makeImage(width: 80, height: 60) { x, y in
            let base = 0.5 + 0.2 * sin(Double(x) / 12.0)
            let noise = ((x * 31 + y * 17) % 7 == 0) ? 0.35 : (((x * 13 + y * 29) % 11 == 0) ? -0.30 : 0)
            return min(1.0, max(0.0, base + noise))
        }
        let rawParams = ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 0,
                                            maxHeightMm: 5.0, maxWidthMm: 80.0,
                                            gridResolution: 80)
        let smoothParams = ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 1.5,
                                               maxHeightMm: 5.0, maxWidthMm: 80.0,
                                               gridResolution: 80)
        let raw = ImageToReliefEngine.generateHeightfield(luminance: img, params: rawParams)
        let smooth = ImageToReliefEngine.generateHeightfield(luminance: img, params: smoothParams)
        try expect(stdDev(smooth.heights) < stdDev(raw.heights),
                   "gaussian: roughness reduced (\(stdDev(smooth.heights)) >= \(stdDev(raw.heights)))")
        try expect(stdDev(smooth.heights) > 0.6 * stdDev(raw.heights),
                   "gaussian: global envelope roughly preserved")
        let eps = 1e-9
        try expect(smooth.heights.max()! <= raw.heights.max()! + eps,
                   "gaussian: blurred max does not exceed raw max")
    }

    // (3) detailBoost=0 equals the plain pipeline; ±0.6 changes output and
    // positive boost increases local contrast.
    do {
        let img = makeImage(width: 64, height: 64) { x, y in
            0.5 + 0.15 * sin(Double(x) / 3.0) * cos(Double(y) / 4.0)
                + 0.05 * sin(Double(x * x + y) / 7.0)
        }
        func run(_ boost: Double) -> HeightfieldData {
            ImageToReliefEngine.generateHeightfield(
                luminance: img,
                params: ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 1.5,
                                            detailBoost: boost, maxHeightMm: 5.0,
                                            maxWidthMm: 64.0, gridResolution: 64))
        }
        let plain = ImageToReliefEngine.generateHeightfield(
            luminance: img,
            params: ImageToReliefParams())
        let zeroBoost = ImageToReliefEngine.generateHeightfield(
            luminance: img,
            params: .autoLevelsWithBoostZero)
        try expect(approxEqual(plain.heights, zeroBoost.heights),
                   "detailBoost=0 matches default/plain pipeline")
        let plus = run(0.6)
        let minus = run(-0.6)
        try expect(!approxEqual(plus.heights, minus.heights, tol: 1e-9),
                   "detailBoost ±0.6 produce different outputs")
        try expect(localContrast(plus) > localContrast(zeroBoost),
                   "detailBoost +0.6 increases local contrast")
        try expect(abs(localContrast(plus) - localContrast(minus)) > 1e-9,
                   "detailBoost ±0.6 differ measurably")
    }

    // (4) invert flips monotonic direction.
    do {
        let img = makeImage(width: 50, height: 20) { x, _ in Double(x) / 49.0 }
        let normal = ImageToReliefEngine.generateHeightfield(
            luminance: img,
            params: ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 0,
                                        maxHeightMm: 5.0, maxWidthMm: 50.0,
                                        gridResolution: 50, invert: false))
        let flipped = ImageToReliefEngine.generateHeightfield(
            luminance: img,
            params: ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 0,
                                        maxHeightMm: 5.0, maxWidthMm: 50.0,
                                        gridResolution: 50, invert: true))
        let midY = normal.height / 2
        let firstN = normal.heights[midY * normal.width]
        let lastN = normal.heights[midY * normal.width + normal.width - 1]
        let firstF = flipped.heights[midY * flipped.width]
        let lastF = flipped.heights[midY * flipped.width + flipped.width - 1]
        try expect(lastN > firstN, "non-inverted ramp rises left→right")
        try expect(lastF < firstF, "inverted ramp falls left→right")
    }

    // (5) Adversarial inputs (NaN, -1, 2.5) produce finite clamped output.
    do {
        let img = makeImage(width: 30, height: 30) { x, y in
            switch (x * 7 + y * 3) % 5 {
            case 0: return Double.nan
            case 1: return -1.0
            case 2: return 2.5
            case 3: return Double.infinity
            default: return Double(y) / 29.0
            }
        }
        let hf = ImageToReliefEngine.generateHeightfield(luminance: img, params: ImageToReliefParams())
        try expect(hf.heights.allSatisfy { $0.isFinite }, "adversarial: all outputs finite")
        try expect(hf.heights.allSatisfy { $0 >= 0 && $0 <= 5.0 + 1e-9 },
                   "adversarial: all outputs clamped to [0, maxHeight]")
    }

    // (6) Aspect ratio + grid dimensions correct.
    do {
        let img = makeImage(width: 400, height: 100) { _, _ in 0.5 }
        let hf = ImageToReliefEngine.generateHeightfield(
            luminance: img,
            params: ImageToReliefParams(maxWidthMm: 100.0, gridResolution: 200))
        try expect(hf.width == 200, "aspect: wide image gets 200 cells on X (got \(hf.width))")
        try expect(hf.height == 50, "aspect: height cells preserve 4:1 aspect (got \(hf.height))")
        try expect(abs(hf.cellSizeMm - 0.5) < 1e-9, "aspect: uniform cell size 0.5mm")
        try expect(abs((Double(hf.width) * hf.cellSizeMm) - 100.0) < 1e-9, "aspect: width = maxWidthMm")
        try expect(abs((Double(hf.height) * hf.cellSizeMm) - 25.0) < 1e-6, "aspect: height = 25mm")

        let tall = makeImage(width: 100, height: 400) { _, _ in 0.5 }
        let hfTall = ImageToReliefEngine.generateHeightfield(
            luminance: tall,
            params: ImageToReliefParams(maxWidthMm: 100.0, gridResolution: 200))
        try expect(hfTall.height == 200 && hfTall.width == 50,
                   "aspect: tall image puts resolution on Y")
    }

    // (7) Params Codable round-trip.
    do {
        let p = ImageToReliefParams(autoLevels: false, gaussianSigmaCells: 2.25,
                                    detailBoost: 0.4, maxHeightMm: 7.5,
                                    maxWidthMm: 120.0, gridResolution: 150,
                                    invert: true)
        let data = try JSONEncoder().encode(p)
        let q = try JSONDecoder().decode(ImageToReliefParams.self, from: data)
        try expect(q.autoLevels == p.autoLevels && q.gaussianSigmaCells == p.gaussianSigmaCells
                    && q.detailBoost == p.detailBoost && q.maxHeightMm == p.maxHeightMm
                    && q.maxWidthMm == p.maxWidthMm && q.gridResolution == p.gridResolution
                    && q.invert == p.invert,
                   "params Codable round-trip preserves every field")
    }

    // (8) Determinism: identical inputs → identical outputs.
    do {
        let img = makeImage(width: 48, height: 36) { x, y in
            0.3 + 0.4 * Double((x * x + 3 * y) % 23) / 22.0
        }
        let params = ImageToReliefParams()
        let a = ImageToReliefEngine.generateHeightfield(luminance: img, params: params)
        let b = ImageToReliefEngine.generateHeightfield(luminance: img, params: params)
        try expect(approxEqual(a.heights, b.heights), "determinism: repeated runs identical")
    }

    print("checks complete")
}

// Helper kept separate so the (3) block stays readable: default params with
// only detailBoost forced to 0.
extension ImageToReliefParams {
    static var autoLevelsWithBoostZero: ImageToReliefParams {
        ImageToReliefParams(detailBoost: 0.0)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write("ShopPilotVerify1900e: FAIL — \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("ShopPilotVerify1900e: PASS — image-to-relief engine")
