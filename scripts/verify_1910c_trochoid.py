#!/usr/bin/env python3
"""SPK-1910c — Trochoid Slot structural gate.

Greps the worktree for the required SPK-1910 UI/structural surface:
  1. ContentView: "Trochoid Slot" Add control in the Cut stage More menu,
     with an accessibility label and .isButton trait.
  2. ContentView: a TrochoidSlotParamsForm wired to session.applyTrochoidSlotParams.
  3. SpecialtyParamsForms.swift: the form exists with all AC fields
     (D, depth, WOC, pitch, feed, plunge, safe Z, ramp toggle).
  4. Engine G-code marker O=TROCHOID_SLOT present in ShopPilotCore.
Exit 0 = PASS, 1 = FAIL.
"""
import re
import sys

ROOT = "Sources"
CONTENT_VIEW = f"{ROOT}/ShopPilot/ContentView.swift"
FORMS = f"{ROOT}/ShopPilot/SpecialtyParamsForms.swift"
ENGINE = f"{ROOT}/ShopPilotCore/TrochoidSlotToolpath.swift"

failures = []


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        failures.append(f"cannot read {path}: {exc}")
        return ""


cv = read(CONTENT_VIEW)
forms = read(FORMS)
engine = read(ENGINE)


def check(cond, label):
    if not cond:
        failures.append(label)


# ── 1. Cut-stage Add control (SPK-1910b) ──────────────────────────────────
check("Trochoid Slot\") { session.generateTrochoidSlotToolpath() }" in cv.replace("’", "'"),
      "ContentView: Cut menu item 'Trochoid Slot' calling generateTrochoidSlotToolpath()")
check('.accessibilityLabel("Trochoid Slot")' in cv,
      "ContentView: Add control has .accessibilityLabel(\"Trochoid Slot\")")
check(re.search(r'Trochoid Slot"\)\s*\{\s*session\.generateTrochoidSlotToolpath\(\)\s*\}[^}]*\.accessibilityAddTraits\(\.isButton\)',
                cv, re.S) is not None,
      "ContentView: Add control carries .accessibilityAddTraits(.isButton)")
check(re.search(r'if !beginnerMode \{[^}]*Trochoid Slot', cv, re.S) is not None,
      "ContentView: Trochoid Slot hidden in Beginner mode (!beginnerMode)")

# ── 2. Form wiring (SPK-1910b/c) ───────────────────────────────────────────
check("TrochoidSlotParamsForm(node: node)" in cv,
      "ContentView: node panel instantiates TrochoidSlotParamsForm")
check("session.applyTrochoidSlotParams" in cv or "applyTrochoidSlotParams(newParams" in cv,
      "ContentView: form Apply routes to session.applyTrochoidSlotParams")
check("func applyTrochoidSlotParams" in read(f"{ROOT}/ShopPilot/AppSession.swift"),
      "AppSession: applyTrochoidSlotParams exists")

# ── 3. The form itself + AC fields (SPK-1910c) ─────────────────────────────
check("struct TrochoidSlotParamsForm: View" in forms,
      "SpecialtyParamsForms: TrochoidSlotParamsForm view exists")
form_body = forms[forms.find("struct TrochoidSlotParamsForm"):] if "struct TrochoidSlotParamsForm" in forms else ""
for field_label, desc in [
    ("Tool Ø (mm)", "tool diameter D"),
    ("Cut depth (mm)", "cut depth"),
    ("Max WOC (mm)", "max radial engagement WOC"),
    ("Loop pitch (mm)", "loop pitch"),
    ("Feed (mm/min)", "feed rate"),
    ("Plunge (mm/min)", "plunge feed"),
    ("Safe Z (mm)", "safe Z height"),
]:
    check(field_label in form_body, f"Form field missing: {desc} ('{field_label}')")
check('Toggle(' in form_body, "Form has a Toggle (ramp entry)")
check("Apply Params — Regenerate" in form_body, "Form Apply button regenerates")

# ── 4. Engine marker ───────────────────────────────────────────────────────
check('O=TROCHOID_SLOT' in engine, "Engine emits the O=TROCHOID_SLOT header marker")

if failures:
    print("ShopPilotVerify1910c: FAIL")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)

print("ShopPilotVerify1910c: PASS — trochoid slot form + AX + structural gate "
      "(menu item, AX label + isButton, beginner-hidden, form fields, O=TROCHOID_SLOT)")
