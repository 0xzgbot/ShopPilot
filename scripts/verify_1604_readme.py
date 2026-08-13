#!/usr/bin/env python3
"""SPK-1604 verify — README current download is 0.05, not 0.03.

Asserts, by reading README.md:
  1. The Download section points at ShopPilot-0.05-macOS.zip (the current
     built release).
  2. No user-facing 0.03 zip is presented as the current download (the old
     "Download dist/ShopPilot-0.03-macOS.zip" line is gone).
  3. CHANGELOG mentions 0.05 (consistent with the release).
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
CHANGELOG = ROOT / "docs" / "planning" / "CHANGELOG.md"

FAILURES: list[str] = []


def must(cond: bool, msg: str) -> None:
    if not cond:
        FAILURES.append(msg)


def main() -> int:
    readme = README.read_text(encoding="utf-8")
    changelog = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else ""

    # 1. Download section points at 0.05.
    must("ShopPilot-0.05-macOS.zip" in readme,
         "README Download references ShopPilot-0.05-macOS.zip")

    # 2. No 0.03 as the current download.
    must("ShopPilot-0.03-macOS.zip" not in readme,
         "README no longer references the 0.03 zip as a download")

    # 3. Changelog has a 0.05 entry.
    must("## [0.05]" in changelog,
         "CHANGELOG has a 0.05 entry")

    if FAILURES:
        print("1604: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1604: PASS — README current download is 0.05 (not 0.03); changelog consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
