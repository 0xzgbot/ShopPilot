#!/usr/bin/env python3
"""SPK-1602 verify — Appearance preference actually tints.

Asserts, by reading sources:
  1. ContentView applies .preferredColorScheme driven by the
     shop_pilot_theme @AppStorage, resolved through Core AppSettings.
  2. Core AppSettings.resolvedTheme maps light→.light, dark→.dark,
     system/unknown→nil (follow the OS).
  3. PreferencesView still offers the Light/Dark/System picker writing the
     same key.

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
    content = (ROOT / "Sources" / "ShopPilot" / "ContentView.swift").read_text(encoding="utf-8")
    prefs = (ROOT / "Sources" / "ShopPilot" / "PreferencesView.swift").read_text(encoding="utf-8")
    settings = (ROOT / "Sources" / "ShopPilotCore" / "AppSettings.swift").read_text(encoding="utf-8")

    # 1. preferredColorScheme on the window root, from the live preference.
    must(".preferredColorScheme(AppSettings.resolvedTheme(themePreference))" in content,
         "ContentView applies preferredColorScheme via AppSettings.resolvedTheme")
    must('@AppStorage("shop_pilot_theme")' in content,
         "ContentView mirrors the shop_pilot_theme preference (live updates)")

    # 2. Core resolver semantics.
    must('case "light": return .light' in settings
         and 'case "dark": return .dark' in settings,
         "AppSettings maps light/dark to color schemes")
    must("default: return nil" in settings,
         "system/unknown → nil (follow the OS)")

    # 3. Preferences picker still writes the same key.
    must('@AppStorage("shop_pilot_theme")' in prefs
         and 'Text("System").tag("system")' in prefs,
         "Preferences picker writes shop_pilot_theme (light/dark/system)")

    if FAILURES:
        print("1602: FAIL —")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("1602: PASS — Appearance picker tints the window (preferredColorScheme; System = nil)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
