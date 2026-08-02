#!/usr/bin/env swift
/// Fixture stream verification script.
/// Loads a .nc fixture file, streams it through SimulatorTransport via GCodeStreamer,
/// and asserts that progress flows 0 → 1.
///
/// Run: swift scripts/verify_fixture_stream.swift

import Foundation
import ShopPilotCore
import ShopPilotSerial

// MARK: - Helpers

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    if a != b {
        print("FAIL: \(msg) — expected \(b), got \(a)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ msg: String) {
    if !condition {
        print("FAIL: \(msg)")
        exit(1)
    }
}

func assertGT(_ a: Double, _ b: Double, _ msg: String) {
    if a <= b {
        print("FAIL: \(msg) — expected > \(b), got \(a)")
        exit(1)
    }
}

// MARK: - Main

let fixtureDir = URL(filePath: "fixtures/gcode")
let fixtures = ["rapid_only.nc", "square_air_10mm.nc"]

for fixtureName in fixtures {
    let fixtureURL = fixtureDir.appending(path: fixtureName)
    print("=== Testing \(fixtureName) ===")

    assertTrue(FileManager.default.fileExists(atPath: fixtureURL.path),
               "Fixture exists: \(fixtureURL.path)")

    let transport = SimulatorTransport()
    let streamer = GCodeStreamer()

    // Connect
    let config = SerialConfig(isSimulator: true)
    try await transport.open(config: config)

    // Initial state
    assertEqual(streamer.progress, 0.0, "Initial progress is 0")
    assertEqual(streamer.state, .idle, "Initial state is idle")

    // Load lines
    let lines = try await streamer.load(from: fixtureURL)
    assertGT(lines.count > 0, "Fixture has executable lines (\(lines.count))")
    print("  Loaded \(lines.count) executable lines")

    // Stream
    try await streamer.stream(lines: lines, to: transport)

    // Verify completion
    assertEqual(streamer.state, .idle, "State is idle after stream")
    assertEqual(streamer.progress, 1.0, "Progress is 1.0 at completion")
    assertEqual(streamer.currentLine, streamer.totalLines, "All lines sent")
    assertGT(streamer.totalLines, 0, "Total lines > 0")
    print("  Progress: 0 → \(streamer.progress) (\(streamer.currentLine)/\(streamer.totalLines) lines)")

    await transport.close()
    print("  PASS")
    print()
}

print("All fixture stream tests passed.")
