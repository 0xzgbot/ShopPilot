import Foundation
import ShopPilotGeometry

/// SPK-0500 verify without XCTest (CLT-only): TextObject stores string + fontName
/// and round-trips Codable; renders to path via CoreText.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // 1. Create a text model with string + system font name.
    let text = TextObject(
        string: "SHOP PILOT",
        fontName: "Helvetica Neue",
        fontSize: 72.0
    )
    try expect(text.string == "SHOP PILOT", "string stored")
    try expect(text.fontName == "Helvetica Neue", "fontName stored")
    try expect(text.fontSize == 72.0, "fontSize stored")
    try expect(!text.isEmpty, "non-empty text")

    // 2. Codable round-trip (JSON).
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(text)
    let decoded = try JSONDecoder().decode(TextObject.self, from: data)
    try expect(decoded == text, "Codable round-trip equality")
    let json = String(data: data, encoding: .utf8) ?? ""
    try expect(json.contains("\"string\"") && json.contains("\"fontName\""),
               "JSON carries string + fontName keys")

    // 3. Renders or converts to path — glyph outlines for real text.
    let rendered = text.renderToShapes()
    try expect(!rendered.shapes.isEmpty, "render produced glyph shapes")
    try expect(rendered.metrics.totalAdvance > 0, "render has positive advance")

    // 4. Whitespace-only text is empty but still round-trips.
    let blank = TextObject(string: "   ", fontName: "Georgia", fontSize: 24)
    try expect(blank.isEmpty, "whitespace-only text is empty")
    let blankData = try encoder.encode(blank)
    let blankDecoded = try JSONDecoder().decode(TextObject.self, from: blankData)
    try expect(blankDecoded == blank, "blank text round-trip")
    try expect(blank.renderToShapes().shapes.isEmpty, "blank renders no shapes")

    print("SPK-0500 verification: PASS")
    print("  TextObject stores string+fontName; Codable round-trip OK")
    print("  rendered \(rendered.shapes.count) glyph shapes for \"\(text.string)\"")
}

do {
    try main()
} catch {
    fputs("SPK-0500 verification: FAIL — \(error)\n", stderr)
    exit(1)
}
