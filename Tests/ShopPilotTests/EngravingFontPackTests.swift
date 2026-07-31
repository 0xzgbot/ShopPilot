import XCTest
@testable import ShopPilotGeometry

final class EngravingFontPackTests: XCTestCase {

    // MARK: - Font List Tests

    func testEngravingFontsIsNonEmpty() {
        let fonts = EngravingFontPack.engravingFonts()
        XCTAssertFalse(fonts.isEmpty, "Engraving font pack should not be empty")
    }

    func testEngravingFontsHasExpectedCount() {
        let fonts = EngravingFontPack.engravingFonts()
        // We have: Helvetica Neue (3 weights) + Arial + Verdana + Georgia +
        // Times New Roman + Courier New + Impact + Zapfino = 10 entries
        XCTAssertEqual(fonts.count, 10, "Expected 10 curated font entries")
    }

    func testEngravingFontsContainsHelveticaNeue() {
        let fonts = EngravingFontPack.engravingFonts()
        let helvetica = fonts.filter { $0.name == "Helvetica Neue" }
        XCTAssertFalse(helvetica.isEmpty, "Should include Helvetica Neue")
        XCTAssertEqual(helvetica.count, 3, "Helvetica Neue should have 3 weight variants")
    }

    func testEngravingFontsContainsAllRequiredFonts() {
        let fonts = EngravingFontPack.engravingFonts()
        let fontNames = fonts.map { $0.name }

        let requiredFonts = [
            "Helvetica Neue",
            "Georgia",
            "Courier New",
            "Times New Roman",
            "Arial",
            "Verdana",
            "Impact",
            "Zapfino"
        ]

        for required in requiredFonts {
            XCTAssertTrue(fontNames.contains(required),
                          "Font pack should contain \(required)")
        }
    }

    // MARK: - Category Tests

    func testAllCategoriesAreRepresented() {
        let fonts = EngravingFontPack.engravingFonts()
        let categories = Set(fonts.map { $0.category })

        XCTAssertEqual(categories.count, 5, "All 5 categories should be represented")
        XCTAssertTrue(categories.contains(.sansSerif), "Should have sans-serif fonts")
        XCTAssertTrue(categories.contains(.serif), "Should have serif fonts")
        XCTAssertTrue(categories.contains(.monospace), "Should have monospace fonts")
        XCTAssertTrue(categories.contains(.display), "Should have display fonts")
        XCTAssertTrue(categories.contains(.script), "Should have script fonts")
    }

    func testSansSerifCategoryCount() {
        let fonts = EngravingFontPack.fonts(in: .sansSerif)
        XCTAssertEqual(fonts.count, 5, "Sans-serif should have Helvetica Neue (3) + Arial + Verdana")
    }

    func testSerifCategoryCount() {
        let fonts = EngravingFontPack.fonts(in: .serif)
        XCTAssertEqual(fonts.count, 2, "Serif should have Georgia + Times New Roman")
    }

    func testMonospaceCategoryCount() {
        let fonts = EngravingFontPack.fonts(in: .monospace)
        XCTAssertEqual(fonts.count, 1, "Monospace should have Courier New")
    }

    func testDisplayCategoryCount() {
        let fonts = EngravingFontPack.fonts(in: .display)
        XCTAssertEqual(fonts.count, 1, "Display should have Impact")
    }

    func testScriptCategoryCount() {
        let fonts = EngravingFontPack.fonts(in: .script)
        XCTAssertEqual(fonts.count, 1, "Script should have Zapfino")
    }

    func testCategoryFilteringReturnsCorrectFonts() {
        let sansSerif = EngravingFontPack.fonts(in: .sansSerif)
        for font in sansSerif {
            XCTAssertEqual(font.category, .sansSerif)
        }

        let serif = EngravingFontPack.fonts(in: .serif)
        for font in serif {
            XCTAssertEqual(font.category, .serif)
        }
    }

    // MARK: - Recommended for Engraving Tests

    func testRecommendedForEngravingReturnsSubset() {
        let all = EngravingFontPack.engravingFonts()
        let recommended = EngravingFontPack.recommendedForEngraving(minFontSize: 8.0)
        XCTAssertLessThanOrEqual(recommended.count, all.count,
                                 "Recommended should be a subset of all fonts")
    }

    func testRecommendedForEngravingSmallSize() {
        // minFontSize 6.0 should include fonts with size <= 6.0
        let recommended = EngravingFontPack.recommendedForEngraving(minFontSize: 6.0)
        for font in recommended {
            XCTAssertLessThanOrEqual(font.size, 6.0,
                                     "Font \(font.name) size \(font.size) should be <= 6.0")
        }
    }

    func testRecommendedForEngravingLargeSize() {
        // minFontSize 14.0 should include all fonts
        let recommended = EngravingFontPack.recommendedForEngraving(minFontSize: 14.0)
        XCTAssertEqual(recommended.count, 10, "All fonts should be recommended at 14pt")
    }

    func testRecommendedForEngravingExactSize() {
        let recommended = EngravingFontPack.recommendedForEngraving(minFontSize: 10.0)
        // Impact has size 10.0, so it should be included
        let impactIncluded = recommended.contains { $0.name == "Impact" }
        XCTAssertTrue(impactIncluded, "Impact (size 10.0) should be included at minFontSize 10.0")
    }

    // MARK: - Font Availability Tests

    func testIsFontAvailableOnSystemReturnsBool() {
        // Helvetica Neue is a standard macOS font — should be available
        let available = EngravingFontPack.isFontAvailableOnSystem("Helvetica Neue")
        XCTAssertTrue(available, "Helvetica Neue should be available on macOS")
    }

    func testIsFontAvailableOnSystemEmptyString() {
        let available = EngravingFontPack.isFontAvailableOnSystem("")
        XCTAssertFalse(available, "Empty string should not be available")
    }

    func testIsFontAvailableOnSystemNonExistentFont() {
        // A clearly non-existent font name — may fall back to system font on macOS
        // but the family name check should still work
        let available = EngravingFontPack.isFontAvailableOnSystem("ThisFontDoesNotExist12345")
        // On macOS, CTFontCreateWithName falls back to system font, so this may return true
        // We just verify it returns a bool without crashing
        _ = available
    }

    func testEngravingFontsAllHaveNonEmptyNames() {
        let fonts = EngravingFontPack.engravingFonts()
        for font in fonts {
            XCTAssertFalse(font.name.isEmpty, "Font name should not be empty")
        }
    }

    func testEngravingFontsAllHaveValidSizes() {
        let fonts = EngravingFontPack.engravingFonts()
        for font in fonts {
            XCTAssertGreaterThan(font.size, 0, "Font size should be positive")
        }
    }

    func testEngravingFontsAllHaveNonEmptyWeights() {
        let fonts = EngravingFontPack.engravingFonts()
        for font in fonts {
            XCTAssertFalse(font.weight.isEmpty, "Font weight should not be empty")
        }
    }

    func testEngravingFontsAllHaveDescriptions() {
        let fonts = EngravingFontPack.engravingFonts()
        for font in fonts {
            XCTAssertFalse(font.description.isEmpty, "Font description should not be empty")
        }
    }

    func testEngravingFontEquatable() {
        let font1 = EngravingFont(name: "Helvetica Neue", category: .sansSerif, size: 6.0, weight: "Regular", description: "Test")
        let font2 = EngravingFont(name: "Helvetica Neue", category: .sansSerif, size: 8.0, weight: "Light", description: "Test")
        let font3 = EngravingFont(name: "Helvetica Neue", category: .sansSerif, size: 6.0, weight: "Regular", description: "Different")

        XCTAssertEqual(font1, font1, "Same font should be equal")
        XCTAssertNotEqual(font1, font2, "Different weights should not be equal")
        XCTAssertEqual(font1, font3, "Same name and category should be equal regardless of description")
    }

    func testEngravingFontIdentifiable() {
        let font1 = EngravingFont(name: "Helvetica Neue", category: .sansSerif, size: 6.0, weight: "Regular", description: "Test")
        let font2 = EngravingFont(name: "Helvetica Neue", category: .sansSerif, size: 6.0, weight: "Regular", description: "Test")

        // Each instance should have a unique UUID
        XCTAssertNotEqual(font1.id, font2.id, "Different instances should have different IDs")
    }

    // MARK: - Availability Check Tests

    func testCheckAllAvailabilityDoesNotCrash() {
        let availability = EngravingFontPack.checkAllAvailability()
        XCTAssertEqual(availability.count, 10, "Should check all 10 font entries")
    }

    func testAvailableFontsReturnsSubset() {
        let available = EngravingFontPack.availableFonts()
        let all = EngravingFontPack.engravingFonts()
        XCTAssertLessThanOrEqual(available.count, all.count,
                                 "Available fonts should be a subset of all fonts")
    }

    func testAvailableFontsIncludesHelveticaNeue() {
        let available = EngravingFontPack.availableFonts()
        let helvetica = available.filter { $0.name == "Helvetica Neue" }
        XCTAssertFalse(helvetica.isEmpty, "Helvetica Neue should be available on macOS")
    }

    // MARK: - Sorting Tests

    func testEngravingFontsAreSortedByCategory() {
        let fonts = EngravingFontPack.engravingFonts()
        let categories = fonts.map { $0.category }
        let sortedCategories = categories.sorted { $0.rawValue < $1.rawValue }
        XCTAssertEqual(categories, sortedCategories,
                       "Fonts should be sorted by category")
    }

    // MARK: - Minimum Font Size Tests

    func testZapfinoHasHighestMinimumSize() {
        let fonts = EngravingFontPack.engravingFonts()
        let zapfino = fonts.first { $0.name == "Zapfino" }
        XCTAssertNotNil(zapfino, "Zapfino should be in the font pack")
        if let zapfino = zapfino {
            XCTAssertEqual(zapfino.size, 14.0, "Zapfino minimum size should be 14.0pt")
        }
    }

    func testCourierNewHasLowestMinimumSize() {
        let fonts = EngravingFontPack.engravingFonts()
        let courier = fonts.first { $0.name == "Courier New" }
        XCTAssertNotNil(courier, "Courier New should be in the font pack")
        if let courier = courier {
            XCTAssertEqual(courier.size, 6.0, "Courier New minimum size should be 6.0pt")
        }
    }
}
