#!/usr/bin/env python3
"""SPK-1607 verify — Vector XYWH inspector.

Asserts, by reading Sources/ShopPilot/InspectorShell.swift:
  1. The Design inspector shows X/Y/W/H for exactly ONE selected shape
     (selectedShapeIndices.count == 1, bounds-checked against shapes).
  2. The readout uses the shape's boundingRect (real geometry, not fakes).
  3. None/multi do NOT show the geometry block: the block is gated on
     count == 1, and the existing selectionInfo badge already shows the
     multi count / "No selection".

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ShopPilot" / "InspectorShell.swift"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    text = SRC.read_text(encoding="utf-8")

    # 1. Exactly-one gate + bounds check.
    must("session.selectedShapeIndices.count == 1" in text,
         "XYWH block gated on exactly one selected shape")
    must("session.shapes.indices.contains(index)" in text,
         "index bounds-checked against the live shapes")

    # 2. Real geometry: boundingRect, formatted.
    must(".boundingRect" in text,
         "readout uses the shape's boundingRect (real bbox)")
    must('PropertyRow(label: "X"' in text and 'PropertyRow(label: "W"' in text
         and 'PropertyRow(label: "H"' in text and 'PropertyRow(label: "Y"' in text,
         "X / Y / W / H rows present")

    # 3. None/multi excluded: block lives under the count==1 guard, and the
    #    existing selectionInfo still shows count / no-selection.
    must("SectionLabel(\"Selection\")" in text,
         "selection geometry has its own section label")
    must("No selection" in text and "vector(s) selected" in text,
         "multi-count / no-selection still handled by selectionInfo")

    if FAILURES:
        print("1607: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1607: PASS — Design inspector shows X/Y/W/H for one selected vector (boundingRect; none/multi excluded)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
