import Foundation

// MARK: - Tiling Manager

// Tiling direction.
public enum TilingDirection: String, Codable, Sendable {
    case horizontal
    case vertical
    case both
}

// Tiling alignment.
public enum TilingAlignment: String, Codable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

// Tiling gap type.
public enum TilingGap: String, Codable, Sendable {
    case none
    case fixed
    case percentage
}

// Tiling configuration.
public struct TilingConfig: Codable, Sendable {
    public var tilesPerRow: Int
    public var tilesPerColumn: Int
    public var tileWidth: Double
    public var tileHeight: Double
    public var tileGap: Double
    public var gapType: TilingGap
    public var direction: TilingDirection
    public var alignment: TilingAlignment
    public var originX: Double
    public var originY: Double
    public var rotation: Double
    public var mirrorHorizontal: Bool
    public var mirrorVertical: Bool
    public var stagger: Bool
    public var staggerAmount: Double
    
    public init(
        tilesPerRow: Int = 2,
        tilesPerColumn: Int = 2,
        tileWidth: Double = 100.0,
        tileHeight: Double = 100.0,
        tileGap: Double = 5.0,
        gapType: TilingGap = .fixed,
        direction: TilingDirection = .both,
        alignment: TilingAlignment = .center,
        originX: Double = 0.0,
        originY: Double = 0.0,
        rotation: Double = 0.0,
        mirrorHorizontal: Bool = false,
        mirrorVertical: Bool = false,
        stagger: Bool = false,
        staggerAmount: Double = 0.0
    ) {
        self.tilesPerRow = max(1, tilesPerRow)
        self.tilesPerColumn = max(1, tilesPerColumn)
        self.tileWidth = max(0.1, tileWidth)
        self.tileHeight = max(0.1, tileHeight)
        self.tileGap = max(0.0, tileGap)
        self.gapType = gapType
        self.direction = direction
        self.alignment = alignment
        self.originX = originX
        self.originY = originY
        self.rotation = rotation
        self.mirrorHorizontal = mirrorHorizontal
        self.mirrorVertical = mirrorVertical
        self.stagger = stagger
        self.staggerAmount = staggerAmount
    }
}

// A single tile in a tiling layout.
public struct TilingTile: Codable, Sendable {
    public var id: UUID
    public var row: Int
    public var column: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var mirroredX: Bool
    public var mirroredY: Bool
    public var placed: Bool
    
    public init(
        id: UUID = UUID(),
        row: Int = 0,
        column: Int = 0,
        x: Double = 0.0,
        y: Double = 0.0,
        width: Double = 100.0,
        height: Double = 100.0,
        rotation: Double = 0.0,
        mirroredX: Bool = false,
        mirroredY: Bool = false,
        placed: Bool = false
    ) {
        self.id = id
        self.row = row
        self.column = column
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.mirroredX = mirroredX
        self.mirroredY = mirroredY
        self.placed = placed
    }
}

// Tiling result.
public struct TilingResult: Codable, Sendable {
    public var config: TilingConfig
    public var tiles: [TilingTile]
    public var totalTiles: Int
    public var placedTiles: Int
    public var sheetWidth: Double
    public var sheetHeight: Double
    public var boundingBox: BoundingBox3D
    public var success: Bool
    public var errorMessage: String?
    
    public init(
        config: TilingConfig,
        tiles: [TilingTile],
        totalTiles: Int,
        placedTiles: Int,
        sheetWidth: Double,
        sheetHeight: Double,
        boundingBox: BoundingBox3D,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.config = config
        self.tiles = tiles
        self.totalTiles = totalTiles
        self.placedTiles = placedTiles
        self.sheetWidth = sheetWidth
        self.sheetHeight = sheetHeight
        self.boundingBox = boundingBox
        self.success = success
        self.errorMessage = errorMessage
    }
}

// MARK: - TilingManager

// Manages tiling layout generation for jobs.
public final class TilingManager: ObservableObject {
    @Published public var configurations: [TilingConfig]
    @Published public var activeConfigID: UUID?
    
    public init() {
        self.configurations = []
        self.activeConfigID = nil
    }
    
    // Creates a new tiling configuration.
    @discardableResult
    public func addConfig(
        tilesPerRow: Int = 2,
        tilesPerColumn: Int = 2,
        tileWidth: Double = 100.0,
        tileHeight: Double = 100.0,
        tileGap: Double = 5.0,
        gapType: TilingGap = .fixed,
        direction: TilingDirection = .both,
        alignment: TilingAlignment = .center,
        originX: Double = 0.0,
        originY: Double = 0.0,
        rotation: Double = 0.0,
        mirrorHorizontal: Bool = false,
        mirrorVertical: Bool = false,
        stagger: Bool = false,
        staggerAmount: Double = 0.0
    ) -> TilingConfig {
        let config = TilingConfig(
            tilesPerRow: tilesPerRow,
            tilesPerColumn: tilesPerColumn,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            tileGap: tileGap,
            gapType: gapType,
            direction: direction,
            alignment: alignment,
            originX: originX,
            originY: originY,
            rotation: rotation,
            mirrorHorizontal: mirrorHorizontal,
            mirrorVertical: mirrorVertical,
            stagger: stagger,
            staggerAmount: staggerAmount
        )
        configurations.append(config)
        activeConfigID = UUID() // placeholder
        return config
    }
    
    // Removes a tiling configuration.
    public func removeConfig(at index: Int) {
        guard index < configurations.count else { return }
        configurations.remove(at: index)
    }
    
    // Generates tiling layout for a sheet.
    public func generateLayout(
        config: TilingConfig,
        sheetWidth: Double,
        sheetHeight: Double
    ) -> TilingResult {
        // Validate
        if config.tilesPerRow < 1 || config.tilesPerColumn < 1 {
            return TilingResult(
                config: config,
                tiles: [],
                totalTiles: 0,
                placedTiles: 0,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                boundingBox: BoundingBox3D(),
                success: false,
                errorMessage: "Tiles per row and column must be at least 1"
            )
        }
        
        let totalTiles = config.tilesPerRow * config.tilesPerColumn
        var tiles: [TilingTile] = []
        var placedTiles = 0
        
        // Calculate effective tile size including gap
        let effectiveWidth: Double
        let effectiveHeight: Double
        
        switch config.gapType {
        case .fixed:
            effectiveWidth = config.tileWidth + config.tileGap
            effectiveHeight = config.tileHeight + config.tileGap
        case .percentage:
            effectiveWidth = config.tileWidth * (1.0 + config.tileGap / 100.0)
            effectiveHeight = config.tileHeight * (1.0 + config.tileGap / 100.0)
        case .none:
            effectiveWidth = config.tileWidth
            effectiveHeight = config.tileHeight
        }
        
        // Calculate alignment offset
        let totalWidth = Double(config.tilesPerRow) * effectiveWidth - config.tileGap
        let totalHeight = Double(config.tilesPerColumn) * effectiveHeight - config.tileGap
        
        var offsetX = config.originX
        var offsetY = config.originY
        
        switch config.alignment {
        case .topLeft:
            offsetX = config.originX
            offsetY = config.originY
        case .topCenter:
            offsetX = config.originX + (sheetWidth - totalWidth) / 2
            offsetY = config.originY
        case .topRight:
            offsetX = config.originX + sheetWidth - totalWidth
            offsetY = config.originY
        case .centerLeft:
            offsetX = config.originX
            offsetY = config.originY + (sheetHeight - totalHeight) / 2
        case .center:
            offsetX = config.originX + (sheetWidth - totalWidth) / 2
            offsetY = config.originY + (sheetHeight - totalHeight) / 2
        case .centerRight:
            offsetX = config.originX + sheetWidth - totalWidth
            offsetY = config.originY + (sheetHeight - totalHeight) / 2
        case .bottomLeft:
            offsetX = config.originX
            offsetY = config.originY + sheetHeight - totalHeight
        case .bottomCenter:
            offsetX = config.originX + (sheetWidth - totalWidth) / 2
            offsetY = config.originY + sheetHeight - totalHeight
        case .bottomRight:
            offsetX = config.originX + sheetWidth - totalWidth
            offsetY = config.originY + sheetHeight - totalHeight
        }
        
        // Generate tile positions
        for row in 0..<config.tilesPerColumn {
            for col in 0..<config.tilesPerRow {
                let tileID = UUID()
                var tileX = offsetX + Double(col) * effectiveWidth
                var tileY = offsetY + Double(row) * effectiveHeight
                
                // Apply staggering
                if config.stagger && row % 2 == 1 {
                    tileX += config.staggerAmount
                }
                
                let tile = TilingTile(
                    id: tileID,
                    row: row,
                    column: col,
                    x: tileX,
                    y: tileY,
                    width: config.tileWidth,
                    height: config.tileHeight,
                    rotation: config.rotation,
                    mirroredX: config.mirrorHorizontal && (config.stagger && row % 2 == 1),
                    mirroredY: config.mirrorVertical && (config.stagger && row % 2 == 0),
                    placed: true
                )
                tiles.append(tile)
                placedTiles += 1
            }
        }
        
        // Calculate bounding box
        guard let firstTile = tiles.first(where: { $0.placed }) else {
            var minX: Double = 0, minY: Double = 0, maxX: Double = 0, maxY: Double = 0
            let boundingBox = BoundingBox3D(minX: minX, minY: minY, minZ: 0, maxX: maxX, maxY: maxY, maxZ: 0)
            return TilingResult(
                config: config,
                tiles: tiles,
                totalTiles: totalTiles,
                placedTiles: placedTiles,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                boundingBox: boundingBox,
                success: true
            )
        }
        var minX = firstTile.x, minY = firstTile.y, maxX = firstTile.x + firstTile.width, maxY = firstTile.y + firstTile.height
        for tile in tiles where tile.placed {
            minX = min(minX, tile.x)
            minY = min(minY, tile.y)
            maxX = max(maxX, tile.x + tile.width)
            maxY = max(maxY, tile.y + tile.height)
        }
        
        let boundingBox = BoundingBox3D(
            minX: minX, minY: minY, minZ: 0,
            maxX: maxX, maxY: maxY, maxZ: 0
        )
        
        return TilingResult(
            config: config,
            tiles: tiles,
            totalTiles: totalTiles,
            placedTiles: placedTiles,
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            boundingBox: boundingBox,
            success: true
        )
    }
    
    // Validates tiling configuration.
    public static func validate(_ config: TilingConfig) -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if config.tilesPerRow < 1 { errors.append("Tiles per row must be at least 1") }
        if config.tilesPerColumn < 1 { errors.append("Tiles per column must be at least 1") }
        if config.tileWidth <= 0 { errors.append("Tile width must be positive") }
        if config.tileHeight <= 0 { errors.append("Tile height must be positive") }
        if config.tileGap < 0 { errors.append("Tile gap cannot be negative") }
        if config.rotation < 0 || config.rotation > 360 { errors.append("Rotation must be 0-360") }
        
        return (errors.isEmpty, errors)
    }
    
    // Gets all configurations.
    public func getAllConfigs() -> [TilingConfig] {
        configurations
    }
    
    // Clears all configurations.
    public func clearAll() {
        configurations.removeAll()
        activeConfigID = nil
    }
}
