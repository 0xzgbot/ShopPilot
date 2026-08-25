#!/usr/bin/env python3
"""SPK-2010d — Valley group on the V-Carve params form.

Structural source-contract gate (no GUI needed):
  1. ContentView.swift carries a GroupBox "Valley" inside VCarveParamsForm.
  2. The form binds medialAxisPass / medialAxisCellMm / flatAreaClearing /
     flatAreaThresholdFactor / flatAreaStepOverMm (all five engine keys).
  3. Toggles expose accessibility labels; Apply regenerates via onApply.
  4. The group is unconditional (beginner mode keeps it visible) — no
     beginner-mode guard wraps the Valley GroupBox.
"""
import re
import sys

CV = "Sources/ShopPilot/ContentView.swift"

def main() -> int:
    src = open(CV, encoding="utf-8").read()

    # Locate VCarveParamsForm's struct body with a brace-counting scan
    # (non-greedy regex stops at the first inner closure — known trap).
    m = re.search(r"private struct VCarveParamsForm: View \{", src)
    if not m:
        print("FAIL — VCarveParamsForm struct not found")
        return 1
    start = m.end()
    depth = 1
    i = start
    while i < len(src) and depth > 0:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    body = src[start:i]

    checks = []

    def check(cond: bool, label: str) -> None:
        checks.append((cond, label))

    # 1. Valley GroupBox exists in the form.
    check('GroupBox("Valley")' in body, 'GroupBox("Valley") present')

    # 2. All five new params bound.
    check("$params.medialAxisPass" in body, "medialAxisPass toggle binding")
    check("$params.medialAxisCellMm" in body, "medialAxisCellMm field")
    check("$params.flatAreaClearing" in body, "flatAreaClearing toggle binding")
    check("$params.flatAreaThresholdFactor" in body, "flatAreaThresholdFactor field")
    check("$params.flatAreaStepOverMm" in body, "flatAreaStepOverMm field")

    # 3. Accessibility labels on both toggles + Apply regeneration hook.
    check('.accessibilityLabel("Medial axis pass")' in body, "medial toggle AX label")
    check('.accessibilityLabel("Flat area clearing")' in body, "flat toggle AX label")
    check("onApply(params)" in body, "Apply calls onApply(params)")

    # 4. Valley block is unconditional: it must not sit behind a
    #    beginner/pro conditional. Scan backwards from the GroupBox for a
    #    gating `if` at the same brace level — simplest honest proxy: the
    #    literal string GroupBox("Valley") appears directly in body, not
    #    only inside some `#if` or `if beginnerMode` branch.
    valley_idx = body.find('GroupBox("Valley")')
    prefix = body[:valley_idx]
    gated = re.findall(r"if\s+(beginnerMode|isPro|showAdvanced)[^\\n{]*\{", prefix[-400:])
    check(not gated, f"Valley not wrapped by mode gate ({gated or 'clean'})")

    failed = [label for ok, label in checks if not ok]
    for ok, label in checks:
        print(f"{'PASS' if ok else 'FAIL'} — {label}")
    if failed:
        print(f"verify_2010d_vcarve_quality: FAIL ({len(failed)} checks)")
        return 1
    print(f"verify_2010d_vcarve_quality: PASS ({len(checks)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
