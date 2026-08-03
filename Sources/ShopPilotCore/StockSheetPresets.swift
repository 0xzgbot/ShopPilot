import Foundation

// MARK: - Stock Sheet Preset

/// A standard stock sheet size + thickness (SPK-1132).
///
/// Ships the same 72 presets a professional CNC CAM suite offers out of the
/// box: six imperial sheet sizes × six thicknesses and six metric sheet
/// sizes × six thicknesses. These are industry-standard sheet goods
/// dimensions (names match the template naming convention, e.g.
/// `4'x8'x0.375''` / `1219x2438x18 mm`).
public struct StockSheetPreset: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    /// Display name, e.g. `4'x8'x0.375''` or `1219x2438x18 mm`.
    public let name: String
    /// Sheet width (X) in mm.
    public let widthMM: Double
    /// Sheet depth (Y) in mm.
    public let depthMM: Double
    /// Stock thickness (Z) in mm.
    public let thicknessMM: Double
    /// `true` when the preset is a metric-size sheet.
    public let isMetric: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        widthMM: Double,
        depthMM: Double,
        thicknessMM: Double,
        isMetric: Bool
    ) {
        self.id = id
        self.name = name
        self.widthMM = widthMM
        self.depthMM = depthMM
        self.thicknessMM = thicknessMM
        self.isMetric = isMetric
    }
}

// MARK: - Preset Catalog

/// The 72 shipped stock sheet presets (SPK-1132).
///
/// Layout mirrors the reference catalog: imperial sheets first (six sizes ×
/// six thicknesses), then metric sheets (six sizes × six thicknesses), each
/// size block ordered by ascending thickness.
public enum StockSheetPresets {

    // MARK: Imperial sizes (feet → mm; 1 ft = 304.8 mm)

    /// Imperial sheet sizes: (name, width mm, depth mm).
    public static let imperialSizes: [(name: String, width: Double, depth: Double)] = [
        ("2'x2'", 609.6, 609.6),
        ("2'x4'", 609.6, 1219.2),
        ("4'x2'", 1219.2, 609.6),
        ("4'x4'", 1219.2, 1219.2),
        ("4'x8'", 1219.2, 2438.4),
        ("8'x4'", 2438.4, 1219.2)
    ]

    /// Imperial thicknesses: (label, mm).
    public static let imperialThicknesses: [(label: String, mm: Double)] = [
        ("0.125", 3.175),
        ("0.25", 6.35),
        ("0.375", 9.525),
        ("0.5", 12.7),
        ("0.75", 19.05),
        ("1", 25.4)
    ]

    // MARK: Metric sizes (mm)

    /// Metric sheet sizes: (name, width mm, depth mm).
    public static let metricSizes: [(name: String, width: Double, depth: Double)] = [
        ("610x610", 610, 610),
        ("610x1219", 610, 1219),
        ("1219x610", 1219, 610),
        ("1219x1219", 1219, 1219),
        ("1219x2438", 1219, 2438),
        ("2438x1219", 2438, 1219)
    ]

    /// Metric thicknesses in mm.
    public static let metricThicknesses: [Double] = [3, 6, 9, 12, 18, 25]

    // MARK: - Catalog

    /// All 72 presets: 36 imperial + 36 metric, deterministic order.
    public static let all: [StockSheetPreset] = {
        var result: [StockSheetPreset] = []
        for size in imperialSizes {
            for thickness in imperialThicknesses {
                result.append(StockSheetPreset(
                    name: "\(size.name)x\(thickness.label)''",
                    widthMM: size.width,
                    depthMM: size.depth,
                    thicknessMM: thickness.mm,
                    isMetric: false
                ))
            }
        }
        for size in metricSizes {
            for thickness in metricThicknesses {
                result.append(StockSheetPreset(
                    name: "\(size.name)x\(Int(thickness)) mm",
                    widthMM: size.width,
                    depthMM: size.depth,
                    thicknessMM: thickness,
                    isMetric: true
                ))
            }
        }
        return result
    }()

    /// Imperial presets only (36).
    public static let imperial: [StockSheetPreset] =
        all.filter { !$0.isMetric }

    /// Metric presets only (36).
    public static let metric: [StockSheetPreset] =
        all.filter { $0.isMetric }

    /// Look up a preset by its display name (stable key across launches).
    public static func preset(named name: String) -> StockSheetPreset? {
        all.first { $0.name == name }
    }

    // MARK: - Apply

    /// Apply a preset to a sheet: sets name, W/D/H, and records the preset
    /// name on the sheet so the choice survives save/open.
    public static func apply(_ preset: StockSheetPreset, to sheet: inout Sheet) {
        sheet.name = preset.name
        sheet.width = preset.widthMM
        sheet.depth = preset.depthMM
        sheet.height = preset.thicknessMM
        sheet.stockPresetName = preset.name
    }
}
