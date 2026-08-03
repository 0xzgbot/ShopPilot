import Foundation
import ShopPilotCore

/// SPK-1103 verify without XCTest (CLT-only machines).
/// Proves the Preview stage shows empty-state copy exactly when the session
/// has no G-code **and** no vectors, and hides it otherwise.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    // Empty-state copy present when no gcode/vectors.
    guard let empty = PreviewEmptyState.copy(gcodeCount: 0, vectorCount: 0) else {
        throw VerifyError.failed("expected empty-state copy for empty session")
    }
    try expect(!empty.title.isEmpty, "title non-empty")
    try expect(!empty.message.isEmpty, "message non-empty")
    try expect(empty.message.contains("Design/Cut") || empty.message.contains("Machine"),
               "message points at where to generate content")

    // Predicate agrees.
    try expect(PreviewEmptyState.isEmpty(gcodeCount: 0, vectorCount: 0), "empty when no gcode/vectors")

    // No empty state when either side has content.
    try expect(PreviewEmptyState.copy(gcodeCount: 1, vectorCount: 0) == nil, "gcode-only hides empty state")
    try expect(PreviewEmptyState.copy(gcodeCount: 0, vectorCount: 1) == nil, "vectors-only hides empty state")
    try expect(PreviewEmptyState.copy(gcodeCount: 3, vectorCount: 2) == nil, "full session hides empty state")

    // G-code lines without any motion segments still count as content
    // (wireframe renderer tolerates them) — empty state must not appear.
    let lines = ["G21", "G90", "M5"]
    let segments = WireframeRenderer.generateSegments(from: lines)
    try expect(segments.isEmpty, "no motion segments in fixture")
    try expect(PreviewEmptyState.isEmpty(gcodeCount: lines.count, vectorCount: 0) == false,
               "non-motion gcode still suppresses empty state")

    print("ShopPilotVerify1103 PASS — empty-state copy shown when no gcode/vectors, hidden otherwise")
}

do {
    try main()
} catch {
    fputs("ShopPilotVerify1103 FAIL — \(error)\n", stderr)
    exit(1)
}
