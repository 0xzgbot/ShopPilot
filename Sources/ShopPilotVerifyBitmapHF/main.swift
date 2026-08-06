import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ShopPilotCore

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func writePNG(_ rows: [[[UInt8]]], to url: URL) throws {
    let h = rows.count
    let w = rows[0].count
    var data = [UInt8](repeating: 0, count: w * h * 4)
    for r in 0..<h {
        for c in 0..<w {
            let o = (r * w + c) * 4
            for k in 0..<4 { data[o + k] = rows[r][c][k] }
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &data, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw VerifyError.failed("PNG context") }
    guard let img = ctx.makeImage() else { throw VerifyError.failed("PNG image") }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw VerifyError.failed("PNG destination")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw VerifyError.failed("PNG finalize") }
}

func tempURL(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hermes-verify-bmhf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

func main() throws {
    // 1. Build from raw pixels.
    let cfg = BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: false, smoothingPasses: 0, maxCells: 600)

    let white = BitmapHeightfieldImporter.build(
        fromPixels: [Double](repeating: 1.0, count: 16), width: 4, height: 4, config: cfg
    )
    try expect(white.success && white.heightfield != nil, "white build succeeds")
    let whf = try white.heightfield ?? { throw VerifyError.failed("white heightfield") }()
    try expect(whf.width == 4 && whf.height == 4, "white grid 4x4 got \(whf.width)x\(whf.height)")
    try expect(whf.heights.allSatisfy { abs($0 - 10.0) < 1e-9 }, "white -> all cells at maxHeight 10")
    try expect(abs(whf.cellSizeMm - 1.0) < 1e-9, "cell = mmPerPixel 1.0 got \(whf.cellSizeMm)")

    let inv = BitmapHeightfieldImporter.build(
        fromPixels: [0, 0, 0, 0], width: 2, height: 2,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: true, smoothingPasses: 0, maxCells: 600)
    )
    let ihf = try inv.heightfield ?? { throw VerifyError.failed("invert heightfield") }()
    try expect(ihf.heights.allSatisfy { abs($0 - 10.0) < 1e-9 }, "invert: black -> peak")

    let gray = BitmapHeightfieldImporter.build(
        fromPixels: [0.5, 0.5, 0.5, 0.5], width: 2, height: 2,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: false, smoothingPasses: 0, maxCells: 600)
    )
    let ghf = try gray.heightfield ?? { throw VerifyError.failed("gray heightfield") }()
    try expect(abs(ghf.heights[0] - 5.0) < 1e-9, "gray 0.5 -> 5.0mm got \(ghf.heights[0])")

    var spot = [Double](repeating: 0, count: 9)
    spot[4] = 1.0
    let sm = BitmapHeightfieldImporter.build(
        fromPixels: spot, width: 3, height: 3,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 8.0, invert: false, smoothingPasses: 1, maxCells: 600)
    )
    let shf = try sm.heightfield ?? { throw VerifyError.failed("smooth heightfield") }()
    let center = shf.heights[4] / 8.0
    try expect(abs(center - 0.25) < 1e-9, "2D smoothing: center 0.25 not 0.5 got \(center)")
    try expect(shf.heights[0] / 8.0 > 0, "corner blurred above 0 after 1 pass")

    let ds = BitmapHeightfieldImporter.build(
        fromPixels: [Double](repeating: 0.5, count: 32 * 32), width: 32, height: 32,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: false, smoothingPasses: 0, maxCells: 16)
    )
    let dhf = try ds.heightfield ?? { throw VerifyError.failed("downsample heightfield") }()
    try expect(dhf.width == 16 && dhf.height == 16, "32x32 -> 16x16 got \(dhf.width)x\(dhf.height)")
    try expect(dhf.heights.allSatisfy { abs($0 - 5.0) < 1e-9 }, "box-average keeps uniform value")
    try expect(abs(dhf.cellSizeMm - 2.0) < 1e-9, "cell 2.0mm after 2x got \(dhf.cellSizeMm)")
    try expect(abs(dhf.bounds.maxX - 32.0) < 1e-9, "world width 32mm got \(dhf.bounds.maxX)")

    let clamped = BitmapHeightfieldConfig(maxCells: 4)
    try expect(clamped.maxCells == 16, "maxCells clamps to minimum 16")

    // 2. Decode a real PNG with orientation check.
    let whitePx: [UInt8] = [255, 255, 255, 255]
    let grayPx: [UInt8] = [128, 128, 128, 255]
    let blackPx: [UInt8] = [0, 0, 0, 255]
    let pngURL = try tempURL("gradient.png")
    try writePNG([[whitePx, whitePx], [grayPx, grayPx], [blackPx, blackPx]], to: pngURL)

    let dec = BitmapHeightfieldImporter.decodeImage(
        at: pngURL,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: false, smoothingPasses: 0, maxCells: 600)
    )
    try expect(dec.success, "PNG decode succeeds")
    try expect(dec.widthPx == 2 && dec.heightPx == 3, "decoded dims 2x3 got \(dec.widthPx)x\(dec.heightPx)")
    let dh = try dec.heightfield ?? { throw VerifyError.failed("decode heightfield") }()

    try expect(dh.heights[0] > 9.5, "top row -> peak got \(dh.heights[0])")
    try expect(dh.heights[1] > 9.5, "top row 2nd px -> peak got \(dh.heights[1])")
    try expect(abs(dh.heights[2] - 5.0) < 0.7, "mid row -> ~5.0 got \(dh.heights[2])")
    try expect(dh.heights[4] < 0.05, "bottom row -> floor got \(dh.heights[4])")
    try expect(dh.heights[5] < 0.05, "bottom row 2nd px -> floor got \(dh.heights[5])")

    // 3. Decode downscale: 32x32 white -> 16x16 grid.
    let bigURL = try tempURL("big.png")
    let bigRow = [[UInt8]](repeating: whitePx, count: 32)
    let bigRows: [[[UInt8]]] = [[[UInt8]]](repeating: bigRow, count: 32)
    try writePNG(bigRows, to: bigURL)
    let bigDec = BitmapHeightfieldImporter.decodeImage(
        at: bigURL,
        config: BitmapHeightfieldConfig(mmPerPixel: 1.0, maxHeightMm: 10.0, invert: false, smoothingPasses: 0, maxCells: 16)
    )
    try expect(bigDec.success, "big PNG decode succeeds")
    let bhf = try bigDec.heightfield ?? { throw VerifyError.failed("big heightfield") }()
    try expect(bhf.width == 16 && bhf.height == 16, "32x32 -> 16x16 got \(bhf.width)x\(bhf.height)")
    try expect(bhf.heights.allSatisfy { $0 > 9.9 }, "downscaled white stays at peak")

    // 4. Persist: Job round-trip + legacy decode.
    var job = Job(name: "Bitmap Relief Job")
    job.stlHeightfield = whf
    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(Job.self, from: data)
    try expect(decoded.stlHeightfield?.width == 4 && decoded.stlHeightfield?.heights == whf.heights,
               "Job round-trip keeps the bitmap-derived relief")
    let legacyData = try JSONEncoder().encode(Job(name: "Old Job"))
    var legacyObject = try JSONSerialization.jsonObject(with: legacyData) as? [String: Any] ?? [:]
    legacyObject.removeValue(forKey: "stlHeightfield")
    let legacy = try JSONDecoder().decode(Job.self, from: JSONSerialization.data(withJSONObject: legacyObject))
    try expect(legacy.stlHeightfield == nil, "legacy Job (no relief key) decodes nil")

    // 5. Robustness.
    let garbageURL = try tempURL("bad.png")
    try Data("definitely not an image".utf8).write(to: garbageURL)
    let garbage = BitmapHeightfieldImporter.decodeImage(at: garbageURL, config: BitmapHeightfieldConfig())
    try expect(!garbage.success && garbage.errorMessage != nil, "garbage bytes fail with an error (no crash)")
    let missing = BitmapHeightfieldImporter.decodeImage(
        at: URL(fileURLWithPath: "/nonexistent/nope.png"),
        config: BitmapHeightfieldConfig()
    )
    try expect(!missing.success && (missing.errorMessage ?? "").contains("not found"),
               "missing file reports file-not-found")

    print("ShopPilotVerifyBitmapHF: PASS - pixel build, 2D smoothing, downsample, PNG decode + orientation, Job round-trip + legacy nil, graceful failures")
}

do {
    try main()
} catch {
    print("ShopPilotVerifyBitmapHF: FAIL - \(error)")
    exit(1)
}
