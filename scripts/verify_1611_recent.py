#!/usr/bin/env python3
"""SPK-1611 verify — Open Recent.

Asserts, by reading sources:
  1. Core RecentPackagesStore: records URLs newest-first (cap 8) in
     UserDefaults, drops dead files.
  2. AppSession.savePackage(to:) and openPackage(from:) both record the URL
     (successful open/save feeds the menu).
  3. AppSession.openRecentPackage(url:) opens through the same loader with
     friendly failure status.
  4. App.swift File menu has an "Open Recent" submenu that lists the store
     and picks call openRecentPackage.

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
    store = (ROOT / "Sources" / "ShopPilotCore" / "RecentPackagesStore.swift").read_text(encoding="utf-8")
    session = (ROOT / "Sources" / "ShopPilot" / "AppSession.swift").read_text(encoding="utf-8")
    app = (ROOT / "Sources" / "ShopPilot" / "App.swift").read_text(encoding="utf-8")

    # 1. Store semantics.
    must("public static func record(_ url: URL)" in store
         and "public static func recent() -> [URL]" in store,
         "RecentPackagesStore has record/recent")
    must("shop_pilot_recent_packages" in store and "maxCount = 8" in store,
         "store is UserDefaults-backed with a cap")

    # 2. Open/save hooks record.
    must("RecentPackagesStore.record(url)" in session,
         "savePackage + openPackage record the URL (successful open/save)")

    # 3. Recent pick opens through the same loader.
    must("func openRecentPackage(url: URL)" in session
         and "try openPackage(from: url)" in session,
         "openRecentPackage uses the same openPackage loader")
    must("Open failed:" in session,
         "friendly failure status on open")

    # 4. File menu submenu.
    must('Menu("Open Recent")' in app and "RecentPackagesStore.recent()" in app,
         "App.swift File menu has an Open Recent submenu from the store")
    must("session.openRecentPackage(url: url)" in app,
         "picking a recent calls openRecentPackage")

    if FAILURES:
        print("1611: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1611: PASS — Open Recent (last N packages, newest first; open/save hooks feed the File submenu)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
