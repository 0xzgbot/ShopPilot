import Foundation

// MARK: - Normalize G-code for comparison (remove comments, whitespace variations)
public func normalizeGcode(_ gcode: String) -> String {
    let lines = gcode.components(separatedBy: "\n")
    
    var normalizedLines: [String] = []
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Skip comments and empty lines
        if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("(") {
            continue
        }
        
        normalizedLines.append(trimmed)
    }
    
    return normalizedLines.joined(separator: "\n")
}

// MARK: - Find line-by-line differences between two G-code strings
public func findGcodeDifferences(_ expected: String, _ actual: String) -> [String] {
    let expectedLines = expected.components(separatedBy: "\n")
    let actualLines = actual.components(separatedBy: "\n")
    
    var differences: [String] = []
    let maxLines = max(expectedLines.count, actualLines.count)
    
    for i in 0..<maxLines {
        let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"
        let actualLine = i < actualLines.count ? actualLines[i] : "<extra>"
        
        if expectedLine != actualLine {
            differences.append("Line \(i + 1):")
            differences.append("  Expected: \(expectedLine)")
            differences.append("  Actual:   \(actualLine)")
        }
    }
    
    return differences
}

// MARK: - Golden Fixture Type

/// Types of golden test fixtures for toolpath verification.
public enum GoldenFixtureType {
    /// Profile toolpath fixture.
    case profile
    /// Pocket toolpath fixture.
    case pocket
    /// Drill toolpath fixture.
    case drill
    
    public var displayName: String {
        switch self {
        case .profile: return "Profile"
        case .pocket: return "Pocket"
        case .drill: return "Drill"
        }
    }
}

// MARK: - Golden Fixture Result

/// Result of a golden fixture test.
public struct GoldenFixtureResult {
    
    /// The expected G-code output.
    public let expectedGcode: String
    
    /// The actual G-code output from the toolpath engine.
    public var actualGcode: String? = nil
    
    /// Whether the outputs match.
    public var matches: Bool {
        guard let actual = actualGcode else { return false }
        return normalizeGcode(expectedGcode) == normalizeGcode(actual)
    }
    
    /// Differences between expected and actual (if any).
    public var differences: [String] = []
    
    /// Fixture type this result is for.
    public let fixtureType: GoldenFixtureType
    
    /// Description of the test case.
    public let description: String
    
    /// Whether the test passed.
    public var passed: Bool { matches && differences.isEmpty }
}

// MARK: - Golden Fixture Manager

/// Manages golden G-code fixtures for toolpath verification testing.
public final class GoldenFixtureManager {
    
    private var fixtures: [GoldenFixtureType: String] = [:]
    
    /// Normalize G-code for comparison (remove comments, whitespace variations).
    public static func normalizeGcode(_ gcode: String) -> String {
        let lines = gcode.components(separatedBy: "\n")
        
        var normalizedLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("(") {
                continue
            }
            
            normalizedLines.append(trimmed)
        }
        
        return normalizedLines.joined(separator: "\n")
    }
    
    /// Find line-by-line differences between two G-code strings.
    public static func findDifferences(_ expected: String, _ actual: String) -> [String] {
        let expectedLines = expected.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        
        var differences: [String] = []
        let maxLines = max(expectedLines.count, actualLines.count)
        
        for i in 0..<maxLines {
            let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"
            let actualLine = i < actualLines.count ? actualLines[i] : "<extra>"
            
            if expectedLine != actualLine {
                differences.append("Line \(i + 1):")
                differences.append("  Expected: \(expectedLine)")
                differences.append("  Actual:   \(actualLine)")
            }
        }
        
        return differences
    }
    
    /// Register a golden fixture.
    public func register(_ gcode: String, for type: GoldenFixtureType) {
        fixtures[type] = gcode
    }
    
    /// Get a golden fixture by type.
    public func fixture(for type: GoldenFixtureType) -> String? {
        fixtures[type]
    }
    
    /// Run all registered fixtures against toolpath engines.
    public func runAllFixtures() -> [GoldenFixtureResult] {
        var results: [GoldenFixtureResult] = []
        
        for (type, expectedGcode) in fixtures {
            let result = GoldenFixtureResult(
                expectedGcode: expectedGcode,
                fixtureType: type,
                description: "\(type.displayName) golden fixture"
            )
            
            // In a real implementation, this would run the actual toolpath engine
            // and compare output against the expected G-code
            
            results.append(result)
        }
        
        return results
    }
    
    /// Verify a specific fixture against generated G-code.
    public func verifyFixture(_ type: GoldenFixtureType, against actualGcode: String) -> GoldenFixtureResult {
        guard let expected = fixtures[type] else {
            return GoldenFixtureResult(
                expectedGcode: "",
                actualGcode: actualGcode,
                fixtureType: type,
                description: "\(type.displayName) golden fixture (not registered)"
            )
        }
        
        var result = GoldenFixtureResult(
            expectedGcode: expected,
            actualGcode: actualGcode,
            fixtureType: type,
            description: "\(type.displayName) golden fixture"
        )
        
        // Compare normalized G-code outputs
        let normalizedExpected = normalizeGcode(expected)
        let normalizedActual = normalizeGcode(actualGcode)
        
        if normalizedExpected != normalizedActual {
            result.differences = findDifferences(normalizedExpected, normalizedActual)
        }
        
        return result
    }
    
    /// Normalize G-code for comparison (remove comments, whitespace variations).
    private func normalizeGcode(_ gcode: String) -> String {
        let lines = gcode.components(separatedBy: "\n")
        
        var normalizedLines: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix(";") || trimmed.hasPrefix("(") {
                continue
            }
            
            normalizedLines.append(trimmed)
        }
        
        return normalizedLines.joined(separator: "\n")
    }
    
    /// Find line-by-line differences between two G-code strings.
    private func findDifferences(_ expected: String, _ actual: String) -> [String] {
        let expectedLines = expected.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        
        var differences: [String] = []
        let maxLines = max(expectedLines.count, actualLines.count)
        
        for i in 0..<maxLines {
            let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"
            let actualLine = i < actualLines.count ? actualLines[i] : "<extra>"
            
            if expectedLine != actualLine {
                differences.append("Line \(i + 1):")
                differences.append("  Expected: \(expectedLine)")
                differences.append("  Actual:   \(actualLine)")
            }
        }
        
        return differences
    }
}

// MARK: - Predefined Golden Fixtures

extension GoldenFixtureManager {
    
    /// Create a manager with predefined golden fixtures.
    public static func createWithPredefinedFixtures() -> GoldenFixtureManager {
        let manager = GoldenFixtureManager()
        
        // Profile fixture example
        let profileGcode = """
%
O=PROFILE_TEST
(Tool: 6mm)
G21 ; Set millimeter units
G90 ; Absolute positioning
M8 ; Flood coolant on

G0 Z5.0
G0 X-5.0 Y0.0
G1 Z-2.0 F300
G1 X5.0 Y0.0 F1000
G1 X5.0 Y10.0 F1000
G1 X-5.0 Y10.0 F1000
G1 X-5.0 Y0.0 F1000
G0 Z5.0

M9 ; Coolant off
G0 Z5.0 ; Rapid to safe height
M2 ; Program end
%
"""
        manager.register(profileGcode, for: .profile)
        
        // Pocket fixture example
        let pocketGcode = """
%
O=POCKET_TEST
(Tool: 6mm)
G21 ; Set millimeter units
G90 ; Absolute positioning
M8 ; Flood coolant on

G0 Z5.0
G0 X0.0 Y0.0
G1 Z-2.0 F300
G1 X10.0 Y0.0 F1000
G1 X10.0 Y10.0 F1000
G1 X0.0 Y10.0 F1000
G1 X0.0 Y0.0 F1000

M9 ; Coolant off
G0 Z5.0 ; Rapid to safe height
M2 ; Program end
%
"""
        manager.register(pocketGcode, for: .pocket)
        
        // Drill fixture example
        let drillGcode = """
%
O=DRILL_TEST
(Tool: 6mm)
(Cycle: Peck Drill)
G21 ; Set millimeter units
G90 ; Absolute positioning
M8 ; Flood coolant on

G0 X5.0 Y5.0
G0 Z5.0
G1 Z-3.0 F300
G4 P1.0
G0 Z5.0

M9 ; Coolant off
G0 Z5.0 ; Rapid to safe height
M2 ; Program end
%
"""
        manager.register(drillGcode, for: .drill)
        
        return manager
    }
}

// MARK: - Preview (Xcode only — not available in CLI builds)

#if canImport(SwiftUI) && DEBUG
import SwiftUI

struct GoldenFixtureManager_Previews: PreviewProvider {
    static var previews: some View {
        Text("Golden fixture manager is a non-visual component")
    }
}
#endif
