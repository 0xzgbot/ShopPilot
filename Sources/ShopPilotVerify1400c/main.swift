import Foundation
import ShopPilotCore

/// SPK-1400c verify (CLT machine, no XCTest).
/// Proves the friendly stage copy contract:
///   1. All six FriendlyCopyStage cases exist (via CaseIterable).
///   2. FriendlyCopy.intent(for:) maps each stage to its exact
///      sentence-case string — no jargon ('Stock, origin and machine',
///      'Toolpath strategies' are gone).
///
/// `Stage.intent` (Sources/ShopPilot/StageEnum.swift) is app-target-only and
/// cannot be imported from this Core-only CLT; the binding — it delegates to
/// `FriendlyCopy.intent(for: FriendlyCopyStage(rawValue: rawValue) ?? .setup)`
/// — is covered by the `swift build --target ShopPilot` gate.

enum VerifyError: Error { case failed(String) }

func expect(_ cond: Bool, _ msg: String) throws {
    if !cond { throw VerifyError.failed(msg) }
}

func main() throws {
    let expected: [FriendlyCopyStage: String] = [
        .setup:   "Set up your board",
        .design:  "Draw it, or bring in a file",
        .model:   "Add 3D relief if you need it",
        .cut:     "Plan the cuts",
        .preview: "See the cut before you run it",
        .machine: "Connect, zero, and run",
    ]
    try expect(expected.count == 6, "expected map covers all six stages (got \(expected.count))")

    // Every stage maps to exactly the specified sentence-case string.
    for stage in FriendlyCopyStage.allCases {
        guard let string = expected[stage] else {
            throw VerifyError.failed("no expectation registered for \(stage.rawValue)")
        }
        let got = FriendlyCopy.intent(for: stage)
        try expect(got == string,
                   "\(stage.rawValue): intent == \"\(string)\" (got \"\(got)\")")
        // Sentence case: starts with an uppercase letter, no all-caps runs
        // (jargon like 'Toolpath strategies' style is gone; acronyms like
        // '3D' are expected to stay capitalized).
        try expect(got.first?.isUppercase == true,
                   "\(stage.rawValue): intent starts uppercase (got \"\(got)\")")
        try expect(!got.allSatisfy(\.isUppercase),
                   "\(stage.rawValue): intent is not all-caps (got \"\(got)\")")
    }

    print("1400c: PASS — friendly stage copy")
}

do {
    try main()
} catch {
    print("1400c: FAIL — \(error)")
    exit(1)
}
