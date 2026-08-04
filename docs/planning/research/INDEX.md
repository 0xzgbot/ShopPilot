# ShopPilot Research Index — Wave-2 (competitive capability research)

**Date:** 2026-08-04 · **Status:** all high-value tracks complete; two medium tracks prepared-but-blocked (interviews, Windows capture). All artifacts under `docs/planning/research/` (committed) + raw data under `research/raw/` (gitignored).

---

## Deliverables

| # | Doc | Answers | Key takeaway for ShopPilot |
|---|---|---|---|
| 1 | `GRBL_DIALECT_MATRIX.md` | Status grammar, `$` cmds, real-time chars, settings, error/alarm codes, FluidNC delta, ATC-vs-files | StatusParser + streamer ground truth; 6 golden fixture files in `research/raw/grbl_golden/` (spec-derived, swap for live captures when hardware lands) |
| 2 | `COMPETITOR_LEAN_CAM_TEARDOWN.md` | Carbide Create / Estlcam / Fusion Free / Candle-UGS minimal UI | Steal: material-preset→feeds auto-fill, built-in sender, post-at-save; avoid: wizard tax, 7-page CAM forms |
| 3 | `BIT_FEEDS_LIBRARY.md` | Onsrud/ShopBot chart + hobby starter tables; chip-load formula | Seed Tool DB matrix: 7 tools × 5 materials, per-material cutting data (geometry vs cutting-data split) |
| 4 | `FAILURE_MODE_LAB.md` | 20 failure modes (geometry/strategy/controller) → preflight rules + preview warnings | FM-06 V-carve punch-through, FM-07 fly-out, FM-12 tool-change collision are P0 warnings |
| 5 | `import_torture/` (README + 10 DXF + 2 SVG) | Deterministic validator fixtures: open/dupe/self-intersect/zero-span/units | Drop into ShopPilotTests when the importer+validator land; nested.dxf must pass clean |
| 6 | `POST_GRAMMAR_GRBL_CLASS.md` | GRBL-class post grammar + Shapeoko/Onefinity/OpenBuilds/FluidNC quirks | Canonical file skeleton, post options table, never-emit list (M6/G41/G28-in-job) |
| 7 | `SIGN_SHOP_OPERATOR_OPS.md` | Proxy evidence (zeroing failures, file-per-tool, preview culture) + 16-question interview guide | Z0 contract everywhere; file-per-tool + ordered naming is first-class |
| 8 | `ASPIRE_FORM_DEFAULTS_RUNSPEC.md` | Narrow Windows capture: Profile/V-Carve/3D Rough/Finish field defaults | Ready to paste on the Windows PC; merge results into FEATURE_PARITY_MATRIX §R |

## R-NEXT close-out deliverables (2026-08-05 — build-wave unblock specs)

| # | Doc | Purpose | Consumer |
|---|---|---|---|
| 9 | `PREFLIGHT_FM_MAPPING.md` | FM-01…FM-20 → existing rules (R001–R012) or NEW stubs (R013–R027); severity/trigger/copy/detection layer; P0 = FM-01/06/07/09/10/12 | preflight engine build (SPK-0211/0212/0307) |
| 10 | `TOOL_DB_SEED_SPEC.md` | Exact JSON/CSV schema + 7×5 starter matrix (feed/RPM/pass depth/stepover/plunge) with source keys; grayed-out UX | SPK-1146/1133 Tool DB seed |
| 11 | `STATUSPARSER_VERIFY_CHECKLIST.md` | 44 parser assertions over `research/raw/grbl_golden/` fixtures (B/S/D/E/T/F + X), 5 `[!]` live-HW items | ShopPilotVerify* StatusParser/streamer |
| 12 | `INTERVIEW_PACK.md` | One-page send-to-operator email + scoring sheet + coding table | human-unblock track |
| 13 | `ASPIRE_FORM_DEFAULTS_RESULTS.md` | Empty capture tables for the four forms + save summary | human-unblock track (merge → §R) |
| 14 | `NEXT_RESEARCH_REPORT.md` | R-NEXT close-out: counts, PASS evidence, blockers, work log | anyone |
| — | `scripts/verify_import_torture.py` | Checked-in stdlib verifier: 28 checks over `import_torture/` (PASS, exit 0) | fixture hygiene (run after edits)

## Cross-references to existing planning docs

- `FAILURE_MODE_LAB.md` extends `docs/planning/PREFLIGHT_RULES.md` (error-strings → machine-outcome layer).
- `GRBL_DIALECT_MATRIX.md` + `POST_GRAMMAR_GRBL_CLASS.md` ground `AGENTS.md` Track A (serial/streamer/posts).
- `BIT_FEEDS_LIBRARY.md` seeds LEAN_CNC_SCOPE P1 "Tool DB seed + feeds wired to recalc".
- `COMPETITOR_LEAN_CAM_TEARDOWN.md` informs the stage-rail UX (progressive disclosure; no wizard tax).
- Vectric Wave-1 research (`WHAT_IT_TAKES_CNC_APP.md`, `vectric_yt_wave1_report.md`) remains the core; this wave fills machine/post/preflight/import gaps.

## Blocked / needs human

| Item | Blocker | Unblock action |
|---|---|---|
| Sign-shop interviews (5–10) | recruiting real operators | Send the ready email + scoring sheet in `INTERVIEW_PACK.md`; proxy evidence in `SIGN_SHOP_OPERATOR_OPS.md` |
| Windows Aspire form-defaults capture | needs Windows PC + trial | Paste `ASPIRE_FORM_DEFAULTS_RUNSPEC.md` on the Windows PC; fill `ASPIRE_FORM_DEFAULTS_RESULTS.md`; merge into §R |
| Live GRBL/FluidNC RX captures | needs physical controller | Golden fixtures are spec-derived; 5 `[!]` assertions in `STATUSPARSER_VERIFY_CHECKLIST.md` §4 need a real controller |
| grbl_golden fixtures gitignored | decision | copy to `ShopPilotTests/Fixtures/grbl/` (checked in) or regenerate from the checklist — see `STATUSPARSER_VERIFY_CHECKLIST.md` §1 |

## Skipped / low ROI (per user direction)

Full Aspire feature-parity crawls · gadget catalogs · laser · cabinet · cloud tool DB · more YouTube marketing. Wave-2 transcripts only fetched for thin spots (chamfer allowance, bitmap trace — both enriched in `extractions/`); rest of Wave-2 backlog stays queued in `vectric_yt_catalog.csv`.
