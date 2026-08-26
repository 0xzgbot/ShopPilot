#!/usr/bin/env python3
"""SPK-1900c gate: Beginner/Advanced mode + starters wiring contract."""
import sys

def read(p):
    return open(p).read()

fails = []
def check(cond, msg):
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond:
        fails.append(msg)

settings = read("Sources/ShopPilot/AppSettings.swift")
content = read("Sources/ShopPilot/ContentView.swift")
prefs = read("Sources/ShopPilot/PreferencesView.swift")
palette = read("Sources/ShopPilot/CommandPaletteView.swift")
cmds = read("Sources/ShopPilot/Commands.swift")
welcome = read("Sources/ShopPilot/WelcomeSheetView.swift")

KEY = "shop_pilot_beginner_mode"

check(KEY in settings and "beginnerMode" in settings, "AppSettings owns the persisted mode")
check(KEY in content and "@AppStorage" in content, "Setup stage reads the same key")
check("beginnerMode ? true : !advancedExpanded" in content,
      "Beginner hides Advanced disclosure from AX (BUG-02 discipline preserved)")
check('.accessibilityLabel("Advanced")' in content and '.accessibilityIdentifier("setup.advanced")' in content,
      "Advanced AX identity intact for Advanced mode")
check(KEY in prefs and "Experience mode" in prefs, "Preferences exposes the mode switch")
check("Beginner" in prefs and "Advanced" in prefs, "both modes offered")

check("beginnerHiddenIDs" in cmds and ".importDWG" in cmds and ".importPDF" in cmds,
      "pro import formats hidden in Beginner ⌘K")
check("flatCommands(beginnerMode:" in cmds and "search(_ query: String, beginnerMode" in cmds,
      "registry filters by mode")
check(KEY in palette and "flatCommands(beginnerMode: beginnerMode)" in palette,
      "palette consumes the filtered list")

# SPK-2024a: the welcome landing carries ONLY sample starters + one primary
# "Plan the cuts" CTA + Import Artwork — the Photo starter moved off it. The
# lithophane path is still wired: it routes through generateLithophaneFromPanel
# from the Model stage.
check("Start from a Photo" not in welcome, "Photo starter off the landing (2024a single-CTA discipline)")
model_stage = read("Sources/ShopPilot/ModelStageView.swift")
check("generateLithophaneFromPanel()" in model_stage, "Photo starter lives in the Model stage")
check("generateLithophaneFromPanel()" not in welcome, "welcome no longer owns the photo path")
check("loadSampleProject(id:" in welcome, "sample starters intact")

print()
if fails:
    print(f"verify_1900c_mode: FAIL ({len(fails)})")
    sys.exit(1)
print("verify_1900c_mode: PASS — beginner/advanced mode + starters wired")
