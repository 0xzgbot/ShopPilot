import XCTest
@testable import ShopPilotCore

final class JobSheetGeneratorTests: XCTestCase {
    
    // MARK: - Basic PDF Generation
    
    func testGeneratePDFCreatesFile() throws {
        let data = makeJobSheetData()
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_jobsheet_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        let result = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        
        XCTAssertTrue(result, "PDF generation should succeed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path), "PDF file should exist")
        
        let fileData = try Data(contentsOf: testURL)
        XCTAssertTrue(fileData.count > 0, "PDF file should not be empty")
        
        // Verify PDF header
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        XCTAssertTrue(pdfString.hasPrefix("%PDF-"), "File should be a valid PDF")
    }
    
    func testGeneratePDFWithEmptyToolpaths() throws {
        let data = JobSheetData(
            jobName: "Test Job",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [],
            notes: "No toolpaths"
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_empty_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        let result = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        
        XCTAssertTrue(result, "PDF generation should succeed even with no toolpaths")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    func testGeneratePDFWithMultipleToolpaths() throws {
        let toolpaths = [
            ToolpathInfo(name: "Outer Profile", type: .profile, tool: "6mm End Mill", feedRate: 1000, depth: 2.5, estimatedTime: 120),
            ToolpathInfo(name: "Pocket", type: .pocket, tool: "8mm End Mill", feedRate: 800, depth: 5.0, estimatedTime: 300),
            ToolpathInfo(name: "Holes", type: .drill, tool: "3mm Drill", feedRate: 500, depth: 10.0, estimatedTime: 60),
            ToolpathInfo(name: "Engraving", type: .quickengrave, tool: "90° V-Bit", feedRate: 1000, depth: 1.0, estimatedTime: 45)
        ]
        
        let data = JobSheetData(
            jobName: "Multi-Tool Job",
            material: "Hardwood",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: toolpaths
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_multi_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        let result = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        
        XCTAssertTrue(result)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        // Verify content includes toolpath names
        XCTAssertTrue(pdfString.contains("Outer Profile"))
        XCTAssertTrue(pdfString.contains("Pocket"))
        XCTAssertTrue(pdfString.contains("Holes"))
        XCTAssertTrue(pdfString.contains("Engraving"))
    }
    
    // MARK: - ToolpathInfo
    
    func testToolpathInfoCreation() {
        let tp = ToolpathInfo(
            name: "Test Operation",
            type: .vcarve,
            tool: "90° V-Bit",
            feedRate: 1000,
            depth: 2.0,
            estimatedTime: 180
        )
        
        XCTAssertEqual(tp.name, "Test Operation")
        XCTAssertEqual(tp.type, .vcarve)
        XCTAssertEqual(tp.type.displayName, "V-Carve")
        XCTAssertEqual(tp.tool, "90° V-Bit")
        XCTAssertEqual(tp.feedRate, 1000)
        XCTAssertEqual(tp.depth, 2.0)
        XCTAssertEqual(tp.estimatedTime, 180)
    }
    
    func testToolpathInfoID() {
        let tp1 = ToolpathInfo(name: "A", type: .profile, tool: "T1", feedRate: 100, depth: 1, estimatedTime: 10)
        let tp2 = ToolpathInfo(name: "B", type: .profile, tool: "T2", feedRate: 100, depth: 1, estimatedTime: 10)
        
        XCTAssertNotEqual(tp1.id, tp2.id)
    }
    
    // MARK: - ToolpathType Display Names
    
    func testToolpathTypeDisplayNames() {
        XCTAssertEqual(ToolpathInfo.ToolpathType.profile.displayName, "Profile")
        XCTAssertEqual(ToolpathInfo.ToolpathType.pocket.displayName, "Pocket")
        XCTAssertEqual(ToolpathInfo.ToolpathType.drill.displayName, "Drill")
        XCTAssertEqual(ToolpathInfo.ToolpathType.vcarve.displayName, "V-Carve")
        XCTAssertEqual(ToolpathInfo.ToolpathType.quickengrave.displayName, "Quick Engrave")
    }
    
    // MARK: - JobSheetData
    
    func testJobSheetDataCreation() {
        let data = JobSheetData(
            jobName: "Test Job",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [],
            notes: "Test notes"
        )
        
        XCTAssertEqual(data.jobName, "Test Job")
        XCTAssertEqual(data.material, "Pine")
        XCTAssertEqual(data.sheetWidth, 600)
        XCTAssertEqual(data.sheetHeight, 400)
        XCTAssertTrue(data.toolpaths.isEmpty)
        XCTAssertEqual(data.notes, "Test notes")
    }
    
    func testJobSheetDataDefaultCreatedAt() {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 100,
            sheetHeight: 100,
            toolpaths: []
        )
        
        XCTAssertLessThan(Date().timeIntervalSince(data.createdAt), 1.0)
    }
    
    func testJobSheetDataDefaultNotes() {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 100,
            sheetHeight: 100,
            toolpaths: []
        )
        
        XCTAssertTrue(data.notes.isEmpty)
    }
    
    // MARK: - PDF Content Validation
    
    func testPDFContainsJobName() throws {
        let data = JobSheetData(
            jobName: "Unique Job Name 12345",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_name_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("Unique Job Name 12345"))
    }
    
    func testPDFContainsMaterial() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Baltic Birch Plywood",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_mat_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("Baltic Birch Plywood"))
    }
    
    func testPDFContainsSheetSize() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 1234.5,
            sheetHeight: 678.9,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_size_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("1234.5"))
        XCTAssertTrue(pdfString.contains("678.9"))
    }
    
    func testPDFContainsFooter() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_footer_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("Generated by ShopPilot"))
    }
    
    func testPDFContainsNotes() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [],
            notes: "Important safety note: wear eye protection"
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_notes_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("wear eye protection"))
    }
    
    // MARK: - PDF Structure
    
    func testPDFHasXrefTable() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_xref_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("xref"))
        XCTAssertTrue(pdfString.contains("startxref"))
        XCTAssertTrue(pdfString.contains("%%EOF"))
    }
    
    func testPDFHasTrailer() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_trailer_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("trailer"))
        XCTAssertTrue(pdfString.contains("/Root"))
    }
    
    func testPDFHasCatalog() throws {
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_catalog_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        _ = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        let fileData = try Data(contentsOf: testURL)
        let pdfString = String(data: fileData, encoding: .utf8) ?? ""
        
        XCTAssertTrue(pdfString.contains("/Catalog"))
    }
    
    // MARK: - ToolpathInfo Codable
    
    func testToolpathInfoCodable() throws {
        let tp = ToolpathInfo(
            name: "Test",
            type: .profile,
            tool: "T1",
            feedRate: 1000,
            depth: 2.0,
            estimatedTime: 60
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(tp)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolpathInfo.self, from: data)
        
        XCTAssertEqual(decoded.name, tp.name)
        XCTAssertEqual(decoded.type, tp.type)
        XCTAssertEqual(decoded.tool, tp.tool)
        XCTAssertEqual(decoded.feedRate, tp.feedRate)
        XCTAssertEqual(decoded.depth, tp.depth)
        XCTAssertEqual(decoded.estimatedTime, tp.estimatedTime)
    }
    
    func testJobSheetDataCodable() throws {
        let data = JobSheetData(
            jobName: "Test Job",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [
                ToolpathInfo(name: "Test", type: .profile, tool: "T1", feedRate: 1000, depth: 2.0, estimatedTime: 60)
            ],
            notes: "Test notes"
        )
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JobSheetData.self, from: jsonData)
        
        XCTAssertEqual(decoded.jobName, data.jobName)
        XCTAssertEqual(decoded.material, data.material)
        XCTAssertEqual(decoded.sheetWidth, data.sheetWidth)
        XCTAssertEqual(decoded.sheetHeight, data.sheetHeight)
        XCTAssertEqual(decoded.toolpaths.count, data.toolpaths.count)
        XCTAssertEqual(decoded.notes, data.notes)
    }
    
    // MARK: - Edge Cases
    
    func testGeneratePDFWithSpecialCharacters() throws {
        let data = JobSheetData(
            jobName: "Job with special chars: <>&\"'",
            material: "Pine & Oak",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: []
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_special_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        // PDF strings need escaping for special characters
        // The generator should handle this gracefully
        let result = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        
        // Even if special chars cause issues, the file should be created
        // (the PDF may not render perfectly but should be valid structure)
        XCTAssertTrue(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    func testGeneratePDFWithLongToolpathName() throws {
        let longName = String(repeating: "A", count: 200)
        let data = JobSheetData(
            jobName: "Test",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [
                ToolpathInfo(name: longName, type: .profile, tool: "T1", feedRate: 1000, depth: 2.0, estimatedTime: 60)
            ]
        )
        let testURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_long_\(UUID().uuidString).pdf")
        
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        
        let result = JobSheetGenerator.generatePDF(data: data, outputPath: testURL)
        
        XCTAssertTrue(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    // MARK: - Helper
    
    private func makeJobSheetData() -> JobSheetData {
        JobSheetData(
            jobName: "Test Sign",
            material: "Pine",
            sheetWidth: 600,
            sheetHeight: 400,
            toolpaths: [
                ToolpathInfo(name: "Outer Profile", type: .profile, tool: "6mm End Mill", feedRate: 1000, depth: 25.0, estimatedTime: 180),
                ToolpathInfo(name: "V-Carve Text", type: .vcarve, tool: "90° V-Bit", feedRate: 500, depth: 2.0, estimatedTime: 300),
                ToolpathInfo(name: "Quick Engrave", type: .quickengrave, tool: "45° V-Bit", feedRate: 1000, depth: 0.5, estimatedTime: 60)
            ],
            notes: "Cut on 25mm pine. Use 6mm end mill for profile."
        )
    }
}
