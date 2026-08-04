# NEXT Research Report — R-NEXT close-out

**Date:** 2026-08-05 · **Predecessor:** Wave-2 research (`INDEX.md`). **Scope:** close the gaps that unblock Hermes build waves + the two human-blocked tracks. No new scraping; synthesis + specs + fixtures only.

## Deliverables & counts

| Card | Deliverable | Status | Evidence |
|---|---|---|---|
| R-NEXT-1 | `scripts/verify_import_torture.py` (stdlib-only, checked in) | ✅ | **28 checks PASS** (`RESULT: 28 checks, 0 failures`), exit 0. Run: `python3 scripts/verify_import_torture.py`. Run instructions added to `import_torture/README.md`. |
| R-NEXT-2 | `PREFLIGHT_FM_MAPPING.md` | ✅ | 20 FM rows mapped: 7 → existing rules (R001–R005, R008, R012), 13 → NEW rule stubs R013–R027. P0 rows: FM-01, 06, 07, 09, 10, 12. Detection layers: engine / preview / machine-preflight. |
| R-NEXT-3 | `TOOL_DB_SEED_SPEC.md` | ✅ | JSON + CSV schema (tools geometry × cutting_data per material×machine), full 7×5 matrix (feed/RPM/pass depth/stepover/plunge), 6 source citation keys, grayed-out UX spec. |
| R-NEXT-4 | `STATUSPARSER_VERIFY_CHECKLIST.md` | ✅ | 6 fixtures confirmed present in `research/raw/grbl_golden/`; 44 parser assertions (P0/P1) across B/S/D/E/T/F + 5 cross-cutting (X1–X5); 5 `[!]` live-hardware items flagged. |
| R-NEXT-5a | `INTERVIEW_PACK.md` | ✅ | One-page send-to-operator email + 16-question scoring sheet + post-interview coding table. No fabricated answers. |
| R-NEXT-5b | `ASPIRE_FORM_DEFAULTS_RESULTS.md` | ✅ | Empty capture tables for Profile / V-Carve / 3D Rough / 3D Finish + save summary; runspec cross-linked. |
| Report | `NEXT_RESEARCH_REPORT.md` | ✅ | this file |

## Fixture verifier detail (R-NEXT-1)

- 10 DXF + 2 SVG fixtures asserted against their README-claimed defect classes: open gap, tiny-gap tolerance, duplicate circles, offset-overlap, self-intersection, zero-length span, rect overlap, open-text path, nested-clean, `$INSUNITS` units, SVG structure (paths/circles/rects/groups/transforms/beziers).
- Same 28 checks as the previous ad-hoc pass — now reproducible via a checked-in script with `--dir`/`--list` options, exit-code contract (0 pass / 1 fail).
- Re-ran clean on the current fixtures (all 28 pass; the 3 fixture bugs fixed in the earlier pass stay fixed).

## Blockers

| Item | Status | Unblock |
|---|---|---|
| Sign-shop interviews (5–10 operators) | **Blocked — human** | Send `INTERVIEW_PACK.md` email; fill scoring sheets; merge into SIGN_SHOP_OPERATOR_OPS.md |
| Windows Aspire form-defaults capture | **Blocked — human/hardware** | Paste `ASPIRE_FORM_DEFAULTS_RUNSPEC.md` on the Windows PC; fill `ASPIRE_FORM_DEFAULTS_RESULTS.md`; merge into FEATURE_PARITY_MATRIX §R |
| Live GRBL/FluidNC RX validation | **Blocked — hardware `[!]`** | 5 `[!]` assertions in STATUSPARSER_VERIFY_CHECKLIST.md §4 need a real controller |
| grbl_golden fixtures gitignored | **Decision needed** | Copy to `ShopPilotTests/Fixtures/grbl/` (checked in) or regenerate from the checklist — flagged in STATUSPARSER_VERIFY_CHECKLIST.md §1 |

## Work log

Read PREFLIGHT_RULES.md (R001–R012, incl. R009 depth-clamp and R011/R012 ATC rules) and confirmed `scripts/` verify_* convention. Wrote the permanent stdlib-only fixture verifier (structured rewrite of the validated ad-hoc pass), ran it: 28/28 PASS, and added run docs to the fixtures README. Mapped all 20 failure modes to existing or new preflight rules with severity/trigger/copy/detection-layer (P0: FM-01/06/07/09/10/12). Wrote the Tool DB seed spec with full 7×5 matrix values and citation keys, the StatusParser verify checklist (44 assertions + live-HW flags), the interview pack, and the Aspire results template. No Swift sources touched; no new scraping; no media downloaded. INDEX.md updated with links to all six new docs.
