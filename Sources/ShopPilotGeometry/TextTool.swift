import Foundation
#if canImport(CoreText)
import CoreText
#endif

// MARK: - Text Metrics

/// Text metrics computed during rendering.
public struct TextMetrics: Codable, Equatable {
    
    /// Total advance width of the text string (sum of all glyph advances).
    public let totalAdvance: Double
    
    /// Ascent of the font (distance from baseline to top of tallest glyph).
    public let ascent: Double
    
    /// Descent of the font (distance from baseline to bottom of lowest glyph).
    public let descent: Double
    
    /// Total height (ascent + |descent|).
    public var totalHeight: Double {
        ascent + abs(descent)
    }
    
    /// Bounding box of the rendered text.
    public let boundingBox: Rect
    
    /// Number of glyphs rendered.
    public let glyphCount: Int
    
    public init(
        totalAdvance: Double,
        ascent: Double,
        descent: Double,
        boundingBox: Rect,
        glyphCount: Int
    ) {
        self.totalAdvance = totalAdvance
        self.ascent = ascent
        self.descent = descent
        self.boundingBox = boundingBox
        self.glyphCount = glyphCount
    }
}

// MARK: - Text Creation Result

/// Result of creating text as vector shapes.
public struct TextCreationResult: Codable {
    
    /// The rendered vector shapes.
    public var shapes: [VectorShape]
    
    /// Text metrics (advance, ascent, descent, bounding box).
    public let metrics: TextMetrics
    
    /// Whether any shapes were rendered.
    public var isEmpty: Bool { shapes.isEmpty }
    
    /// Bounding rectangle of all shapes.
    public var boundingRect: Rect {
        shapes.reduce(Rect()) { acc, shape in
            let r = shape.boundingRect
            return Rect(
                minX: min(acc.minX, r.minX),
                minY: min(acc.minY, r.minY),
                maxX: max(acc.maxX, r.maxX),
                maxY: max(acc.maxY, r.maxY)
            )
        }
    }
}

// MARK: - Text Tool

/// User-facing API for creating text as vector shapes.
///
/// Uses CoreText on macOS to render text as VectorShape.freehand paths
/// suitable for CNC toolpaths (engraving, sign lettering, etc.).
public final class TextTool {
    
    // MARK: - Create Text
    
    /// Create text as vector shapes for CNC toolpaths.
    ///
    /// - Parameters:
    ///   - text: The text string to render.
    ///   - font: Font name (e.g. "Helvetica", "Georgia", "Courier New").
    ///           Use `getAvailableFonts()` to see available fonts.
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor to apply to all coordinates.
    ///            1.0 = 1 point = 1 unit. Use >1 to enlarge, <1 to shrink.
    ///            For sign-making, typical values: 10–50 depending on desired size.
    /// - Returns: A TextCreationResult containing vector shapes and text metrics.
    ///
    /// - Note: Returns empty shapes for empty or whitespace-only text.
    ///         Kerning pairs are handled automatically by CoreText.
    public static func createText(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> TextCreationResult {
        
        // Validate input
        guard !text.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return TextCreationResult(
                shapes: [],
                metrics: TextMetrics(
                    totalAdvance: 0,
                    ascent: 0,
                    descent: 0,
                    boundingBox: Rect(),
                    glyphCount: 0
                )
            )
        }
        
        // Render text using CoreText
        let renderResult = TextRenderer.render(
            text: text,
            fontName: font,
            fontSize: fontSize,
            scale: scale
        )
        
        // Compute metrics from rendering
        let metrics = computeMetrics(
            text: text,
            font: font,
            fontSize: fontSize,
            scale: scale,
            renderResult: renderResult
        )
        
        return TextCreationResult(
            shapes: renderResult.shapes,
            metrics: metrics
        )
    }
    
    // MARK: - Available Fonts
    
    /// Get all available system font names.
    ///
    /// - Returns: Array of font names sorted alphabetically.
    ///           At minimum includes: Helvetica, Georgia, Courier New,
    ///           Times New Roman, Arial, Verdana, Palatino, Garamond.
    public static func getAvailableFonts() -> [String] {
        TextRenderer.availableFonts()
    }
    
    // MARK: - Text Metrics Computation
    
    /// Compute text metrics from rendering result.
    /// Metrics are derived from the rendered shapes' bounding box.
    private static func computeMetrics(
        text: String,
        font: String,
        fontSize: Double,
        scale: Double,
        renderResult: TextRenderResult
    ) -> TextMetrics {
        
        // Compute bounding box from shapes
        let shapes = renderResult.shapes
        let bb: Rect
        if !shapes.isEmpty {
            let xs = shapes.map { $0.boundingRect.minX }
            let ys = shapes.map { $0.boundingRect.minY }
            let xe = shapes.map { $0.boundingRect.maxX }
            let ye = shapes.map { $0.boundingRect.maxY }
            bb = Rect(
                minX: xs.min()!, minY: ys.min()!,
                maxX: xe.max()!, maxY: ye.max()!
            )
        } else {
            bb = Rect()
        }
        
        // Estimate ascent/descent from bounding box
        let totalHeight = bb.height
        let ascent = totalHeight * 0.7  // Typical ratio
        let descent = totalHeight * 0.3
        
        // Total advance is the width of the rendered text
        let totalAdvance = bb.width
        
        return TextMetrics(
            totalAdvance: totalAdvance,
            ascent: ascent,
            descent: descent,
            boundingBox: bb,
            glyphCount: shapes.count
        )
    }
    
    // MARK: - Convenience: Center Text
    
    /// Create text and center it at the origin.
    ///
    /// - Parameters:
    ///   - text: The text string to render.
    ///   - font: Font name.
    ///   - fontSize: Font size in points.
    ///   - scale: Scale factor.
    /// - Returns: TextCreationResult with shapes translated so bounding box center is at (0, 0).
    public static func createCenteredText(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> TextCreationResult {
        let result = createText(text: text, font: font, fontSize: fontSize, scale: scale)
        
        guard !result.shapes.isEmpty else { return result }
        
        // Compute bounding box center
        let bb = result.boundingRect
        let cx = (bb.minX + bb.maxX) / 2.0
        let cy = (bb.minY + bb.maxY) / 2.0
        
        // Translate all shapes so center is at origin
        let centeredShapes = result.shapes.map { $0.translated(by: -cx, -cy) }
        
        return TextCreationResult(
            shapes: centeredShapes,
            metrics: result.metrics
        )
    }
    
    // MARK: - Convenience: Text on Line
    
    /// Create text positioned along a horizontal line at the given Y coordinate.
    ///
    /// - Parameters:
    ///   - text: The text string to render.
    ///   - font: Font name.
    ///   - fontSize: Font size in points.
    ///   - scale: Scale factor.
    ///   - baselineY: Y coordinate for the text baseline (default: 0).
    /// - Returns: TextCreationResult with shapes translated to the specified baseline.
    public static func createTextAtBaseline(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0,
        baselineY: Double = 0.0
    ) -> TextCreationResult {
        let result = createText(text: text, font: font, fontSize: fontSize, scale: scale)
        
        guard !result.shapes.isEmpty else { return result }
        
        // Shift shapes so baseline (y=0 in CoreText coords) aligns with baselineY
        // CoreText renders with y=0 at baseline, so we just translate by baselineY
        let shiftedShapes = result.shapes.map { $0.translated(by: 0, baselineY) }
        
        return TextCreationResult(
            shapes: shiftedShapes,
            metrics: result.metrics
        )
    }
    
    // MARK: - Text to Curves (SPK-0501)
    
    /// Convert text to individual editable vector curves — one VectorShape per glyph.
    ///
    /// Each glyph is returned as a separate `VectorShape.freehand` that can be independently
    /// scaled, rotated, or offset. This is essential for V-Carve engraving where individual
    /// letterforms must be manipulated separately.
    ///
    /// - Parameters:
    ///   - text: The text string to convert.
    ///   - font: Font name (e.g. "Helvetica", "Georgia", "Courier New").
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor to apply to all coordinates.
    ///            1.0 = 1 point = 1 unit. Use >1 to enlarge, <1 to shrink.
    /// - Returns: Array of individual VectorShape objects, one per glyph in the input text.
    ///           Each shape is a `VectorShape.freehand` with points suitable for CNC toolpaths.
    ///
    /// - Note: Returns an empty array for empty or whitespace-only text.
    ///         Spaces and unrenderable characters produce empty GlyphCurve entries.
    public static func convertToCurves(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> [VectorShape] {
        let curvesResult = TextRenderer.textToCurves(
            text: text,
            fontName: font,
            fontSize: fontSize,
            scale: scale
        )
        
        return curvesResult.glyphs.map { $0.shape }
    }
    
    /// Convert text to individual editable vector curves with metadata.
    ///
    /// Like `convertToCurves(text:font:fontSize:scale:)` but returns full `GlyphCurve`
    /// objects with character identity, position, and advance information.
    ///
    /// - Parameters:
    ///   - text: The text string to convert.
    ///   - font: Font name.
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor to apply to all coordinates.
    /// - Returns: TextCurvesResult with individual glyph curves and metrics.
    public static func convertToCurvesDetailed(
        text: String,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0
    ) -> TextCurvesResult {
        TextRenderer.textToCurves(
            text: text,
            fontName: font,
            fontSize: fontSize,
            scale: scale
        )
    }
    
    // MARK: - Text on Curve (SPK-0502)
    
    /// Place text along a curved path — each character rotated to follow the curve tangent.
    ///
    /// Essential for sign making: curved text on circular signs, arched entrances,
    /// freehand curves, etc.
    ///
    /// - Parameters:
    ///   - text: The text string to place on the curve.
    ///   - curvePoints: The curve path as an array of points (minimum 2 points).
    ///   - font: Font name (e.g. "Helvetica", "Georgia", "Courier New").
    ///   - fontSize: Font size in points (default: 72).
    ///   - scale: Scale factor to apply to all coordinates.
    ///   - offset: Fractional offset along the curve (0.0 = start, 1.0 = end).
    ///   - letterSpacing: Extra spacing between characters in points (default: 0).
    /// - Returns: Array of VectorShape, one per glyph, positioned and rotated along the curve.
    ///           Each shape is a `VectorShape.freehand` with points suitable for CNC toolpaths.
    ///
    /// - Note: Returns an empty array for empty or whitespace-only text.
    ///         Spaces and unrenderable characters produce empty GlyphCurve entries.
    public static func textOnCurve(
        text: String,
        curvePoints: [VectorPoint],
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0,
        offset: Double = 0.5,
        letterSpacing: Double = 0.0
    ) -> [VectorShape] {
        
        // Validate input
        guard !text.isEmpty, !text.trimmingCharacters(in: .whitespaces).isEmpty,
              curvePoints.count >= 2 else {
            return []
        }
        
        // Step 1: Get individual glyph shapes from CoreText
        let curvesResult = TextRenderer.textToCurves(
            text: text,
            fontName: font,
            fontSize: fontSize,
            scale: scale
        )
        
        guard !curvesResult.glyphs.isEmpty else { return [] }
        
        // Step 2: Sample the curve to get positions and tangents
        let curveSamples = sampleCurve(points: curvePoints, numSamples: 100)
        
        // Step 3: Calculate total curve length
        let totalLength = curveLength(curveSamples)
        
        // Step 4: For each character, find its position on the curve
        let glyphShapes = curvesResult.glyphs
        
        var placedShapes: [VectorShape] = []
        var currentDistance: Double = 0.0
        
        // Center offset: shift the text so it's centered on the offset point
        let totalTextWidth = curvesResult.totalWidth
        let startOffset = (totalTextWidth / 2.0) - (totalLength * offset)
        
        for glyph in glyphShapes {
            guard !glyph.shape.points.isEmpty else { continue }
            
            // Find position on curve for this character
            let charCenter = currentDistance + startOffset + (glyph.advance / 2.0)
            
            // Get point and tangent at this position
            let (point, tangent) = pointAtDistance(curveSamples: curveSamples, distance: charCenter)
            
            // Calculate rotation angle from tangent
            let angle = atan2(tangent.y, tangent.x)
            
            // Translate glyph to origin
            let glyphBB = glyph.shape.boundingRect
            let glyphCenter = VectorPoint(
                x: (glyphBB.minX + glyphBB.maxX) / 2.0,
                y: (glyphBB.minY + glyphBB.maxY) / 2.0
            )
            
            let centeredShape = glyph.shape.translated(by: -glyphCenter.x, -glyphCenter.y)
            
            // Rotate in place (about the glyph center at origin) to follow the
            // curve tangent, THEN translate to the curve point. Rotating about
            // the ORIGIN after translation swings the glyph by its distance
            // from (0,0) — for arcs far from the origin (e.g. a sign arc at
            // sheet center) every glyph lands hundreds of mm off-stock
            // (caught by the SPK-1106b E2E sheet-bounds check).
            let rotatedShape = rotateShape(centeredShape, angle: angle, about: VectorPoint(x: 0, y: 0))
            let translatedShape = rotatedShape.translated(by: point.x, point.y)
            
            placedShapes.append(translatedShape)
            
            // Advance to next character
            currentDistance += glyph.advance + letterSpacing
        }
        
        return placedShapes
    }
    
    // MARK: - Text on Arc (convenience)
    
    /// Place text along a circular arc.
    ///
    /// - Parameters:
    ///   - text: The text string to place on the arc.
    ///   - center: Center of the arc.
    ///   - radius: Radius of the arc.
    ///   - startAngle: Start angle in radians.
    ///   - endAngle: End angle in radians.
    ///   - font: Font name.
    ///   - fontSize: Font size in points.
    ///   - scale: Scale factor.
    ///   - letterSpacing: Extra spacing between characters.
    /// - Returns: Array of VectorShape, one per glyph, positioned along the arc.
    public static func textOnArc(
        text: String,
        center: VectorPoint,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        font: String = "Helvetica Neue",
        fontSize: Double = 72.0,
        scale: Double = 1.0,
        letterSpacing: Double = 0.0
    ) -> [VectorShape] {
        
        // Create an arc point list
        let arcPts = arcPoints(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, segments: 100)
        
        return textOnCurve(
            text: text,
            curvePoints: arcPts,
            font: font,
            fontSize: fontSize,
            scale: scale,
            offset: 0.5,
            letterSpacing: letterSpacing
        )
    }
    
    // MARK: - Helpers
    
    /// Sample a curve path into discrete points with tangents.
    private static func sampleCurve(points: [VectorPoint], numSamples: Int) -> [(point: VectorPoint, tangent: VectorPoint)] {
        guard points.count >= 2 else { return [] }
        
        var samples: [(point: VectorPoint, tangent: VectorPoint)] = []
        
        // For each segment, compute points and tangents
        for i in 0..<points.count - 1 {
            let p0 = points[i]
            let p1 = points[i + 1]
            
            // Tangent is the direction of the segment
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-9 else { continue }
            
            let tangent = VectorPoint(x: dx / len, y: dy / len)
            
            // Sample evenly along this segment
            let samplesPerSegment = max(1, numSamples / (points.count - 1))
            for j in 0..<samplesPerSegment {
                let t = Double(j) / Double(samplesPerSegment)
                let x = p0.x + dx * t
                let y = p0.y + dy * t
                samples.append((VectorPoint(x: x, y: y), tangent))
            }
        }
        
        // If we got fewer samples than requested, pad with the last point
        while samples.count < numSamples {
            if let last = samples.last {
                samples.append(last)
            } else {
                break
            }
        }
        
        return samples
    }
    
    /// Compute total curve length from samples.
    private static func curveLength(_ samples: [(point: VectorPoint, tangent: VectorPoint)]) -> Double {
        var total: Double = 0.0
        for i in 1..<samples.count {
            let dx = samples[i].point.x - samples[i-1].point.x
            let dy = samples[i].point.y - samples[i-1].point.y
            let len = (dx * dx + dy * dy).squareRoot()
            total += len
        }
        return total
    }
    
    /// Get point and tangent at a given distance along the curve.
    private static func pointAtDistance(
        curveSamples: [(point: VectorPoint, tangent: VectorPoint)],
        distance: Double
    ) -> (point: VectorPoint, tangent: VectorPoint) {
        
        guard !curveSamples.isEmpty else {
            return (VectorPoint(), VectorPoint())
        }
        
        // Compute cumulative distances
        var cumulativeDistances: [Double] = [0.0]
        for i in 1..<curveSamples.count {
            let dx = curveSamples[i].point.x - curveSamples[i-1].point.x
            let dy = curveSamples[i].point.y - curveSamples[i-1].point.y
            let len = (dx * dx + dy * dy).squareRoot()
            cumulativeDistances.append(cumulativeDistances[i-1] + len)
        }
        
        let totalLength = cumulativeDistances.last ?? 0.0
        
        // Clamp distance to curve bounds
        let clampedDistance = max(0, min(distance, totalLength))
        
        // Find the segment containing this distance
        for i in 1..<cumulativeDistances.count {
            if cumulativeDistances[i] >= clampedDistance {
                let segStart = cumulativeDistances[i-1]
                let segEnd = cumulativeDistances[i]
                let segLen = segEnd - segStart
                let t = segLen > 1e-9 ? (clampedDistance - segStart) / segLen : 0
                
                let p0 = curveSamples[i-1].point
                let p1 = curveSamples[i].point
                
                let x = p0.x + (p1.x - p0.x) * t
                let y = p0.y + (p1.y - p0.y) * t
                
                // Use the tangent from the segment
                let tangent = curveSamples[i].tangent
                
                return (VectorPoint(x: x, y: y), tangent)
            }
        }
        
        // Fallback: return last sample
        let last = curveSamples.last!
        return (last.point, last.tangent)
    }
    
    /// Rotate a VectorShape around a center point by an angle in radians.
    private static func rotateShape(
        _ shape: VectorShape,
        angle: Double,
        about center: VectorPoint
    ) -> VectorShape {
        switch shape {
        case .line(let start, let end):
            let newStart = rotatePoint(start, around: center, by: angle)
            let newEnd = rotatePoint(end, around: center, by: angle)
            return .line(start: newStart, end: newEnd)
        case .circle(let c, let r):
            let newCenter = rotatePoint(c, around: center, by: angle)
            return .circle(center: newCenter, radius: r)
        case .rectangle(let o, let w, let h):
            let newOrigin = rotatePoint(o, around: center, by: angle)
            return .rectangle(origin: newOrigin, width: w, height: h)
        case .arc(let c, let r, let sa, let ea):
            let newCenter = rotatePoint(c, around: center, by: angle)
            return .arc(center: newCenter, radius: r, startAngle: sa + angle, endAngle: ea + angle)
        case .ellipse(let c, let rx, let ry, let rot):
            let newCenter = rotatePoint(c, around: center, by: angle)
            return .ellipse(center: newCenter, radiusX: rx, radiusY: ry, rotation: rot + angle)
        case .polygon(let c, let r, let s, let rot):
            let newCenter = rotatePoint(c, around: center, by: angle)
            return .polygon(center: newCenter, radius: r, sides: s, rotation: rot + angle)
        case .star(let c, let or, let ir, let p, let rot):
            let newCenter = rotatePoint(c, around: center, by: angle)
            return .star(center: newCenter, outerRadius: or, innerRadius: ir, points: p, rotation: rot + angle)
        case .freehand(let points):
            return .freehand(points: points.map { rotatePoint($0, around: center, by: angle) })
        }
    }
    
    /// Rotate a single point around a center.
    private static func rotatePoint(_ point: VectorPoint, around center: VectorPoint, by angle: Double) -> VectorPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        return VectorPoint(
            x: center.x + (dx * cosA - dy * sinA),
            y: center.y + (dx * sinA + dy * cosA)
        )
    }
    
    /// Generate points along a circular arc.
    private static func arcPoints(
        center: VectorPoint,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        segments: Int
    ) -> [VectorPoint] {
        var points: [VectorPoint] = []
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let angle = startAngle + (endAngle - startAngle) * t
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            points.append(VectorPoint(x: x, y: y))
        }
        return points
    }
}
