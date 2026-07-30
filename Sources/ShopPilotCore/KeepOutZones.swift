import Foundation

// MARK: - Keep-Out Zone Type

/// Types of keep-out zones that restrict toolpath generation.
public enum KeepOutZoneType: String, Codable, Sendable {
    /// Circular area to avoid.
    case circle
    /// Rectangular area to avoid.
    case rectangle
    /// Polygonal area to avoid (arbitrary shape).
    case polygon
    
    public var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        case .polygon: return "Polygon"
        }
    }
}

// MARK: - Keep-Out Zone

/// A zone that toolpaths must avoid during generation.
public struct KeepOutZone: Identifiable, Codable, Sendable {
    
    public let id = UUID()
    public var name: String
    public let type: KeepOutZoneType
    
    /// Circular keep-out zone center and radius.
    public var circleCenter: VectorPoint?
    public var circleRadiusMm: Double?
    
    /// Rectangular keep-out zone bounds.
    public var rectMinX: Double?
    public var rectMinY: Double?
    public var rectMaxX: Double?
    public var rectMaxY: Double?
    
    /// Polygonal keep-out zone boundary points.
    public var polygonPoints: [VectorPoint]?
    
    /// Whether this zone is active and should be enforced.
    public var isActive: Bool = true
    
    public init(
        name: String,
        type: KeepOutZoneType,
        circleCenter: VectorPoint? = nil,
        circleRadiusMm: Double? = nil,
        rectMinX: Double? = nil,
        rectMinY: Double? = nil,
        rectMaxX: Double? = nil,
        rectMaxY: Double? = nil,
        polygonPoints: [VectorPoint]? = nil
    ) {
        self.name = name
        self.type = type
        self.circleCenter = circleCenter
        self.circleRadiusMm = circleRadiusMm
        self.rectMinX = rectMinX
        self.rectMinY = rectMinY
        self.rectMaxX = rectMaxX
        self.rectMaxY = rectMaxY
        self.polygonPoints = polygonPoints
    }
    
    /// Check if a point is inside this keep-out zone.
    public func containsPoint(_ point: VectorPoint) -> Bool {
        guard isActive else { return false }
        
        switch type {
        case .circle:
            guard let center = circleCenter, let radius = circleRadiusMm else { return false }
            let dx = point.x - center.x
            let dy = point.y - center.y
            return (dx * dx + dy * dy) <= (radius * radius)
            
        case .rectangle:
            guard let minX = rectMinX, let minY = rectMinY,
                  let maxX = rectMaxX, let maxY = rectMaxY else { return false }
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
            
        case .polygon:
            guard let points = polygonPoints, !points.isEmpty else { return false }
            return isPointInPolygon(point, polygon: points)
        }
    }
    
    /// Check if a line segment intersects this keep-out zone.
    public func intersectsLine(_ start: VectorPoint, _ end: VectorPoint) -> Bool {
        guard isActive else { return false }
        
        // Simple check: if either endpoint is inside, or if the bounding box of the line intersects
        if containsPoint(start) || containsPoint(end) {
            return true
        }
        
        // Check bounding box intersection for rectangles
        if type == .rectangle {
            guard let minX = rectMinX, let minY = rectMinY,
                  let maxX = rectMaxX, let maxY = rectMaxY else { return false }
            
            let lineMinX = min(start.x, end.x)
            let lineMaxX = max(start.x, end.x)
            let lineMinY = min(start.y, end.y)
            let lineMaxY = max(start.y, end.y)
            
            // Check if bounding boxes overlap
            return !(lineMaxX < minX || lineMinX > maxX || lineMaxY < minY || lineMinY > maxY)
        }
        
        return false
    }
    
    /// Check if a point is inside a polygon using ray casting algorithm.
    private func isPointInPolygon(_ point: VectorPoint, polygon: [VectorPoint]) -> Bool {
        var inside = false
        let n = polygon.count
        
        guard n >= 3 else { return false }
        
        var j = n - 1
        for i in 0..<n {
            let yi = polygon[i].y
            let yj = polygon[j].y
            let xi = polygon[i].x
            let xj = polygon[j].x
            
            if ((yi > point.y) != (yj > point.y)) &&
                (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
}

// MARK: - Keep-Out Zone Manager

/// Manages a collection of keep-out zones and enforces them during toolpath generation.
public final class KeepOutZoneManager: ObservableObject {
    
    @Published public var zones: [KeepOutZone] = []
    
    /// Add a keep-out zone.
    public func addZone(_ zone: KeepOutZone) {
        zones.append(zone)
    }
    
    /// Remove a keep-out zone by ID.
    public func removeZone(id: UUID) -> Bool {
        if let index = zones.firstIndex(where: { $0.id == id }) {
            zones.remove(at: index)
            return true
        }
        return false
    }
    
    /// Check if a point is inside any active keep-out zone.
    public func containsPoint(_ point: VectorPoint) -> Bool {
        for zone in zones where zone.isActive && zone.containsPoint(point) {
            return true
        }
        return false
    }
    
    /// Check if a line segment intersects any active keep-out zone.
    public func intersectsLine(_ start: VectorPoint, _ end: VectorPoint) -> Bool {
        for zone in zones where zone.isActive && zone.intersectsLine(start, end) {
            return true
        }
        return false
    }
    
    /// Get all active keep-out zones.
    public var activeZones: [KeepOutZone] {
        zones.filter { $0.isActive }
    }
    
    /// Clear all keep-out zones.
    public func clearAll() {
        zones.removeAll()
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct KeepOutZone_Previews: PreviewProvider {
    static var previews: some View {
        Text("Keep-out zones are a non-visual component")
    }
}
#endif
