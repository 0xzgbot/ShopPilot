#!/usr/bin/env python3
"""SPK-1507 verify — Preview copy honesty.

Asserts, by reading Sources:
  1. ToolpathPreviewView.swift Camera help no longer claims a "live webcam
     feed over the preview" as if it were the cut sim — it is an optional
     reference overlay.
  2. MetalPreview.swift carries no user-facing "metal-backed preview" /
     GPU claim without an honesty note; the legacy scaffolding is labeled
     as such (not consumed by the live SwiftUI Canvas stage).
  3. The live preview still says what it is: the heightfield/wireframe sim
     copy stays (material picker help mentions heightfield preview).

Exit 0 + PASS line on success; non-zero with details on failure.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    preview = (ROOT / "Sources" / "ShopPilot" / "ToolpathPreviewView.swift").read_text(encoding="utf-8")
    metal = (ROOT / "Sources" / "ShopPilotCore" / "MetalPreview.swift").read_text(encoding="utf-8")

    # 1. Camera help is honest: overlay for reference, not the cut sim.
    must("live webcam feed over the preview" not in preview,
         "Camera help no longer claims a 'live webcam feed over the preview'")
    must("camera view over the sim as a reference" in preview,
         "Camera help describes an optional reference overlay")
    must("the cut sim itself is the wireframe below" in preview,
         "Camera help says the sim is the wireframe (not the camera)")

    # 2. MetalPreview: no un-nuanced metal-backed claim.
    # (Pass if the phrase is gone entirely, OR any remaining use is
    # immediately qualified by the honesty note.)
    has_claim = "metal-backed preview" in metal
    has_note = "does NOT use a Metal" in metal
    must(not has_claim or has_note,
         "MetalPreview has no un-nuanced 'metal-backed preview' claim")
    must("legacy scaffolding" in metal.lower(),
         "MetalPreview labels itself legacy scaffolding")
    must("Not consumed by the live SwiftUI Canvas Preview stage" in metal,
         "MetalPreview says it is not the live preview")

    # 3. Live preview copy intact (heightfield sim).
    must("heightfield preview" in preview,
         "Preview material help still calls it the heightfield preview")

    if FAILURES:
        print("1507: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1507: PASS — preview copy honesty (no Metal GPU claim; camera = reference overlay; heightfield sim labeled)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
