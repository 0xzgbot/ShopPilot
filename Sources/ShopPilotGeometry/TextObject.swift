import Foundation

// MARK: - Text Object

/// A document-level text object: an editable string rendered with a system font.
///
/// This is the persistable model for the SPK-0500 "text + system fonts" feature.
/// It stores the raw string and font name, renders to vector shapes through the
/// CoreText pipeline (`TextTool`), and round-trips through Codable so it can live
/// in the `.shoppilot` document payload.
public struct TextObject: Codable, Equatable, Identifiable {

    /// Stable identity for document references (undo, selection, layers).
    public let id: UUID

    /// The text content (may contain any Unicode characters).
    public var string: String

    /// System font name, e.g. "Helvetica Neue", "Georgia", "Courier New".
    /// Use `TextTool.getAvailableFonts()` to enumerate valid names.
    public var fontName: String

    /// Font size in points (design units before any job scale).
    public var fontSize: Double

    /// Whether the object renders nothing (empty or whitespace-only string).
    public var isEmpty: Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        id: UUID = UUID(),
        string: String,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 72.0
    ) {
        self.id = id
        self.string = string
        self.fontName = fontName
        self.fontSize = max(1.0, fontSize)
    }

    // MARK: - Rendering

    /// Render this text object to vector shapes (glyph outlines).
    ///
    /// Empty / whitespace-only strings return a result with no shapes.
    public func renderToShapes(scale: Double = 1.0) -> TextCreationResult {
        TextTool.createText(text: string, font: fontName, fontSize: fontSize, scale: scale)
    }

    /// Convert this text object to individual editable glyph curves.
    ///
    /// One `VectorShape` per glyph — the input for V-Carve / engraving toolpaths.
    public func convertToCurves(scale: Double = 1.0) -> TextCurvesResult {
        TextTool.convertToCurvesDetailed(text: string, font: fontName, fontSize: fontSize, scale: scale)
    }

    /// Convenience: the vector shapes for this object (same as `renderToShapes().shapes`).
    public var shapes: [VectorShape] {
        renderToShapes().shapes
    }
}
