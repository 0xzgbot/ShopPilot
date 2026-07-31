# ShopPilot Preflight Rules

**Source:** Vectric Aspire V12 error strings and validation messages, mapped to actionable preflight checks.
**Verified against:** [Vectric Aspire V12 Vector Validator docs](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/Vector%20Validator/index.html), [Save Toolpaths](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/Save%20Toolpaths/), [V-Carve Toolpath Creator](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/VCarve%20Toolpath%20Creator/index.html), [2D Profile Toolpath](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/uiProfileMachineForm/index.html), [Toolpath Tabs](https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/form/Toolpath%20Tabs/index.html)
**Verification date:** 2026-07-30
**Purpose:** Block toolpath generation on invalid geometry with plain-English fix CTAs.

---

## Verification Summary

| Status | Count | Description |
|--------|-------|-------------|
| ✅ Verified | 4 | Exact or near-exact Aspire error string confirmed in V12 docs |
| ⚠️ Partially Verified | 1 | Concept confirmed in Aspire but exact error string differs |
| ❌ Unverified | 5 | Concept is sound CAM practice but no Aspire error string found |

**Key confirmed Aspire error strings:**
- `"Ignoring unsuitable open vectors"` — official Vectric error for V-Carve on open vectors (confirmed via Vectric Instagram/Facebook posts, forum posts, and user-facing messaging)
- `"intersections"` — Vector Validator marks intersecting vectors (confirmed in Vector Validator form docs)
- `"zero-length spans"` — Vector Validator detects and fixes zero-length spans (confirmed in Vector Validator form docs)
- `"overlapping contours"` — Vector Validator detects overlapping vectors (confirmed in Vector Validator form docs)

**Key Aspire features confirmed but without explicit error strings:**
- Vector Validator "V-Carving Mode" — performs vector checks required for V-cutting
- Options Dialog: "If vector intersections are detected calculating a V-Carve or Pocket toolpath you can choose to be asked what to do next or to open the Vector Validator"
- Save Toolpaths: postprocessor checks ATC configuration and tool number uniqueness

---

## Rule Set

### R001 — Open Vector Gaps

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any polyline or arc where start ≠ end point within tolerance (1e-6 units) |
| **Aspire Equivalent** | **"Ignoring unsuitable open vectors"** ✅ Verified |
| **Plain English** | "This shape has a gap — the toolpath can't follow an open line." |
| **Fix CTA** | Show node handles at gap endpoints with "Close Gap" button (connects endpoints) |
| **Verification** | ✅ **Verified** — Exact string `"Ignoring unsuitable open vectors"` is the official Vectric error displayed when V-Carve toolpath encounters open vectors. Confirmed via Vectric's official social media posts, forum posts, and the Vector Validator docs which describe open vector detection. |

### R002 — Self-Intersecting Contours

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any shape where edges cross each other (line-line intersection within bounds) |
| **Aspire Equivalent** | **Vector Validator marks "intersections"** ✅ Verified (concept); original string `"Self-intersecting path may produce unexpected results"` was approximate |
| **Plain English** | "This shape crosses itself — the toolpath would cut in two places at once." |
| **Fix CTA** | Highlight intersecting segments, offer "Split at Intersections" (boolean union) |
| **Verification** | ✅ **Verified** — Vector Validator explicitly detects and marks "intersections" between vectors. The Options Dialog states: *"If vector intersections are detected calculating a V-Carve or Pocket toolpath you can choose to be asked what to do next or to open the Vector Validator."* The Design Doctor (Vector Doctor) also surfaces intersections. The exact phrasing in PREFLIGHT_RULES.md was approximate but the concept is confirmed. |

### R003 — Zero-Length Segments

| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Any line segment where start == end point exactly |
| **Aspire Equivalent** | **Vector Validator detects "zero-length spans"** ✅ Verified (terminology correction) |
| **Plain English** | "This is a zero-length line — it won't cut anything." |
| **Fix CTA** | Highlight and offer "Remove Zero-Length Segments" |
| **Verification** | ✅ **Verified** — Vector Validator explicitly detects and marks "zero-length spans." The form provides a "Fix zero length Spans" button that removes them. Release notes also reference: *"Prevent some cases of zero length span creation when node editing."* The original string `"Degenerate vector element"` was incorrect; Vectric uses "zero-length spans." |

### R004 — Duplicate / Overlapping Vectors

| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Two or more shapes occupying the same bounding box within tolerance |
| **Aspire Equivalent** | **Vector Validator detects "overlapping contours"** ⚠️ Partially Verified (terminology correction) |
| **Plain English** | "This shape is duplicated — you'll cut it twice." |
| **Fix CTA** | Highlight duplicates, offer "Merge Duplicates" (boolean weld) |
| **Verification** | ⚠️ **Partially Verified** — Vector Validator detects "overlapping contours" and the "Overlap Vectors" tool exists for merging overlapping closed vectors. However, Vectric's overlap detection is about vectors occupying the same space (which may be intentional, e.g., nested shapes), not about exact duplicate geometry. The original string `"Duplicate geometry detected"` was not found; Vectric uses "overlapping contours" / "overlap." The concept is valid but the trigger should be "overlapping contours" not "duplicate geometry." |

### R005 — Toolpath Outside Stock Bounds

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any toolpath segment outside the defined stock rectangle |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "This cut goes off your material — you'd cut into empty space." |
| **Fix CTA** | Highlight out-of-bounds segments, offer "Clip to Stock" or "Expand Stock" |
| **Verification** | ❌ **Unverified** — The release notes mention *"Fixed issue with zooming when vectors are extending way beyond the material bounds"* but this is about zoom behavior, not a toolpath error. The Keep-out Zones feature handles obstacles, not stock bounds. No explicit Aspire error string about toolpaths extending beyond material was found in V12 docs. This is sound CAM practice but not backed by a confirmed Aspire error string. |

### R006 — Zero Tool Diameter

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any toolpath using a tool with diameter ≤ 0 |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "This tool has no cutting edge — select an endmill or V-bit." |
| **Fix CTA** | Open tool database picker, pre-select valid tools |
| **Verification** | ❌ **Unverified** — The Save Toolpaths page mentions postprocessor checks for ATC: *"A different tool number has been defined for each different cutter being used."* But no explicit error string for zero/negative tool diameter was found in the Tool Database or toolpath forms. This is sound CAM practice but not backed by a confirmed Aspire error string. |

### R007 — No Tool Selected for Strategy

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Profile/Pocket/Drill/V-Carve strategy with no tool assigned |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "You haven't chosen a cutting tool for this operation." |
| **Fix CTA** | Open tool selector in the strategy panel |
| **Verification** | ❌ **Unverified** — All toolpath forms (Profile, V-Carve, Pocket, Drill, etc.) require a tool to be selected from the tool list. The toolpath calculation would fail without a tool, but no specific error string was found in the V12 docs. This is a reasonable preflight rule derived from general CAM practice. |

### R008 — Feed Rate Exceeds Machine Limit

| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Any feed rate exceeding the machine profile's max RPM or max travel speed |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "This cut is faster than your machine can handle." |
| **Fix CTA** | Show current vs. limit, offer "Reduce to Safe Speed" |
| **Verification** | ❌ **Unverified** — The Machine Configuration form and Tool Database define feed rate settings and machine limits. However, no explicit error string about feed rate exceeding machine capability was found in the V12 docs. The postprocessor generates feed rate commands but does not appear to validate against machine limits at toolpath time. |

### R009 — Depth Exceeds Stock Thickness

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any cutting depth deeper than the stock thickness setting |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "This cut goes through your entire piece — you'll damage the table." |
| **Fix CTA** | Show current vs. stock, offer "Reduce Depth" or "Expand Stock" |
| **Verification** | ❌ **Unverified** — The V-Carve and Profile forms note that when projecting onto a 3D model, *"its depth is limited so that it does not exceed the bottom of the material."* This is a soft limit (clamping), not an error. The Material Setup form defines stock thickness, but no explicit error string about depth exceeding stock was found. Aspire appears to clamp depth rather than error. |

### R010 — Tab Spacing Too Tight

| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Profile tabs spaced closer than the tool diameter apart |
| **Aspire Equivalent** | **No explicit error string found** ❌ Unverified |
| **Plain English** | "Your tabs are too close together — they might not hold the piece." |
| **Fix CTA** | Show tab layout, offer "Auto-Adjust Tab Spacing" |
| **Verification** | ❌ **Unverified** — The Toolpath Tabs form allows setting tab placement (constant number or constant distance). The form notes: *"It may not always be possible to avoid all corners, whilst trying to place the chosen number of tabs and have them spaced relatively evenly."* But no explicit error string about tabs being too close was found. Aspire allows any tab configuration. |

---

## Additional Verified Rules (Not in Original R001-R010)

### R011 — ATC Tool Number Uniqueness

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Multiple toolpaths using different cutters but assigned the same tool number in ATC mode |
| **Aspire Equivalent** | **"A different tool number has been defined for each different cutter being used"** ✅ Verified |
| **Plain English** | "Different cutters must have different tool numbers for automatic tool change." |
| **Fix CTA** | Open tool database to assign unique numbers |
| **Verification** | ✅ **Verified** — Explicitly stated in Save Toolpaths form: postprocessor checks that each different cutter has a different tool number when saving ATC files. |

### R012 — ATC Postprocessor Configuration

| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Saving ATC file with a postprocessor not configured for ATC commands |
| **Aspire Equivalent** | **Postprocessor ATC config check** ✅ Verified |
| **Plain English** | "Your postprocessor isn't set up for automatic tool changes." |
| **Fix CTA** | Select an ATC-capable postprocessor |
| **Verification** | ✅ **Verified** — Save Toolpaths form: *"The postprocessor automatically checks to ensure: It has been configured for saving files that include ATC commands."* An error message is displayed if this is not correct. |

---

## Preflight Check Flow

1. User clicks "Run Preflight" (or attempts to export)
2. System runs all rules against current geometry + toolpath settings
3. Results displayed in a panel:
   - **Errors** (red): Must fix before export
   - **Warnings** (yellow): Can override with confirmation
4. Each issue shows:
   - Plain English description
   - Visual highlight on the canvas
   - One-click fix CTA (where applicable)
5. Export button remains disabled until all errors are resolved

---

## Integration Points

- **SPK-0211**: Vector Preflight Doctor — implements R001-R004 checks in geometry kernel
- **SPK-0212**: Preflight plain-English fix actions — implements CTA buttons and canvas highlighting
- **SPK-0307**: Block export while dirty — integrates preflight into export gate
- **SPK-0604**: Preflight blocks V-Carve on open vectors with fix CTA — Phase G acceptance test
