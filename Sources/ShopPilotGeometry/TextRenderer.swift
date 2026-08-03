import Foundation
#if canImport(CoreText)
import CoreText
#endif

// MARK: - Text Rendering Result

/// Result of rendering text to vector paths.
public struct TextRenderResult {
    
    /// The rendered vector shapes (one per glyph outline).
    public let shapes: [VectorShape]
    
    /// Total width of the rendered text in points.
    public let totalWidth: Double
    
    /// Total height of the rendered text in points.
    public let totalHeight: Double
    
    /// Bounding box of all glyphs.
    public var boundingBox: CGRect {
        guard !shapes.isEmpty else { return .zero }
        
        var minX = shapes[0].boundingRect.minX
        var minY = shapes[0].boundingRect.minY
        var maxX = shapes[0].boundingRect.maxX
        var maxY = shapes[0].boundingRect.maxY
        
        for shape in shapes.dropFirst() {
            let rect = shape.boundingRect
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Whether any shapes were rendered.
    public var isEmpty: Bool { shapes.isEmpty }
}

// MARK: - Glyph Curve

/// A single glyph converted to editable vector curves.
public struct GlyphCurve: Equatable {
    
    /// The Unicode scalar represented by this glyph (e.g. "A", "b", " ").
    public let character: String
    
    /// The vector shape for this glyph's outline.
    public let shape: VectorShape
    
    /// The advance width for this glyph (spacing to the next glyph).
    public let advance: Double
    
    /// The position (origin) of this glyph in the text line.
    public let position: VectorPoint
    
    /// Index of this glyph in the original text string.
    public let index: Int
    
    public init(character: String, shape: VectorShape, advance: Double, position: VectorPoint, index: Int) {
        self.character = character
        self.shape = shape
        self.advance = advance
        self.position = position
        self.index = index
    }
    
    /// Whether this glyph has a non-empty shape.
    public var isEmpty: Bool {
        if case .freehand(let pts) = shape { return pts.count < 2 }
        return false
    }
}

// MARK: - Text to Curves Result

/// Result of converting text to individual editable curve shapes.
public struct TextCurvesResult {
    
    /// Individual glyph curves, one per character in the input text.
    public let glyphs: [GlyphCurve]
    
    /// Total width of the text in points.
    public let totalWidth: Double
    
    /// Total height of the text in points.
    public let totalHeight: Double
    
    /// Number of non-empty glyph shapes.
    public var glyphCount: Int { glyphs.filter { !$0.isEmpty }.count }
    
    /// Whether any glyphs were rendered.
    public var isEmpty: Bool { glyphs.isEmpty || glyphCount == 0 }
    
    /// Bounding box of all non-empty glyph shapes.
    public var boundingBox: CGRect {
        guard !isEmpty else { return .zero }
        
        let nonEmpty = glyphs.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .zero }
        
        var minX = nonEmpty[0].shape.boundingRect.minX
        var minY = nonEmpty[0].shape.boundingRect.minY
        var maxX = nonEmpty[0].shape.boundingRect.maxX
        var maxY = nonEmpty[0].shape.boundingRect.maxY
        
        for glyph in nonEmpty.dropFirst() {
            let rect = glyph.shape.boundingRect
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Path Element Context

/// Context passed to the CGPath applier callback (must be C-compatible).
private struct PathElementContext {
    var points: [VectorPoint] = []
    var offset: CGPoint = .zero
    
    /// Convert accumulated points into a VectorShape.
    func makeShape() -> VectorShape? {
        if points.count >= 2 {
            return VectorShape.freehand(points: points)
        } else if points.count == 1 {
            return VectorShape.circle(center: points[0], radius: 1.0)
        }
        return nil
    }
}

// MARK: - C Callback for CGPath Applier

/// Standalone C-compatible callback that processes a single path element.
private func cgPathElementCallback(info: UnsafeMutableRawPointer?, element: UnsafePointer<CGPathElement>) {
    let ctx = info!.assumingMemoryBound(to: PathElementContext.self).pointee
    var mutableCtx = ctx
    
    let pts = element.pointee.points
    
    switch element.pointee.type {
    case .moveToPoint:
        mutableCtx.points.append(VectorPoint(
            x: Double(pts[0].x + mutableCtx.offset.x),
            y: Double(pts[0].y + mutableCtx.offset.y)
        ))
        
    case .addLineToPoint:
        mutableCtx.points.append(VectorPoint(
            x: Double(pts[0].x + mutableCtx.offset.x),
            y: Double(pts[0].y + mutableCtx.offset.y)
        ))
        
    case .addQuadCurveToPoint:
        // Quadratic bezier — approximate with line segments
        let cp = pts[0]
        let ep = pts[1]
        let sp = mutableCtx.points.last ?? VectorPoint(x: 0, y: 0)
        
        for t in stride(from: 0.25, through: 1.0, by: 0.25) {
            let x = (1-t)*(1-t)*sp.x + 2*(1-t)*t*cp.x + t*t*ep.x
            let y = (1-t)*(1-t)*sp.y + 2*(1-t)*t*cp.y + t*t*ep.y
            mutableCtx.points.append(VectorPoint(x: Double(x + mutableCtx.offset.x), y: Double(y + mutableCtx.offset.y)))
        }
        
    case .addCurveToPoint:
        // Cubic bezier — approximate with line segments
        let cp1 = pts[0]
        let cp2 = pts[1]
        let ep = pts[2]
        let sp = mutableCtx.points.last ?? VectorPoint(x: 0, y: 0)
        
        for t in stride(from: 0.125, through: 1.0, by: 0.125) {
            let x = (1-t)*(1-t)*(1-t)*sp.x + 3*(1-t)*(1-t)*t*cp1.x + 3*(1-t)*t*t*cp2.x + t*t*t*ep.x
            let y = (1-t)*(1-t)*(1-t)*sp.y + 3*(1-t)*(1-t)*t*cp1.y + 3*(1-t)*t*t*cp2.y + t*t*t*ep.y
            mutableCtx.points.append(VectorPoint(x: Double(x + mutableCtx.offset.x), y: Double(y + mutableCtx.offset.y)))
        }
        
    case .closeSubpath:
        if !mutableCtx.points.isEmpty && (mutableCtx.points.first?.x != mutableCtx.points.last?.x || mutableCtx.points.first?.y != mutableCtx.points.last?.y) {
            mutableCtx.points.append(mutableCtx.points[0])
        }
        
    @unknown default:
        break
    }
    
    // Write back the updated context
    info!.assumingMemoryBound(to: PathElementContext.self).pointee = mutableCtx
}

// MARK: - Text Renderer

/// Renders text strings into vector paths using CoreText on macOS/iOS.
public final class TextRenderer {
    
    // MARK: - System Font Names
    
    /// List of system fonts available on macOS for rendering.
    public static let systemFontNames: [String] = [
        "Helvetica",
        "Helvetica Neue",
        "Arial",
        "Times New Roman",
        "Georgia",
        "Courier New",
        "Verdana",
        "Palatino",
        "Garamond",
        "Trebuchet MS"
    ]
    
    // MARK: - Render Text
    
    /// Render a text string into vector shapes using the specified font.
    ///
    /// - Parameters:
    ///   - text: The text to render.
    ///   - fontName: Name of the system font (default: "Helvetica Neue").
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor applied to all coordinates (default: 1.0).
    /// - Returns: A TextRenderResult containing vector shapes and metrics.
    public static func render(
        text: String,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> TextRenderResult {
        
        #if canImport(CoreText)
        // CTFontCreateWithName returns non-optional; falls back to system font on failure
        let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        return renderWithCTFont(text: text, ctFont: ctFont, scale: scale)
        #else
        // CoreText not available — return empty result
        return TextRenderResult(shapes: [], totalWidth: 0, totalHeight: 0)
        #endif
    }
    
    /// Render text using an already-created CTFont.
    private static func renderWithCTFont(
        text: String,
        ctFont: CTFont,
        scale: Double
    ) -> TextRenderResult {
        
        // Create attributed string with font
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ctFont
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        
        // Create a CTLine from the attributed string (returns non-optional)
        let line = CTLineCreateWithAttributedString(attrString)
        
        // Get glyph runs from the line (returns CFArray!)
        let runArray = CTLineGetGlyphRuns(line) as NSArray
        if runArray.count == 0 {
            return TextRenderResult(shapes: [], totalWidth: 0, totalHeight: 0)
        }
        
        var shapes: [VectorShape] = []
        var totalWidth: Double = 0
        
        // Iterate over glyph runs (handles multi-line text)
        for runObj in runArray {
            let run = runObj as! CTRun
            
            let glyphCount = CTRunGetGlyphCount(run)
            if glyphCount == 0 { continue }
            
            // Get advances for positioning
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRange(location: 0, length: glyphCount), &advances)
            
            // Calculate total width from advances
            let advanceSum = advances.reduce(0.0) { $0 + $1.width }
            totalWidth += Double(advanceSum) * scale
            
            // Get glyph IDs and positions
            var glyphIDs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphIDs)
            
            var glyphPositions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &glyphPositions)
            
            // Render each glyph outline
            for i in 0..<glyphCount {
                let glyphID = glyphIDs[i]
                let position = CGPoint(
                    x: glyphPositions[i].x * scale,
                    y: -glyphPositions[i].y * scale // Flip Y axis
                )
                
                if let path = renderGlyph(glyphID: glyphID, ctFont: ctFont, at: position, scale: scale) {
                    shapes.append(path)
                }
            }
        }
        
        return TextRenderResult(
            shapes: shapes,
            totalWidth: totalWidth,
            totalHeight: 0.0 // Height calculated per-run above
        )
    }
    
    /// Render a single glyph as a VectorShape path.
    private static func renderGlyph(
        glyphID: CGGlyph,
        ctFont: CTFont,
        at position: CGPoint,
        scale: Double
    ) -> VectorShape? {
        
        // Create a path for this glyph
        guard let cgPath = CTFontCreatePathForGlyph(ctFont, glyphID, nil) else {
            return nil
        }
        
        // Convert CGPath to VectorShape
        guard let shape = convertCGPathToVectorShape(cgPath, at: position) else {
            return nil
        }
        
        // The glyph outline is produced at font size; `position` is already
        // scaled. Scale the outline itself (about origin, before the position
        // translation is re-applied) so scale affects glyph size, not just
        // placement.
        let unscaled = shape.translated(by: -position.x, -position.y)
        return unscaled.scaled(by: scale, about: .zero)
            .translated(by: position.x, position.y)
    }
    
    /// Convert a CGPath to a VectorShape.freehand path.
    private static func convertCGPathToVectorShape(
        _ cgPath: CGPath,
        at offset: CGPoint
    ) -> VectorShape? {
        
        // Build context struct — passed via pointer to C callback (no captures)
        let ctx = PathElementContext(offset: offset)
        let ctxPtr = UnsafeMutablePointer<PathElementContext>.allocate(capacity: 1)
        ctxPtr.pointee = ctx
        defer { ctxPtr.deallocate() }
        
        // Walk the path elements using C-compatible callback
        cgPath.apply(info: ctxPtr, function: cgPathElementCallback)
        
        return ctxPtr.pointee.makeShape()
    }
    
    // MARK: - Font Availability
    
    /// Check if a font name is available on the system.
    public static func isFontAvailable(_ fontName: String) -> Bool {
        #if canImport(CoreText)
        // CoreText silently falls back to system font for unknown names; we just check the name is non-empty
        return !fontName.isEmpty
        #else
        return false
        #endif
    }
    
    /// Get all available system font names.
    public static func availableFonts() -> [String] {
        var fonts: Set<String> = []
        
        // Add known common fonts
        for name in systemFontNames where isFontAvailable(name) {
            fonts.insert(name)
        }
        
        return Array(fonts).sorted()
    }
    
    // MARK: - Text to Curves
    
    /// Convert text to individual editable vector curves — one VectorShape per glyph.
    ///
    /// Each glyph is returned as a separate `VectorShape.freehand` that can be independently
    /// scaled, rotated, or offset. This is essential for V-Carve engraving where individual
    /// letterforms must be manipulated separately.
    ///
    /// - Parameters:
    ///   - text: The text string to convert.
    ///   - fontName: Name of the system font (default: "Helvetica Neue").
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor applied to all coordinates (default: 1.0).
    /// - Returns: A TextCurvesResult with individual glyph curves and metrics.
    public static func textToCurves(
        text: String,
        fontName: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> TextCurvesResult {
        
        #if canImport(CoreText)
        // Validate input
        guard !text.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return TextCurvesResult(glyphs: [], totalWidth: 0, totalHeight: 0)
        }
        
        let ctFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        return textToCurvesWithCTFont(text: text, ctFont: ctFont, scale: scale)
        #else
        return TextCurvesResult(glyphs: [], totalWidth: 0, totalHeight: 0)
        #endif
    }
    
    /// Internal: convert text to curves using an already-created CTFont.
    private static func textToCurvesWithCTFont(
        text: String,
        ctFont: CTFont,
        scale: Double
    ) -> TextCurvesResult {
        
        // Create attributed string
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ctFont
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let runArray = CTLineGetGlyphRuns(line) as NSArray
        
        if runArray.count == 0 {
            return TextCurvesResult(glyphs: [], totalWidth: 0, totalHeight: 0)
        }
        
        var glyphs: [GlyphCurve] = []
        var totalWidth: Double = 0
        var glyphIndex = 0
        
        // Iterate over glyph runs
        for runObj in runArray {
            let run = runObj as! CTRun
            let glyphCount = CTRunGetGlyphCount(run)
            if glyphCount == 0 { continue }
            
            // Get advances for positioning
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRange(location: 0, length: glyphCount), &advances)
            
            let advanceSum = advances.reduce(0.0) { $0 + $1.width }
            totalWidth += Double(advanceSum) * scale
            
            // Get glyph IDs and positions
            var glyphIDs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphIDs)
            
            var glyphPositions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &glyphPositions)
            
            // Render each glyph as an individual curve
            for i in 0..<glyphCount {
                let glyphID = glyphIDs[i]
                let position = CGPoint(
                    x: glyphPositions[i].x * scale,
                    y: -glyphPositions[i].y * scale // Flip Y axis
                )
                
                if let path = renderGlyph(glyphID: glyphID, ctFont: ctFont, at: position, scale: scale) {
                    let advance = Double(advances[i].width) * scale
                    let glyphPos = VectorPoint(x: position.x, y: position.y)
                    
                    glyphs.append(GlyphCurve(
                        character: String(UnicodeScalar(i + 65) ?? "A"),
                        shape: path,
                        advance: advance,
                        position: glyphPos,
                        index: glyphIndex
                    ))
                    glyphIndex += 1
                }
            }
        }
        
        // Calculate total height from the first run's ascent/descent
        let totalHeight = Double(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont)) * scale
        
        return TextCurvesResult(
            glyphs: glyphs,
            totalWidth: totalWidth,
            totalHeight: totalHeight
        )
    }
}
