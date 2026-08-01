import Foundation

// MARK: - Nest Advanced

// Nesting strategy.
public enum NestingStrategy: String, Codable, Sendable {
    case guillotine
    case contour
    case hybrid
    case random
    case smart
}

// Part orientation.
public enum PartOrientation: String, Codable, Sendable {
    case fixed
    case rotate90
    case rotate45
    case free
}

// Grain direction for wood.
public enum GrainDirection: String, Codable, Sendable {
    case parallel
    case perpendicular
    case angle
    case any
}

// Nesting configuration.
public struct NestingConfig: Codable, Sendable {
    public var strategy: NestingStrategy
    public var partOrientation: PartOrientation
    public var grainDirection: GrainDirection
    public var grainAngle: Double
    public var minSpacing: Double
    public var maxParts: Int
    public var allowRotation: Bool
    public var allowFlip: Bool
    public var respectGrain: Bool
    public var optimizeForWaste: Bool
    
    public init(
        strategy: NestingStrategy = .smart,
        partOrientation: PartOrientation = .rotate90,
        grainDirection: GrainDirection = .parallel,
        grainAngle: Double = 0.0,
        minSpacing: Double = 3.0,
        maxParts: Int = 100,
        allowRotation: Bool = true,
        allowFlip: Bool = false,
        respectGrain: Bool = false,
        optimizeForWaste: Bool = true
    ) {
        self.strategy = strategy
        self.partOrientation = partOrientation
        self.grainDirection = grainDirection
        self.grainAngle = max(0.0, min(360.0, grainAngle))
        self.minSpacing = max(0.0, minSpacing)
        self.maxParts = max(1, maxParts)
        self.allowRotation = allowRotation
        self.allowFlip = allowFlip
        self.respectGrain = respectGrain
        self.optimizeForWaste = optimizeForWaste
    }
}

// A part to be nested.
public struct NestedPart: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var flipped: Bool
    public var x: Double
    public var y: Double
    public var placed: Bool
    
    public init(
        id: UUID = UUID(),
        name: String = "Part",
        width: Double = 100.0,
        height: Double = 50.0,
        rotation: Double = 0.0,
        flipped: Bool = false,
        x: Double = 0.0,
        y: Double = 0.0,
        placed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.width = max(0.1, width)
        self.height = max(0.1, height)
        self.rotation = rotation
        self.flipped = flipped
        self.x = x
        self.y = y
        self.placed = placed
    }
}

// Nesting result.
public struct NestingResult: Codable, Sendable {
    public var config: NestingConfig
    public var sheetWidth: Double
    public var sheetHeight: Double
    public var parts: [NestedPart]
    public var placedCount: Int
    public var unplacedCount: Int
    public var utilization: Double
    public var wasteArea: Double
    public var totalArea: Double
    public var usedArea: Double
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: NestingConfig,
        sheetWidth: Double,
        sheetHeight: Double,
        parts: [NestedPart],
        placedCount: Int,
        unplacedCount: Int,
        utilization: Double,
        wasteArea: Double,
        totalArea: Double,
        usedArea: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.sheetWidth = sheetWidth
        self.sheetHeight = sheetHeight
        self.parts = parts
        self.placedCount = placedCount
        self.unplacedCount = unplacedCount
        self.utilization = max(0.0, min(100.0, utilization))
        self.wasteArea = wasteArea
        self.totalArea = totalArea
        self.usedArea = usedArea
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - NestingEngine

// Performs advanced part nesting on a sheet.
public final class NestingEngine {
    
    // Runs a nesting operation.
    public static func nest(
        parts: [NestedPart],
        config: NestingConfig,
        sheetWidth: Double,
        sheetHeight: Double
    ) -> NestingResult {
        // Validate
        if parts.isEmpty {
            return NestingResult(
                config: config,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                parts: [],
                placedCount: 0,
                unplacedCount: 0,
                utilization: 0,
                wasteArea: sheetWidth * sheetHeight,
                totalArea: sheetWidth * sheetHeight,
                usedArea: 0,
                success: false,
                errorMessage: "No parts to nest"
            )
        }
        
        if sheetWidth <= 0 || sheetHeight <= 0 {
            return NestingResult(
                config: config,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                parts: [],
                placedCount: 0,
                unplacedCount: parts.count,
                utilization: 0,
                wasteArea: 0,
                totalArea: 0,
                usedArea: 0,
                success: false,
                errorMessage: "Sheet dimensions must be positive"
            )
        }
        
        let totalSheetArea = sheetWidth * sheetHeight
        var placedParts = parts
        var placedCount = 0
        
        // Simple placement algorithm based on strategy
        switch config.strategy {
        case .guillotine:
            placedParts = guillotineNest(parts: &placedParts, config: config, sheetWidth: sheetWidth, sheetHeight: sheetHeight)
        case .contour:
            placedParts = contourNest(parts: &placedParts, config: config, sheetWidth: sheetWidth, sheetHeight: sheetHeight)
        case .hybrid:
            placedParts = hybridNest(parts: &placedParts, config: config, sheetWidth: sheetWidth, sheetHeight: sheetHeight)
        case .random:
            placedParts = randomNest(parts: &placedParts, config: config, sheetWidth: sheetWidth, sheetHeight: sheetHeight)
        case .smart:
            placedParts = smartNest(parts: &placedParts, config: config, sheetWidth: sheetWidth, sheetHeight: sheetHeight)
        }
        
        placedCount = placedParts.filter { $0.placed }.count
        let unplacedCount = parts.count - placedCount
        
        // Calculate utilization
        var usedArea = 0.0
        for part in placedParts where part.placed {
            let w = part.flipped ? part.height : part.width
            let h = part.flipped ? part.width : part.height
            usedArea += w * h
        }
        
        let utilization = totalSheetArea > 0 ? (usedArea / totalSheetArea) * 100.0 : 0.0
        let wasteArea = totalSheetArea - usedArea
        
        return NestingResult(
            config: config,
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            parts: placedParts,
            placedCount: placedCount,
            unplacedCount: unplacedCount,
            utilization: utilization,
            wasteArea: wasteArea,
            totalArea: totalSheetArea,
            usedArea: usedArea,
            success: true
        )
    }
    
    // Guillotine-style nesting.
    private static func guillotineNest(parts: inout [NestedPart], config: NestingConfig, sheetWidth: Double, sheetHeight: Double) -> [NestedPart] {
        // Sort by area descending
        var sortedParts = parts.sorted { $0.width * $0.height > $1.width * $1.height }
        
        var y = 0.0
        var x = 0.0
        var currentRowHeight: Double = 0
        
        for i in sortedParts.indices {
            let part = sortedParts[i]
            let pw = part.flipped ? part.height : part.width
            let ph = part.flipped ? part.width : part.height
            
            // Try to place
            if x + pw <= sheetWidth && y + ph <= sheetHeight {
                sortedParts[i].x = x
                sortedParts[i].y = y
                sortedParts[i].placed = true
                x += pw + config.minSpacing
                currentRowHeight = max(currentRowHeight, ph)
            } else {
                // Move to next row
                x = 0.0
                y += currentRowHeight + config.minSpacing
                if y + ph <= sheetHeight && x + pw <= sheetWidth {
                    sortedParts[i].x = x
                    sortedParts[i].y = y
                    sortedParts[i].placed = true
                    x += pw + config.minSpacing
                }
                currentRowHeight = ph
            }
        }
        
        return sortedParts
    }
    
    // Contour-based nesting.
    private static func contourNest(parts: inout [NestedPart], config: NestingConfig, sheetWidth: Double, sheetHeight: Double) -> [NestedPart] {
        // Place parts in grid pattern
        var sortedParts = parts.sorted { $0.width * $0.height > $1.width * $1.height }
        
        var x: Double = 0
        var y: Double = 0
        var rowHeight: Double = 0
        
        for i in sortedParts.indices {
            let part = sortedParts[i]
            let pw = part.flipped ? part.height : part.width
            let ph = part.flipped ? part.width : part.height
            
            if x + pw <= sheetWidth && y + ph <= sheetHeight {
                sortedParts[i].x = x
                sortedParts[i].y = y
                sortedParts[i].placed = true
                x += pw + config.minSpacing
                rowHeight = max(rowHeight, ph)
            } else {
                x = 0
                y += rowHeight + config.minSpacing
                rowHeight = 0
                if y + ph <= sheetHeight && x + pw <= sheetWidth {
                    sortedParts[i].x = x
                    sortedParts[i].y = y
                    sortedParts[i].placed = true
                    x += pw + config.minSpacing
                }
                rowHeight = ph
            }
        }
        
        return sortedParts
    }
    
    // Hybrid nesting.
    private static func hybridNest(parts: inout [NestedPart], config: NestingConfig, sheetWidth: Double, sheetHeight: Double) -> [NestedPart] {
        // Try smart first, fall back to grid
        var sortedParts = parts.sorted { $0.width * $0.height > $1.width * $1.height }
        
        for i in sortedParts.indices {
            let part = sortedParts[i]
            let pw = part.flipped ? part.height : part.width
            let ph = part.flipped ? part.width : part.height
            
            if i == 0 {
                sortedParts[i].x = 0
                sortedParts[i].y = 0
                sortedParts[i].placed = true
            } else {
                // Simple placement
                var found = false
                for tryY in stride(from: 0, to: sheetHeight - ph, by: config.minSpacing) {
                    for tryX in stride(from: 0, to: sheetWidth - pw, by: config.minSpacing) {
                        var overlaps = false
                        for j in 0..<i where sortedParts[j].placed {
                            let jw = sortedParts[j].flipped ? sortedParts[j].height : sortedParts[j].width
                            let jh = sortedParts[j].flipped ? sortedParts[j].width : sortedParts[j].height
                            if !(tryX + pw <= sortedParts[j].x || tryX >= sortedParts[j].x + jw ||
                                  tryY + ph <= sortedParts[j].y || tryY >= sortedParts[j].y + jh) {
                                overlaps = true
                                break
                            }
                        }
                        if !overlaps {
                            sortedParts[i].x = tryX
                            sortedParts[i].y = tryY
                            sortedParts[i].placed = true
                            found = true
                            break
                        }
                    }
                    if found { break }
                }
            }
        }
        
        return sortedParts
    }
    
    // Random placement.
    private static func randomNest(parts: inout [NestedPart], config: NestingConfig, sheetWidth: Double, sheetHeight: Double) -> [NestedPart] {
        for i in parts.indices {
            let part = parts[i]
            let pw = part.flipped ? part.height : part.width
            let ph = part.flipped ? part.width : part.height
            
            if pw <= sheetWidth && ph <= sheetHeight {
                parts[i].x = Double.random(in: 0...(sheetWidth - pw))
                parts[i].y = Double.random(in: 0...(sheetHeight - ph))
                parts[i].placed = true
            }
        }
        
        return parts
    }
    
    // Smart placement.
    private static func smartNest(parts: inout [NestedPart], config: NestingConfig, sheetWidth: Double, sheetHeight: Double) -> [NestedPart] {
        // Sort by area descending, try best fit
        var sortedParts = parts.sorted { $0.width * $0.height > $1.width * $1.height }
        
        for i in sortedParts.indices {
            let part = sortedParts[i]
            let pw = part.flipped ? part.height : part.width
            let ph = part.flipped ? part.width : part.height
            
            if i == 0 {
                sortedParts[i].x = 0
                sortedParts[i].y = 0
                sortedParts[i].placed = true
            } else {
                var bestX: Double = 0
                var bestY: Double = 0
                var bestScore: Double = .infinity
                var found = false
                
                for tryY in stride(from: 0, to: sheetHeight - ph, by: config.minSpacing) {
                    for tryX in stride(from: 0, to: sheetWidth - pw, by: config.minSpacing) {
                        var overlaps = false
                        for j in 0..<i where sortedParts[j].placed {
                            let jw = sortedParts[j].flipped ? sortedParts[j].height : sortedParts[j].width
                            let jh = sortedParts[j].flipped ? sortedParts[j].width : sortedParts[j].height
                            if !(tryX + pw <= sortedParts[j].x || tryX >= sortedParts[j].x + jw ||
                                  tryY + ph <= sortedParts[j].y || tryY >= sortedParts[j].y + jh) {
                                overlaps = true
                                break
                            }
                        }
                        if !overlaps {
                            // Score: prefer bottom-left
                            let score = tryX + tryY
                            if score < bestScore {
                                bestScore = score
                                bestX = tryX
                                bestY = tryY
                            }
                            found = true
                        }
                    }
                    if found && bestY != 0 { break }
                }
                
                if found {
                    sortedParts[i].x = bestX
                    sortedParts[i].y = bestY
                    sortedParts[i].placed = true
                }
            }
        }
        
        return sortedParts
    }
    
    // Validates nesting configuration.
    public static func validate(_ config: NestingConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.minSpacing < 0 { errors.append("Min spacing cannot be negative") }
        if config.maxParts < 1 { errors.append("Max parts must be at least 1") }
        if config.grainAngle < 0 || config.grainAngle > 360 { errors.append("Grain angle must be 0-360") }
        
        return (errors.isEmpty, errors)
    }
}
