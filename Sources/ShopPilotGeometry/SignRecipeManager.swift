import Foundation
import ShopPilotCore

// MARK: - Sign Recipe Manager

/// Creates a sign job from a recipe selection, pre-wiring text-on-curve,
/// decorative border, and V-Carve toolpath for a complete sign-making workflow.
public enum SignRecipeManager {

    // MARK: - Create Sign Job

    /// Create a complete sign job from the signage recipe.
    public static func createSignJob(
        jobName: String = "Sign Job",
        text: String = "SHOP",
        font: String = "Helvetica Neue",
        fontSize: Double = 48.0,
        scale: Double = 1.0,
        vBitAngle: Double = 90.0,
        vCarveDepth: Double = 0.5,
        feedRate: Double = 1000.0
    ) -> ShopPilotCore.Job {
        let recipe = JobRecipe(
            name: "Signage",
            description: "Single-face sign with lettering and decorative graphics.",
            icon: "textformat.abc",
            stockWidth: 457.2,
            stockDepth: 609.6,
            stockHeight: 19.05,
            recommendedStrategy: "Profile + V-Carve lettering"
        )

        // Create the sheet with sign dimensions
        var sheet = ShopPilotCore.Sheet(
            name: "Sign Sheet",
            width: recipe.stockWidth,
            depth: recipe.stockDepth,
            height: recipe.stockHeight
        )
        sheet.material = ShopPilotCore.MaterialDatabase.shared.lookup(byName: "MDF")

        // Layer 1: Text-on-curve
        var textLayer = ShopPilotCore.Layer(name: "Text")
        let textShapes = TextTool.textOnCurve(
            text: text,
            curvePoints: arcPoints(center: VectorPoint(x: recipe.stockWidth / 2, y: recipe.stockDepth / 2 + 50),
                                   radius: 120,
                                   startAngle: -0.8,
                                   endAngle: 0.8,
                                   segments: 50),
            font: font,
            fontSize: fontSize,
            scale: scale,
            offset: 0.5,
            letterSpacing: 0.0
        )
        for (idx, shape) in textShapes.enumerated() {
            let points = shape.points.map { ShopPilotCore.VectorPoint(x: $0.x, y: $0.y) }
            var path = ShopPilotCore.VectorPath(
                name: "Glyph \(idx + 1)",
                points: points,
                isClosed: false,
                layerId: textLayer.id
            )
            if idx < text.count {
                let charIndex = text.index(text.startIndex, offsetBy: min(idx, text.count - 1))
                path.name = "Glyph \(text[charIndex])"
            }
            textLayer.addVector(path)
        }
        sheet.addLayer(textLayer)

        // Layer 2: Decorative border
        var borderLayer = ShopPilotCore.Layer(name: "Border")
        // Border is drawn centered on the origin — translate it into the stock
        // (sheet coordinates span 0..width × 0..depth), leaving a 20mm margin.
        let border = createDecorativeBorder(width: recipe.stockWidth - 40, height: recipe.stockDepth - 40)
        var borderInStock = border
        borderInStock.points = border.points.map {
            ShopPilotCore.VectorPoint(
                x: $0.x + recipe.stockWidth / 2,
                y: $0.y + recipe.stockDepth / 2
            )
        }
        borderLayer.addVector(borderInStock)
        sheet.addLayer(borderLayer)

        // Create the job
        var job = ShopPilotCore.Job(name: jobName)
        job.addSheet(sheet)

        // Pre-calculate V-Carve toolpath for text vectors
        let textVectors = textLayer.vectors
        guard !textVectors.isEmpty else { return job }

        var vectorDepths: [UUID: Double] = [:]
        for vec in textVectors {
            vectorDepths[vec.id] = vCarveDepth
        }

        let vcParams = ShopPilotCore.VCarveParams(
            vBitAngleDegrees: vBitAngle,
            feedRateMmPerMin: feedRate,
            plungeFeedRateMmPerMin: 300,
            maxDepthOfCutMm: vCarveDepth,
            leadInDistanceMm: 5.0,
            leadOutDistanceMm: 5.0,
            stepOverMm: 1.0,
            flatBottomMode: false,
            vectorDepths: vectorDepths
        )

        let vcResult = VCarveEngine.compute(
            vectors: textVectors,
            params: vcParams,
            stockHeightMm: recipe.stockHeight
        )

        job.vcarvePasses = vcResult.passCount
        job.vcarveTimeSeconds = vcResult.estimatedTimeSeconds

        return job
    }

    // MARK: - Decorative Border

    private static func createDecorativeBorder(width: Double, height: Double, cornerRadius: Double = 10.0) -> ShopPilotCore.VectorPath {
        let halfW = width / 2.0
        let halfH = height / 2.0
        let segments = 16
        var points: [ShopPilotCore.VectorPoint] = []

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let x = -halfW + cornerRadius + (width - 2 * cornerRadius) * t
            let y = halfH - cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 1...segments {
            let angle = -Double.pi / 2.0 * Double(i) / Double(segments)
            let x = cornerRadius * cos(angle)
            let y = cornerRadius * sin(angle) + halfH - cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let x = halfW - cornerRadius
            let y = halfH - cornerRadius - (height - 2 * cornerRadius) * t
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 1...segments {
            let angle = Double.pi / 2.0 + Double.pi / 2.0 * Double(i) / Double(segments)
            let x = cornerRadius * cos(angle)
            let y = cornerRadius * sin(angle) - halfH + cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let x = halfW - cornerRadius - (width - 2 * cornerRadius) * t
            let y = -halfH + cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 1...segments {
            let angle = Double.pi + Double.pi / 2.0 * Double(i) / Double(segments)
            let x = cornerRadius * cos(angle)
            let y = cornerRadius * sin(angle) - halfH + cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let x = -halfW + cornerRadius
            let y = -halfH + cornerRadius + (height - 2 * cornerRadius) * t
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        for i in 1...segments {
            let angle = 3.0 * Double.pi / 2.0 + Double.pi / 2.0 * Double(i) / Double(segments)
            let x = cornerRadius * cos(angle)
            let y = cornerRadius * sin(angle) + halfH - cornerRadius
            points.append(ShopPilotCore.VectorPoint(x: x, y: y))
        }

        points.append(points.first!)

        return ShopPilotCore.VectorPath(
            name: "Decorative Border",
            points: points,
            isClosed: true,
            layerId: UUID()
        )
    }

    // MARK: - Arc Helpers

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
