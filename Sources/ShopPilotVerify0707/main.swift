import Foundation
import ShopPilotCore

/// SPK-0707 — Verify STL import/export enhancements.
/// Proves: binary STL parse, ASCII STL parse, orientation config round-trip,
/// component STL export structure.

enum Verify0707 {
    static func run() {
        var pass = 0
        var fail = 0

        // 1. Binary STL parse
        // Create a minimal binary STL with one non-degenerate triangle.
        // Header: 80 bytes of zeros.
        var binaryData = Data(repeating: 0, count: 80)
        // Triangle count = 1 as uint32 LE at offset 80.
        let tcBytes = UInt32(1).littleEndian
        let tcData = withUnsafePointer(to: tcBytes) { ptr in
            Data(bytes: ptr, count: 4)
        }
        binaryData.append(tcData)
        // One triangle: normal (0,0,1) + 3 vertices forming a non-degenerate triangle.
        // Each float is 4 bytes, little-endian.
        func leFloat(_ v: Float32) -> Data {
            withUnsafePointer(to: v) { ptr in Data(bytes: ptr, count: 4) }
        }
        // Normal: 0, 0, 1
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(1))
        // Vertex 1: 0, 0, 0
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(0))
        // Vertex 2: 10, 0, 5
        binaryData.append(leFloat(10))
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(5))
        // Vertex 3: 0, 10, 5
        binaryData.append(leFloat(0))
        binaryData.append(leFloat(10))
        binaryData.append(leFloat(5))
        // Attribute byte count: 0 (2 bytes)
        binaryData.append(Data(repeating: 0, count: 2))

        let tempDir = FileManager.default.temporaryDirectory
        let binaryPath = tempDir.appendingPathComponent("test_binary.stl").path
        try? binaryData.write(to: URL(fileURLWithPath: binaryPath))

        // Test isBinarySTL via parseBinary (which calls it internally)
        // We'll test parseBinary directly since isBinarySTL is private.
        do {
            let triangles = try STLHeightfieldImporter.parseBinary(path: binaryPath)
            if triangles.count == 1 { pass += 1; print("✓ Binary STL parse: 1 triangle") }
            else { fail += 1; print("✗ Binary STL parse: expected 1, got \(triangles.count)") }
        } catch {
            fail += 1; print("✗ Binary STL parse: \(error)")
        }

        // 2. ASCII STL parse
        let asciiSTL = """
solid test
  facet normal 0 0 1
    outer loop
      vertex 0 0 0
      vertex 10 0 5
      vertex 0 10 5
    endloop
  endfacet
endsolid test
"""
        let asciiPath = tempDir.appendingPathComponent("test_ascii.stl").path
        try? asciiSTL.write(to: URL(fileURLWithPath: asciiPath), atomically: true, encoding: .utf8)

        do {
            let triangles = try STLHeightfieldImporter.parseASCII(text: asciiSTL)
            if triangles.count == 1 { pass += 1; print("✓ ASCII STL parse: 1 triangle") }
            else { fail += 1; print("✗ ASCII STL parse: expected 1, got \(triangles.count)") }
        } catch {
            fail += 1; print("✗ ASCII STL parse: \(error)")
        }

        // 3. STLImportConfig round-trip
        let config = STLImportConfig(
            orientation: .xz,
            scale: 2.5,
            flipX: true,
            flipY: false,
            flipZ: true,
            center: true,
            maxTriangles: 50000
        )
        let encoded = try? JSONEncoder().encode(config)
        let decoded = try? JSONDecoder().decode(STLImportConfig.self, from: encoded!)
        if let d = decoded,
           d.orientation == .xz,
           d.scale == 2.5,
           d.flipX == true,
           d.flipY == false,
           d.flipZ == true,
           d.center == true,
           d.maxTriangles == 50000 {
            pass += 1; print("✓ STLImportConfig Codable round-trip")
        } else {
            fail += 1; print("✗ STLImportConfig Codable round-trip failed")
        }

        // 4. BoundingBox3D computed properties
        let box = BoundingBox3D(minX: 0, minY: 0, minZ: 0, maxX: 100, maxY: 50, maxZ: 25)
        if box.width == 100 && box.height == 50 && box.depth == 25
           && box.centerX == 50 && box.centerY == 25 && box.centerZ == 12.5 {
            pass += 1; print("✓ BoundingBox3D computed properties correct")
        } else {
            fail += 1; print("✗ BoundingBox3D computed properties wrong")
        }

        // 5. STLManager.validateSTL
        let (isValid, _) = STLManager.validateSTL(at: binaryPath)
        if isValid { pass += 1; print("✓ STLManager.validateSTL: valid binary STL") }
        else { fail += 1; print("✗ STLManager.validateSTL: should be valid") }

        let (isInvalid, _) = STLManager.validateSTL(at: "/nonexistent.stl")
        if !isInvalid { pass += 1; print("✓ STLManager.validateSTL: nonexistent → invalid") }
        else { fail += 1; print("✗ STLManager.validateSTL: nonexistent should be invalid") }

        // 6. STLManager.importSTL with valid file
        let importResult = STLManager.importSTL(
            at: binaryPath,
            config: config,
            componentID: UUID()
        )
        if importResult.success { pass += 1; print("✓ STLManager.importSTL: success with valid file") }
        else { fail += 1; print("✗ STLManager.importSTL: failed with valid file") }

        // 7. STLManager.importSTL with nonexistent file
        let badImport = STLManager.importSTL(
            at: "/nonexistent.stl",
            config: config,
            componentID: UUID()
        )
        if !badImport.success { pass += 1; print("✓ STLManager.importSTL: failure with nonexistent file") }
        else { fail += 1; print("✗ STLManager.importSTL: should fail with nonexistent file") }

        // 8. STLManager.exportSTL
        let exportPath = tempDir.appendingPathComponent("export_test.stl").path
        let exportResult = STLManager.exportSTL(
            componentID: UUID(),
            triangleCount: 100,
            outputPath: exportPath,
            config: STLOutputConfig()
        )
        if exportResult.success { pass += 1; print("✓ STLManager.exportSTL: success") }
        else { fail += 1; print("✗ STLManager.exportSTL: failed") }

        // 9. Rasterization produces valid HeightfieldData
        let tri = STLHeightfieldImporter.Triangle(
            (0, 0, 0),
            (10, 0, 5),
            (0, 10, 5)
        )
        let grid = STLHeightfieldImporter.rasterize(
            triangles: [tri],
            cellSizeMm: 1.0,
            scale: 1.0
        )
        if grid.width > 0 && grid.height > 0 && grid.heights.count == grid.width * grid.height {
            pass += 1; print("✓ Rasterization: valid HeightfieldData")
        } else {
            fail += 1; print("✗ Rasterization: invalid grid dimensions")
        }

        print("\nSPK-0707 verify: \(pass) passed, \(fail) failed")
        if fail == 0 {
            print("PASS: ShopPilotVerify0707 — binary/ASCII STL parse, orientation config, bounding box, STLManager CRUD, rasterization verified.")
        } else {
            print("FAIL: \(fail) tests failed.")
            exit(1)
        }
    }
}

Verify0707.run()
