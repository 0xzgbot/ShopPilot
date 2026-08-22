#!/usr/bin/env python3
"""SPK-1900f structural gate: nesting wiring contract in AppSession + DesignCanvasView."""
import re, sys

APP = "Sources/ShopPilot/AppSession.swift"
CANVAS = "Sources/ShopPilot/DesignCanvasView.swift"

def struct_body(path, marker):
    src = open(path).read()
    i = src.find(marker)
    if i < 0:
        return None
    j = src.find("{", i)
    depth = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[i:k+1]
    return None

fails = []
def check(cond, msg):
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond:
        fails.append(msg)

body = struct_body(APP, "func nestShapesOnSheet")
check(body is not None, "nestShapesOnSheet exists in AppSession")
if body is None:
    body = ""

check("guard let sheet = activeSheet" in body, "gates on an active sheet")
check("ShapeGroupEngine.expandedSelection" in body, "selection is group-aware")
check("Array(shapes.indices)" in body, "empty selection nests ALL shapes")
check("NestingEngine.nest(parts:" in body, "calls the Geometry packer")
check("allowRotationGlobally: false" in body, "translation-only (rotation follow-up)")
check("registerUndoPoint()" in body, "undoable")
check("syncLayerVectors()" in body, "syncs layers after move")
check("markDirty()" in body, "marks document dirty")
check("case .doesNotFit" in body, "handles doesNotFit honestly")

canvas = open(CANVAS).read()
check('session.nestShapesOnSheet()' in canvas, "canvas toolbar button wired to session")
check('.accessibilityLabel("Nest shapes")' in canvas, "button has AX label (1800a/h discipline)")
check(".accessibilityAddTraits(.isButton)" in canvas, "icon button has isButton trait")
check(".disabled(session.shapes.isEmpty)" in canvas, "disabled when no shapes")

# engine contract spot-checks (Geometry file unchanged by wiring)
eng = open("Sources/ShopPilotGeometry/NestingEngine.swift").read()
check("public static func nest(" in eng, "shape-level nest present")
check("public static func nestGrid(" in eng, "grid variant present")
for t in ["NestingPart", "NestedPlacement", "NestingOptions", "NestingResult"]:
    check(f"struct {t}" in eng or f"enum {t}" in eng, f"{t} type present")

print()
if fails:
    print(f"verify_1900f_nesting: FAIL ({len(fails)} checks failed)")
    sys.exit(1)
print("verify_1900f_nesting: PASS — nesting wiring contract holds")
