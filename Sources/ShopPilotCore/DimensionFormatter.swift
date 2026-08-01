/// Dimension formatting utilities for ShopPilot.
public struct DimensionFormatter {

    /// Millimeters per inch.
    public static let mmPerInch: Double = 25.4

    // MARK: - Single dimension

    /// Format a millimetre value as `"123.45 mm"`.
    public static func formatMillimeters(_ mm: Double) -> String {
        let value = String(format: "%.2f", mm)
        return "\(value) mm"
    }

    /// Convert millimetres to inches and format as `"4.86 in"`.
    public static func formatInches(_ mm: Double) -> String {
        let inches = mm / mmPerInch
        let value = String(format: "%.2f", inches)
        return "\(value) in"
    }

    // MARK: - 3D dimensions

    /// Format a 3D dimension in millimetres: `"600 × 400 × 25 mm"`.
    public static func formatDimensionMM(width: Double, depth: Double, height: Double) -> String {
        let w = String(format: "%.2f", width)
        let d = String(format: "%.2f", depth)
        let h = String(format: "%.2f", height)
        return "\(w) × \(d) × \(h) mm"
    }

    /// Format a 3D dimension in inches: `"23.62 × 15.75 × 0.98 in"`.
    public static func formatDimensionIN(width: Double, depth: Double, height: Double) -> String {
        let w = String(format: "%.2f", width / mmPerInch)
        let d = String(format: "%.2f", depth / mmPerInch)
        let h = String(format: "%.2f", height / mmPerInch)
        return "\(w) × \(d) × \(h) in"
    }

    // MARK: - Area / Volume

    /// Format an area in square millimetres: `"240,000 mm²"`.
    public static func formatAreaMM(width: Double, depth: Double) -> String {
        let area = width * depth
        let formatted = String(format: "%.0f", area)
        return "\(formatted) mm²"
    }

    /// Format a volume in cubic millimetres: `"6,000,000 mm³"`.
    public static func formatVolumeMM(width: Double, depth: Double, height: Double) -> String {
        let volume = width * depth * height
        let formatted = String(format: "%.0f", volume)
        return "\(formatted) mm³"
    }
}
