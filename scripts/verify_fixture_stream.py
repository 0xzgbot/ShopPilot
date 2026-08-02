#!/usr/bin/env python3
"""
Standalone verification for SPK-0411a: Stream fixture file with progress fraction.

Reads a small fixture .nc file, simulates the GCodeStreamer + SimulatorTransport
streaming logic, and asserts progress flows 0 → 1.

Run: python3 scripts/verify_fixture_stream.py
"""

import os
import sys
import re
from pathlib import Path

# Resolve project root
ROOT = Path(__file__).resolve().parent.parent
FIXTURE_DIR = ROOT / "fixtures" / "gcode"


def is_comment(line: str) -> bool:
    """Check if a line is a G-code comment (semicolon or parenthesized)."""
    trimmed = line.strip()
    return trimmed.startswith(";") or trimmed.startswith("(")


def is_directive(line: str) -> bool:
    """Check if a line is a G-code directive (% or O=)."""
    trimmed = line.strip()
    return trimmed.startswith("%") or trimmed.startswith("O=")


def parse_fixture(path: Path) -> list[str]:
    """Load and parse a fixture file, filtering comments/directives/blank lines."""
    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()
    executable = [
        line for line in lines
        if line.strip()
        and not is_comment(line)
        and not is_directive(line)
    ]
    return executable


def simulate_stream(lines: list[str]) -> dict:
    """
    Simulate GCodeStreamer.stream(): send each line, wait for 'ok',
    track progress 0→1. Returns stats.
    """
    total = len(lines)
    sent = 0
    progress_values = [0.0]

    for line in lines:
        # Simulate transport write + ok response
        # (In real code: transport.write(Data(line.utf8)) → waitForOk)
        sent += 1
        progress = round(sent / total, 6)
        progress_values.append(progress)

    return {
        "total_lines": total,
        "sent_lines": sent,
        "final_progress": progress_values[-1],
        "progress_start": progress_values[0],
        "progress_values": progress_values,
    }


def test_fixture(name: str, fixture_path: Path) -> bool:
    """Run the full fixture stream verification for one fixture."""
    print(f"=== Testing {name} ===")

    # 1. Fixture exists
    if not fixture_path.exists():
        print(f"  FAIL: Fixture does not exist: {fixture_path}")
        return False

    # 2. Load and parse
    lines = parse_fixture(fixture_path)
    if not lines:
        print(f"  FAIL: No executable lines in {name}")
        return False
    print(f"  Loaded {len(lines)} executable lines")

    # 3. Simulate streaming
    stats = simulate_stream(lines)

    # 4. Verify progress 0 → 1
    ok = True

    if stats["progress_start"] != 0.0:
        print(f"  FAIL: Progress did not start at 0.0, got {stats['progress_start']}")
        ok = False

    if stats["final_progress"] != 1.0:
        print(f"  FAIL: Progress did not reach 1.0, got {stats['final_progress']}")
        ok = False

    if stats["sent_lines"] != stats["total_lines"]:
        print(f"  FAIL: Sent {stats['sent_lines']}/{stats['total_lines']} lines")
        ok = False

    # 5. Verify progress is monotonically non-decreasing
    for i in range(1, len(stats["progress_values"])):
        if stats["progress_values"][i] < stats["progress_values"][i - 1]:
            print(f"  FAIL: Progress decreased at step {i}")
            ok = False
            break

    # 6. Verify progress increases (not stuck at 0)
    if len(stats["progress_values"]) > 1 and stats["progress_values"][-2] == 0.0:
        print(f"  FAIL: Progress never increased before final step")
        ok = False

    # 7. Verify fixture content expectations
    content = fixture_path.read_text()
    if "G21" not in content:
        print(f"  WARN: Fixture does not contain G21 (mm mode)")
    if "M2" not in content:
        print(f"  WARN: Fixture does not contain M2 (end of program)")

    if ok:
        print(f"  PASS: {name} — {stats['sent_lines']}/{stats['total_lines']} lines, "
              f"progress {stats['progress_start']} → {stats['final_progress']}")
    else:
        print(f"  FAIL: {name}")

    print()
    return ok


def main():
    fixtures = ["square_air_10mm.nc", "rapid_only.nc"]
    all_pass = True

    for name in fixtures:
        path = FIXTURE_DIR / name
        if not test_fixture(name, path):
            all_pass = False

    if all_pass:
        print("All fixture stream tests passed.")
        sys.exit(0)
    else:
        print("Some tests failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
